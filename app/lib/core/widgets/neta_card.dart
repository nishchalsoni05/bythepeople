import 'dart:math' as math;
import 'dart:ui' show FragmentProgram;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../device_tilt.dart';
import '../models.dart';
import '../tokens.dart';
import 'shaders.dart';

const _rarityIndex = {'unrated': 0, 'common': 1, 'rare': 2, 'epic': 3, 'legendary': 4};

class RarityStyle {
  final List<Color> colors;
  final Color glow;
  final String label;
  const RarityStyle(this.colors, this.glow, this.label);
}

RarityStyle rarityStyle(String rarity) {
  switch (rarity) {
    case 'legendary':
      return const RarityStyle([Color(0xFFF7C948), Color(0xFFF08A3C), Color(0xFFC8438C)], Color(0xFFFFC857), 'LEGENDARY');
    case 'epic':
      return const RarityStyle([Color(0xFF6A5BE2), Color(0xFF8E54D9), Color(0xFFE05AA5)], Color(0xFFB388FF), 'EPIC');
    case 'rare':
      return const RarityStyle([Color(0xFF2F80ED), Color(0xFF38B6E8), Color(0xFF63D6B6)], Color(0xFF6FD3FF), 'RARE');
    case 'common':
      return const RarityStyle([Color(0xFF7E7A72), Color(0xFFA39E94)], Color(0xFFD8D2C6), 'COMMON');
    default:
      return const RarityStyle([Color(0xFF6B7280), Color(0xFF9AA1AE)], Color(0xFFC9CED8), 'UNRATED');
  }
}

IconData levelIcon(String level) => switch (level) {
      'ward' => Icons.location_on_rounded,
      'mla' => Icons.account_balance_rounded,
      'mp' => Icons.how_to_vote_rounded,
      _ => Icons.workspace_premium_rounded,
    };

const double kCardRatio = 1.46;

/// Fractions of the card width so the layout and the foil mask always agree.
class _L {
  final double w;
  const _L(this.w);
  double get h => w * kCardRatio;
  double get pad => w * 0.055;
  Rect get art => Rect.fromLTWH(pad, w * 0.16, w - 2 * pad, w * 0.70);
  double get nameTop => w * 0.885;
  double get placeTop => w * 0.995;
  double get pillTop => w * 1.065;
  double get statsTop => w * 1.15;
  double get statsH => w * 0.25;
}

/// Collectible Neta card.
///
/// Physics: a single Ticker integrates a spring for the tilt (underdamped, so it
/// overshoots when you let go), a spring for the flip, and eased press / entrance
/// values. The foil shader reads the live tilt, so colour, parallax, glitter and
/// glare all follow the same motion as the card geometry.
class HoloNetaCard extends StatefulWidget {
  final Neta neta;
  final double width;
  final bool active; // only the focused card runs the idle animation
  final bool interactive; // false for cards waiting behind the top of a deck
  final bool entrance; // play the deal-in animation when first built
  final Offset tiltBias; // extra tilt injected by a parent, e.g. while it is being swiped
  final VoidCallback? onOpen;
  const HoloNetaCard({
    super.key, required this.neta, this.width = 280, this.active = true, this.interactive = true,
    this.entrance = true, this.tiltBias = Offset.zero, this.onOpen,
  });
  @override
  State<HoloNetaCard> createState() => HoloNetaCardState();
}

