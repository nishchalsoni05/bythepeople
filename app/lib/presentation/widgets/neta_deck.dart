import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/neta_card.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Vertical room the stack needs around the card: shadow/bob room (34) + the cards peeking out below.
double deckPeek(bool compact) => compact ? 16 : 30;
double deckExtra(bool compact) => 34 + deckPeek(compact);
double deckControlsHeight(bool compact) => compact ? 64 : 84;

/// Largest card width that lets the whole deck (stack + controls) fit in [maxHeight].
double deckCardWidth({required double maxWidth, required double maxHeight, bool compact = false}) {
  final byHeight = (maxHeight - deckExtra(compact) - deckControlsHeight(compact)) / kCardRatio;
  return math.max(compact ? 140.0 : 168.0, math.min(math.min(maxWidth * 0.78, 330.0), byHeight));
}

/// Tinder-style stack of Neta cards.
///  * drag the top card: it follows your finger, rotates, and the foil reacts to the motion
///  * fling it sideways: it flies off and goes to the back of the deck (the deck loops)
///  * fling it up, or tap Open: opens the leader's page
///  * tap the card or Flip: flips it
///  * Undo: the last card flies back in from the side it left
class NetaDeck extends StatefulWidget {
  final List<Neta> items;
  final double cardWidth;
  final ValueChanged<Neta> onOpen;
  final ValueChanged<int>? onTopChanged;
  final bool compact; // short screens: tighter stack and smaller controls
  const NetaDeck({super.key, required this.items, required this.cardWidth, required this.onOpen, this.onTopChanged, this.compact = false});
  @override
  State<NetaDeck> createState() => _NetaDeckState();
}

enum _Mode { idle, dragging, flying, returning }

