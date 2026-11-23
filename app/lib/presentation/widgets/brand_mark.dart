import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:by_the_people/core/theme/tokens.dart';

/// The By the People mark: a crowd of eight people facing outward around a
/// check mark. Same geometry as tool/make_icon.py (the app icon).
class BrandMark extends StatefulWidget {
  final double size;
  const BrandMark({super.key, this.size = 96});
  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: _MarkPainter(_c)),
      );
}

class _MarkPainter extends CustomPainter {
  final Animation<double> a;
  _MarkPainter(this.a) : super(repaint: a);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 1024;
    final c = Offset(size.width / 2, size.height / 2);
    const ring = 262.0;
    // people pop in one after another, then the seal and check land
    for (var k = 0; k < 8; k++) {
      final t = Curves.easeOutBack.transform(((a.value * 1.6 - k * 0.07).clamp(0.0, 1.0)));
      if (t <= 0) continue;
      final theta = k * math.pi / 4;
      final u = Offset(math.sin(theta), -math.cos(theta));
      final tan = Offset(math.cos(theta), math.sin(theta));
      final paint = Paint()
        ..shader = LinearGradient(colors: k.isEven ? const [C.emberLight, C.ember] : const [C.ember, Color(0xFFE23D1E)])
            .createShader(Rect.fromCircle(center: c, radius: size.width / 2));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(t, t);
      canvas.translate(-c.dx, -c.dy);
      final head = c + u * ((ring + 50) * s);
      canvas.drawCircle(head, 50 * s, paint);
      final body = c + u * ((ring - 52) * s);
      final rs = 80 * s;
      final path = Path();
      for (var i = 0; i <= 60; i++) {
        final phi = math.pi * i / 60;
        final p = body + tan * (rs * math.cos(phi)) + u * (rs * 0.95 * math.sin(phi));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
      canvas.restore();
    }
    final st = Curves.easeOutBack.transform(((a.value * 1.5 - 0.5).clamp(0.0, 1.0)));
    if (st > 0) {
      canvas.drawCircle(c, 128 * s * st, Paint()..color = C.ink);
      final ck = Path()
        ..moveTo(c.dx - 58 * s, c.dy + 4 * s)
        ..lineTo(c.dx - 16 * s, c.dy + 46 * s)
        ..lineTo(c.dx + 62 * s, c.dy - 44 * s);
      canvas.drawPath(
        ck,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 30 * s * st
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = C.lime,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter o) => false;
}