class HoloNetaCardState extends State<HoloNetaCard> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  Offset _tilt = Offset.zero, _vel = Offset.zero, _pointer = Offset.zero;
  bool _touching = false, _flipped = false, _reduceMotion = false, _holdsSensors = false;
  double _flipP = 0, _flipV = 0, _press = 0, _enter = 0, _sweep = -1, _flashCooldown = 0;
  final _frame = ValueNotifier<int>(0);

  _L get L => _L(widget.width);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.active) _sweep = 0;
    if (!widget.entrance) _enter = 1;
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "Reduce Motion" setting: no sensors, no idle sway.
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncSensors();
  }

  /// Only the focused card listens to the motion sensors.
  void _syncSensors() {
    final want = widget.active && !_reduceMotion;
    if (want && !_holdsSensors) {
      DeviceTilt.instance.acquire();
      _holdsSensors = true;
    } else if (!want && _holdsSensors) {
      DeviceTilt.instance.release();
      _holdsSensors = false;
    }
  }

  @override
  void didUpdateWidget(HoloNetaCard old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _sweep = 0; // reveal sweep each time the card comes into focus
      _wake();
    } else if (!widget.active && old.active) {
      if (_flipped) _flipped = false; // flip back when it leaves focus
      _wake();
    }
    _syncSensors();
  }

  /// Flips the card (used by the deck's flip button).
  void flip() {
    _flipped = !_flipped;
    HapticFeedback.lightImpact();
    if (!_flipped) _sweep = 0;
    _wake();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    if (_holdsSensors) DeviceTilt.instance.release();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    dt = dt.clamp(0.0, 0.05);
    _time += dt;

    final motion = DeviceTilt.instance;
    final sensor = (_holdsSensors && motion.available) ? motion.tilt : Offset.zero;
    final Offset target;
    if (_touching) {
      target = _pointer + sensor * 0.4;
    } else if (widget.active && !_reduceMotion) {
      // With a real motion sensor the phone drives the card; the gentle sway only fills in
      // when there is no sensor (simulator, desktop) so the foil still feels alive.
      final sway = motion.available ? 0.12 : 1.0;
      target = Offset(math.sin(_time * 0.7) * 0.42 * sway, math.cos(_time * 0.5) * 0.28 * sway) + sensor * 1.15;
    } else {
      target = Offset.zero;
    }
    // Flick the phone (gyroscope angular speed) and a flash of light runs across the foil.
    _flashCooldown = math.max(0, _flashCooldown - dt);
    if (_holdsSensors && motion.energy > 3.2 && _flashCooldown == 0 && _sweep < 0) {
      _sweep = 0;
      _flashCooldown = 1.4;
    }
    final biased = target + widget.tiltBias;
    final k = _touching ? 240.0 : 110.0;
    final c = _touching ? 24.0 : 10.0; // released: damping ratio ~0.5 -> springy overshoot
    final acc = (biased - _tilt) * k - _vel * c;
    _vel += acc * dt;
    _tilt += _vel * dt;

    final ft = _flipped ? 1.0 : 0.0;
    _flipV += ((ft - _flipP) * 110 - _flipV * 14) * dt;
    _flipP += _flipV * dt;

    _press += ((_touching ? 1.0 : 0.0) - _press) * (1 - math.exp(-dt * 12));
    if (_enter < 1) _enter = math.min(1, _enter + dt / 0.9);
    if (_sweep >= 0) {
      _sweep += dt / 1.15;
      if (_sweep > 1.25) _sweep = -1;
    }
    _frame.value++;

    final settled = !widget.active && !_touching && widget.tiltBias == Offset.zero && _tilt.distance < 0.003 && _vel.distance < 0.02 &&
        (_flipP - ft).abs() < 0.002 && _flipV.abs() < 0.02 && _enter >= 1 && _sweep < 0 && _press < 0.01;
    if (settled) _ticker.stop();
  }

  Offset _norm(Offset p) {
    final l = L;
    return Offset((((p.dx / l.w) - 0.5) * 2).clamp(-1.0, 1.0), (((p.dy / l.h) - 0.5) * 2).clamp(-1.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final l = L;
    final n = widget.neta;
    final style = rarityStyle(n.stats.rarity);
    return RepaintBoundary(
      child: SizedBox(
        width: l.w,
        height: l.h + 34,
        child: Listener(
          // Raw pointer events keep tilting from fighting a parent PageView swipe.
          onPointerDown: (e) {
            if (!widget.interactive) return;
            _touching = true;
            _pointer = _norm(e.localPosition);
            _wake();
          },
          onPointerMove: (e) => _pointer = _norm(e.localPosition),
          onPointerUp: (_) => _touching = false,
          onPointerCancel: (_) => _touching = false,
          child: GestureDetector(
            onTap: widget.interactive ? flip : null,
            onLongPress: widget.interactive ? widget.onOpen : null,
            child: AnimatedBuilder(
              animation: _frame,
              builder: (context, _) {
                final enterT = Curves.easeOutBack.transform(_enter.clamp(0.0, 1.0));
                final bob = widget.active ? math.sin(_time * 1.4) * 4.0 : 0.0;
                final flipAngle = _flipP * math.pi;
                final showBack = flipAngle > math.pi / 2;
                final lift = 1 + 0.06 * math.sin(math.pi * _flipP.clamp(0.0, 1.0));
                final scale = (0.86 + 0.14 * enterT) * (1 + 0.035 * _press) * lift;
                final m = Matrix4.identity()
                  ..setEntry(3, 2, 0.0011)
                  ..translateByDouble(0.0, bob, 0.0, 1.0)
                  ..rotateZ((1 - enterT.clamp(0.0, 1.0)) * -0.08)
                  ..rotateX(_tilt.dy * 0.20)
                  ..rotateY(-_tilt.dx * 0.20 + flipAngle)
                  ..scaleByDouble(scale, scale, 1.0, 1.0);
                final tilt = Offset(_tilt.dx.clamp(-1.4, 1.4), _tilt.dy.clamp(-1.4, 1.4));
                return Stack(alignment: Alignment.topCenter, children: [
                  // ground shadow reacts to tilt and press
                  Positioned(
                    top: 8,
                    child: Opacity(
                      opacity: enterT.clamp(0.0, 1.0),
                      child: Container(
                        width: l.w,
                        height: l.h,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.30 + 0.12 * _press),
                              blurRadius: 36 - 8 * _press,
                              spreadRadius: -10,
                              offset: Offset(tilt.dx * 20, 30 - bob - tilt.dy * 6),
                            ),
                            BoxShadow(color: style.glow.withValues(alpha: 0.10 + 0.10 * _press), blurRadius: 60, spreadRadius: -20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: m,
                      child: SizedBox(
                        width: l.w,
                        height: l.h,
                        child: showBack
                            ? Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.rotationY(math.pi),
                                child: _Back(neta: n, style: style, l: l, tilt: Offset(-tilt.dx, tilt.dy), time: _time))
                            : _Front(neta: n, style: style, l: l, tilt: tilt, time: _time, sweep: _sweep),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- front face

class _Front extends StatelessWidget {
  final Neta neta;
  final RarityStyle style;
  final _L l;
  final Offset tilt;
  final double time, sweep;
  const _Front({required this.neta, required this.style, required this.l, required this.tilt, required this.time, required this.sweep});

  TextStyle _t(double size, {double w = 600, double a = 1}) =>
      ui(size, color: Colors.white.withValues(alpha: a), w: w).copyWith(shadows: const [Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 1))]);

  @override
  Widget build(BuildContext context) {
    final s = neta.stats;
    final w = l.w;
    final art = l.art;
    final rate = s.rate;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: style.colors, begin: Alignment.topLeft, end: Alignment.bottomRight))),
        CustomPaint(painter: _BackdropPainter(neta.id)),
        // header
        Positioned(
          left: l.pad, right: l.pad, top: l.pad,
          height: w * 0.075,
          child: Row(children: [
            Flexible(
              child: _Glass(
                padding: EdgeInsets.symmetric(horizontal: w * 0.03),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(levelIcon(neta.level), size: w * 0.042, color: Colors.white),
                    SizedBox(width: w * 0.012),
                    Text(neta.levelLabel.toUpperCase(), maxLines: 1, style: _t(w * 0.031, w: 800).copyWith(letterSpacing: 0.8)),
                  ]),
                ),
              ),
            ),
            SizedBox(width: w * 0.03),
            Icon(Icons.diamond_outlined, size: w * 0.045, color: Colors.white),
            SizedBox(width: w * 0.012),
            Text(style.label, maxLines: 1, style: _t(w * 0.03, w: 800).copyWith(letterSpacing: 1.2)),
          ]),
        ),
        // art window
        Positioned.fromRect(
          rect: art,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(fit: StackFit.expand, children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [hueColor(neta.hue, s: 0.50, l: 0.68), hueColor(neta.hue + 55, s: 0.46, l: 0.48), hueColor(neta.hue + 110, s: 0.44, l: 0.34)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
              ),
              CustomPaint(painter: _GuillochePainter(neta.id)),
              Center(child: _Emblem(initials: _initials(neta.name), size: art.width * 0.40)),
              // inner shadow so the window feels recessed
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.6),
                  gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.18), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: 0.12)], stops: const [0, 0.18, 0.8, 1], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                ),
              ),
            ]),
          ),
        ),
        // identity
        Positioned(
          left: l.pad + 2, right: l.pad, top: l.nameTop, height: w * 0.11,
          child: FittedBox(
            alignment: Alignment.centerLeft, fit: BoxFit.scaleDown,
            child: Text(neta.name, style: display(w * 0.088, color: Colors.white, w: 640).copyWith(shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 1))])),
          ),
        ),
        Positioned(
          left: l.pad + 2, right: l.pad, top: l.placeTop, height: w * 0.055,
          child: Row(children: [
            Icon(Icons.place_rounded, size: w * 0.043, color: Colors.white70),
            SizedBox(width: w * 0.01),
            Expanded(child: Text(neta.constituency, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(w * 0.043, w: 650, a: 0.92))),
          ]),
        ),
        Positioned(
          left: l.pad, right: l.pad, top: l.pillTop, height: w * 0.062,
          child: Row(children: [
            Flexible(child: _Glass(padding: EdgeInsets.symmetric(horizontal: w * 0.028), child: Text(neta.party, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(w * 0.034, w: 700)))),
            SizedBox(width: w * 0.02),
            if (neta.jurisdiction.isNotEmpty)
              Flexible(child: _Glass(padding: EdgeInsets.symmetric(horizontal: w * 0.028), child: Text(neta.jurisdiction, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(w * 0.034, w: 700, a: 0.9)))),
          ]),
        ),
        // stats
        Positioned(
          left: l.pad, right: l.pad, top: l.statsTop, height: l.statsH,
          child: _Glass(
            radius: 18, tint: 0.20,
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: Row(children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _Stat('${s.reported}', 'Reported', w),
                    _Stat('${s.resolved}', 'Resolved', w),
                    _Stat('${s.open}', 'Open', w),
                  ]),
                ),
              ),
              SizedBox(width: w * 0.02),
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(
                  width: w * 0.155, height: w * 0.155,
                  child: CustomPaint(painter: _RingPainter(rate), child: Center(child: Text(rate == null ? '—' : '${(rate * 100).round()}', style: _t(w * 0.05, w: 800)))),
                ),
                SizedBox(height: w * 0.008),
                Text(rate == null ? 'Unrated' : 'Rate', style: _t(w * 0.028, w: 700, a: 0.85)),
              ]),
            ]),
          ),
        ),
        // holographic foil: colour layer then light layer
        if (ShaderLib.holo != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FoilPainter(ShaderLib.holo!, time, tilt, (_rarityIndex[neta.stats.rarity] ?? 0).toDouble(), art, l, sweep, neta.id.toDouble()),
              ),
            ),
          ),
        // bezel: outer sheen + inner keyline
        IgnorePointer(child: CustomPaint(painter: _BezelPainter())),
      ]),
    );
  }

  String _initials(String n) {
    final p = n.split(' ');
    return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius, tint;
  const _Glass({required this.child, this.padding = EdgeInsets.zero, this.radius = 20, this.tint = 0.22});
  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: tint),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1),
        ),
        child: child,
      );
}