class _NetaDeckState extends State<NetaDeck> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _top = 0;
  final List<int> _sides = []; // sides of dismissed cards, for undo
  Offset _off = Offset.zero, _vel = Offset.zero, _target = Offset.zero;
  _Mode _mode = _Mode.idle;
  int _flySide = 1;
  bool _openAfter = false;
  final _frame = ValueNotifier<int>(0);
  final _topKey = GlobalKey<HoloNetaCardState>();

  double get w => widget.cardWidth;
  double get h => w * kCardRatio;
  int get n => widget.items.length;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void didUpdateWidget(NetaDeck old) {
    super.didUpdateWidget(old);
    if (_top >= n) _top = 0;
    if (old.items.length != n || (n > 0 && old.items.isNotEmpty && old.items.first.id != widget.items.first.id)) {
      _top = 0;
      _sides.clear();
      _off = Offset.zero;
      _mode = _Mode.idle;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    dt = dt.clamp(0.0, 0.05);
    if (_mode == _Mode.flying || _mode == _Mode.returning) {
      final k = _mode == _Mode.flying ? 70.0 : 190.0;
      final c = _mode == _Mode.flying ? 12.0 : 21.0; // returning is underdamped: it settles with a little wobble
      final acc = (_target - _off) * k - _vel * c;
      _vel += acc * dt;
      _off += _vel * dt;
      if (_mode == _Mode.flying && _off.dx.abs() > w * 1.25) {
        _finishFly();
      } else if (_mode == _Mode.returning && (_target - _off).distance < 0.6 && _vel.distance < 8) {
        _off = _target;
        _vel = Offset.zero;
        _mode = _Mode.idle;
        if (_openAfter) {
          _openAfter = false;
          widget.onOpen(widget.items[_top]);
        }
      }
    }
    _frame.value++;
    if (_mode == _Mode.idle) _ticker.stop();
  }

  void _finishFly() {
    setState(() {
      _sides.add(_flySide);
      _top = (_top + 1) % n; // counter + undo state live outside the per-frame builder
      _off = Offset.zero;
      _vel = Offset.zero;
      _mode = _Mode.idle;
    });
    widget.onTopChanged?.call(_top);
    HapticFeedback.selectionClick();
  }

  // ---- gestures
  void _panStart(DragStartDetails d) {
    _mode = _Mode.dragging;
    _vel = Offset.zero;
    _wake();
  }

  void _panUpdate(DragUpdateDetails d) {
    _off += d.delta;
    _frame.value++;
  }

  void _panEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    if (_off.dx.abs() > w * 0.30 || v.dx.abs() > 850) {
      _fling(_off.dx != 0 ? _off.dx.sign.toInt() : v.dx.sign.toInt(), v);
    } else if (_off.dy < -h * 0.28 || v.dy < -950) {
      _openAfter = true;
      _goBack();
    } else {
      _goBack();
    }
  }

  void _fling(int side, Offset v) {
    _flySide = side == 0 ? 1 : side;
    _mode = _Mode.flying;
    _target = Offset(_flySide * w * 1.9, _off.dy + math.max(-120, math.min(120, v.dy * 0.12)));
    _vel = Offset(v.dx.clamp(-2600.0, 2600.0), v.dy.clamp(-1200.0, 1200.0));
    HapticFeedback.mediumImpact();
    _wake();
  }

  void _goBack() {
    _mode = _Mode.returning;
    _target = Offset.zero;
    _wake();
  }

  void _undo() {
    if (_sides.isEmpty || _mode == _Mode.flying) return;
    late int side;
    setState(() {
      side = _sides.removeLast();
      _top = (_top - 1 + n) % n;
      _off = Offset(side * w * 1.6, -h * 0.05);
      _vel = Offset.zero;
      _mode = _Mode.returning;
      _target = Offset.zero;
    });
    widget.onTopChanged?.call(_top);
    HapticFeedback.lightImpact();
    _wake();
  }

  void _open() {
    if (_mode == _Mode.idle) widget.onOpen(widget.items[_top]);
  }

  @override
  Widget build(BuildContext context) {
    if (n == 0) return const SizedBox.shrink();
    final cardBoxH = h + 34;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: double.infinity,
        height: cardBoxH + deckPeek(widget.compact),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: _panStart,
          onPanUpdate: _panUpdate,
          onPanEnd: _panEnd,
          onPanCancel: () {
            if (_mode == _Mode.dragging) _goBack();
          },
          child: AnimatedBuilder(
            animation: _frame,
            builder: (context, _) {
              final p = (_off.dx.abs() / (w * 0.9)).clamp(0.0, 1.0);
              final tiltBias = Offset((_off.dx / w * 1.7).clamp(-1.3, 1.3), (_off.dy / h * 1.2).clamp(-1.0, 1.0));
              final depth = math.min(3, n);
              return Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                for (var k = depth - 1; k >= 0; k--) _slot(k, p, tiltBias),
              ]);
            },
          ),
        ),
      ),
      SizedBox(height: widget.compact ? 4 : 10),
      _Controls(
        compact: widget.compact,
        position: '${_top + 1} / $n',
        canUndo: _sides.isNotEmpty,
        onUndo: _undo,
        onFlip: () => _topKey.currentState?.flip(),
        onOpen: _open,
      ),
    ]);
  }

  Widget _slot(int k, double p, Offset tiltBias) {
    final item = widget.items[(_top + k) % n];
    double scale, dy, opacity;
    if (k == 0) {
      scale = 1;
      dy = 0;
      opacity = 1;
    } else if (k == 1) {
      scale = lerp(0.935, 1, p);
      dy = lerp(deckPeek(widget.compact) * 0.6, 0, p);
      opacity = lerp(0.92, 1, p);
    } else {
      scale = lerp(0.87, 0.935, p);
      dy = lerp(deckPeek(widget.compact) * 1.2, deckPeek(widget.compact) * 0.6, p);
      opacity = lerp(0.8, 0.92, p);
    }
    final isTop = k == 0;
    final rot = isTop ? (_off.dx / w) * 0.30 : 0.0;
    final off = isTop ? _off : Offset.zero;
    return Positioned(
      key: ValueKey('deck-${item.id}'),
      top: 0,
      left: 0,
      right: 0,
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(off.dx, off.dy + dy),
            child: Transform.rotate(
              angle: rot,
              alignment: Alignment.bottomCenter,
              child: Transform.scale(
                scale: scale,
                // anchor at the bottom so cards behind peek out below the top card
                alignment: Alignment.bottomCenter,
                child: HoloNetaCard(
                  key: isTop ? _topKey : null,
                  neta: item,
                  width: w,
                  active: isTop,
                  interactive: isTop,
                  entrance: false,
                  tiltBias: isTop ? tiltBias : Offset.zero,
                  onOpen: _open,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double lerp(double a, double b, double t) => a + (b - a) * t;

class _Controls extends StatelessWidget {
  final String position;
  final bool canUndo, compact;
  final VoidCallback onUndo, onFlip, onOpen;
  const _Controls({required this.position, required this.canUndo, required this.onUndo, required this.onFlip, required this.onOpen, this.compact = false});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _RoundBtn(icon: Icons.undo_rounded, onTap: canUndo ? onUndo : null, label: 'Undo', compact: compact),
      SizedBox(width: compact ? 14 : 18),
      Column(mainAxisSize: MainAxisSize.min, children: [
        _RoundBtn(icon: Icons.north_east_rounded, onTap: onOpen, big: true, dark: true, label: 'Open', compact: compact),
        SizedBox(height: compact ? 2 : 4),
        Text(position, style: ui(11, color: C.inkSoft, w: 700, h: 1.1)),
      ]),
      SizedBox(width: compact ? 14 : 18),
      _RoundBtn(icon: Icons.flip_rounded, onTap: onFlip, label: 'Flip', compact: compact),
    ]);
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool big, dark, compact;
  final String label;
  const _RoundBtn({required this.icon, required this.onTap, required this.label, this.big = false, this.dark = false, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final s = big ? (compact ? 46.0 : 58.0) : (compact ? 38.0 : 48.0);
    return Semantics(
      button: true,
      label: label,
      child: TapScale(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(color: dark ? C.ink : C.surface, shape: BoxShape.circle, boxShadow: softShadow),
            child: Icon(icon, size: big ? 26 : 22, color: dark ? Colors.white : C.ink),
          ),
        ),
      ),
    );
  }
}
