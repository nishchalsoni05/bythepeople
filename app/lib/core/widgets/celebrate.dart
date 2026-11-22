import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../tokens.dart';
import 'ui.dart';

const _confettiColors = [C.ember, C.emberLight, C.lime, C.lavender, C.sky, C.blush, Colors.white];

void showConfetti(BuildContext context) {
  if (MediaQuery.of(context).disableAnimations) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry e;
  e = OverlayEntry(builder: (_) => _Confetti(onDone: () => e.remove()));
  overlay.insert(e);
  HapticFeedback.heavyImpact();
}

class _Confetti extends StatefulWidget {
  final VoidCallback onDone;
  const _Confetti({required this.onDone});
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  final _rnd = math.Random();
  late final List<_P> ps = List.generate(70, (i) => _P(_rnd));
  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _CP(ps, _c)));
}

class _P {
  final double angle, speed, spin, size;
  final Color color;
  _P(math.Random r)
      : angle = -math.pi / 2 + (r.nextDouble() - 0.5) * 2.2,
        speed = 380 + r.nextDouble() * 560,
        spin = (r.nextDouble() - 0.5) * 14,
        size = 6 + r.nextDouble() * 7,
        color = _confettiColors[r.nextInt(_confettiColors.length)];
}

class _CP extends CustomPainter {
  final List<_P> ps;
  final Animation<double> a;
  _CP(this.ps, this.a) : super(repaint: a);
  @override
  void paint(Canvas canvas, Size size) {
    final t = a.value * 2.6;
    for (final p in ps) {
      final x = size.width / 2 + math.cos(p.angle) * p.speed * t * 0.55;
      final y = size.height * 0.62 + math.sin(p.angle) * p.speed * t + 450 * t * t;
      final fade = (1 - (a.value - 0.65).clamp(0, 0.35) / 0.35);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55), const Radius.circular(2)),
        Paint()..color = p.color.withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CP o) => false;
}

/// Celebrates rewards: toast with points / badge / rank up, optional confetti.
void celebrate(BuildContext context, {Rewards? rewards, String? headline, bool confetti = false}) {
  final big = confetti || (rewards?.badges.isNotEmpty ?? false) || rewards?.rankUpTo != null;
  if (big) showConfetti(context);
  final parts = <String>[];
  if (headline != null) parts.add(headline);
  if (rewards != null) {
    if (rewards.points > 0) parts.add('+${rewards.points} pts');
    for (final b in rewards.badges) {
      parts.add('Badge unlocked: ${b.name}');
    }
    if (rewards.rankUpTo != null) parts.add('Rank up! You are now ${rewards.rankUpTo}');
  }
  if (parts.isEmpty) return;
  showToast(context, parts.join('  ·  '), icon: rewards?.rankUpTo != null ? Icons.military_tech_rounded : (big ? Icons.auto_awesome_rounded : Icons.check_circle_rounded));
}