class _Stat extends StatelessWidget {
  final String v, l;
  final double w;
  const _Stat(this.v, this.l, this.w);
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(right: w * 0.045),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: display(w * 0.082, color: Colors.white, w: 650).copyWith(shadows: const [Shadow(color: Color(0x55000000), blurRadius: 6)])),
          Text(l, style: ui(w * 0.028, color: Colors.white.withValues(alpha: 0.85), w: 700)),
        ]),
      );
}

class _Emblem extends StatelessWidget {
  final String initials;
  final double size;
  const _Emblem({required this.initials, required this.size});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: const Alignment(-0.4, -0.5), colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.14)]),
          border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Text(initials, style: display(size * 0.42, color: Colors.white, w: 650).copyWith(shadows: const [Shadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 2))])),
      );
}

// ---------------------------------------------------------------- painters

class _BackdropPainter extends CustomPainter {
  final int seed;
  _BackdropPainter(this.seed);
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    for (var i = 0; i < 3; i++) {
      final c = Offset(size.width * (0.15 + r.nextDouble() * 0.7), size.height * (0.1 + r.nextDouble() * 0.8));
      canvas.drawCircle(c, size.width * (0.35 + r.nextDouble() * 0.25),
          Paint()..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: size.width * 0.6)));
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter o) => o.seed != seed;
}

/// Engraved banknote-style pattern for the art window.
class _GuillochePainter extends CustomPainter {
  final int seed;
  _GuillochePainter(this.seed);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.24);
    final off = (seed % 7) * 0.05;
    for (var i = 0; i < 18; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * math.pi / 18 + off);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: size.width * 0.98, height: size.height * (0.30 + (seed % 3) * 0.03)), line);
      canvas.restore();
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Colors.white.withValues(alpha: 0.16);
    for (var r = 1; r <= 7; r++) {
      canvas.drawCircle(c, size.shortestSide * 0.085 * r, ring);
    }
    final ray = Paint()
      ..strokeWidth = 0.7
      ..color = Colors.white.withValues(alpha: 0.10);
    for (var i = 0; i < 48; i++) {
      final a = i * math.pi * 2 / 48;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * size.shortestSide * 0.26, c + Offset(math.cos(a), math.sin(a)) * size.longestSide, ray);
    }
    // dotted halo
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.5);
    for (var i = 0; i < 36; i++) {
      final a = i * math.pi * 2 / 36;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * size.shortestSide * 0.31, 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(_GuillochePainter o) => o.seed != seed;
}

class _RingPainter extends CustomPainter {
  final double? rate;
  _RingPainter(this.rate);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.095
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, p..color = Colors.white.withValues(alpha: 0.25));
    if (rate != null) {
      canvas.drawArc(r, -math.pi / 2, math.pi * 2 * rate!, false, p..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.rate != rate;
}

class _BezelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(26));
    canvas.drawRRect(
      outer.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0.9), Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      outer.deflate(7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.28),
    );
  }

  @override
  bool shouldRepaint(_BezelPainter o) => false;
}

class _FoilPainter extends CustomPainter {
  final FragmentProgram program;
  final double time, rarity, sweep, seed;
  final Offset tilt;
  final Rect? art;
  final _L l;
  _FoilPainter(this.program, this.time, this.tilt, this.rarity, this.art, this.l, this.sweep, this.seed);

  void _set(dynamic s, Size size, double pass) {
    s
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, tilt.dx)
      ..setFloat(4, tilt.dy)
      ..setFloat(5, rarity)
      ..setFloat(6, pass)
      ..setFloat(7, art == null ? 0 : art!.left / l.w)
      ..setFloat(8, art == null ? 0 : art!.top / l.h)
      ..setFloat(9, art == null ? 0 : art!.width / l.w)
      ..setFloat(10, art == null ? 0 : art!.height / l.h)
      ..setFloat(11, sweep)
      ..setFloat(12, seed * 1.7 + 3.1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (rarity < 0.5) return; // unrated cards stay matte
    final rect = Offset.zero & size;
    final colour = program.fragmentShader();
    _set(colour, size, 0);
    canvas.drawRect(rect, Paint()..shader = colour..blendMode = BlendMode.hardLight);
    final light = program.fragmentShader();
    _set(light, size, 1);
    canvas.drawRect(rect, Paint()..shader = light..blendMode = BlendMode.plus);
  }

  @override
  bool shouldRepaint(_FoilPainter o) => true;
}

// ---------------------------------------------------------------- back face

class _Back extends StatelessWidget {
  final Neta neta;
  final RarityStyle style;
  final _L l;
  final Offset tilt;
  final double time;
  const _Back({required this.neta, required this.style, required this.l, required this.tilt, required this.time});

  @override
  Widget build(BuildContext context) {
    final s = neta.stats;
    final w = l.w;
    TextStyle t(double size, {double wt = 600, double a = 1}) =>
        ui(size, color: Colors.white.withValues(alpha: a), w: wt).copyWith(shadows: const [Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 1))]);
    Widget row(String label, String value) => Padding(
          padding: EdgeInsets.symmetric(vertical: w * 0.016),
          child: Row(children: [
            Expanded(child: Text(label, style: t(w * 0.043, wt: 600, a: 0.85))),
            Text(value, style: t(w * 0.05, wt: 800)),
          ]),
        );
    final total = math.max(1, s.reported);
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: style.colors.reversed.map((c) => Color.lerp(c, Colors.black, 0.28)!).toList(), begin: Alignment.topRight, end: Alignment.bottomLeft),
          ),
        ),
        CustomPaint(painter: _BackdropPainter(neta.id + 91)),
        Padding(
          padding: EdgeInsets.all(l.pad * 1.5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Track record', style: display(w * 0.085, color: Colors.white, w: 640)),
            SizedBox(height: w * 0.008),
            Text('${neta.levelLabel} · ${neta.jurisdictionLong}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t(w * 0.036, wt: 650, a: 0.8)),
            SizedBox(height: w * 0.04),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: w * 0.034,
                child: Row(children: [
                  Expanded(flex: math.max(1, s.resolved * 100 ~/ total), child: Container(color: const Color(0xFFC8DB7A))),
                  Expanded(flex: math.max(0, s.open * 100 ~/ total), child: Container(color: Colors.white.withValues(alpha: 0.35))),
                ]),
              ),
            ),
            SizedBox(height: w * 0.03),
            row('Issues reported', '${s.reported}'),
            row('Resolved', '${s.resolved}'),
            row('Still open', '${s.open}'),
            row('Critical and open', '${s.criticalOpen}'),
            row('Avg days to resolve', s.avgDays == null ? '—' : s.avgDays!.toStringAsFixed(1)),
            row('Severity-weighted rate', s.rate == null ? 'n/a' : '${(s.rate! * 100).round()}%'),
            const Spacer(),
            if (!s.sampleOk) Text('Rated after ${s.minSample} issues, so one lucky fix can never skew a score.', style: t(w * 0.034, wt: 600, a: 0.78)),
            if (neta.parent != null) ...[
              SizedBox(height: w * 0.02),
              Text('Reports to ${neta.parent!.name}', style: t(w * 0.04, wt: 750)),
            ],
            SizedBox(height: w * 0.01),
            Text('Tap to flip back', style: t(w * 0.03, wt: 600, a: 0.6)),
          ]),
        ),
        if (ShaderLib.holo != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _FoilPainter(ShaderLib.holo!, time, tilt, math.max(1, (_rarityIndex[neta.stats.rarity] ?? 0).toDouble() - 1), null, l, -1, neta.id.toDouble())),
            ),
          ),
        IgnorePointer(child: CustomPaint(painter: _BezelPainter())),
      ]),
    );
  }
}
