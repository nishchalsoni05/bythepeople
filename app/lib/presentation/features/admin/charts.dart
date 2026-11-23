import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:by_the_people/core/theme/tokens.dart';

class Segment {
  final String label;
  final double value;
  final Color color;
  const Segment(this.label, this.value, this.color);
}

/// Animated donut chart drawn with CustomPaint. Centre shows [centerTop] over [centerBottom].
class DonutChart extends StatelessWidget {
  final List<Segment> segments;
  final double size;
  final String centerTop, centerBottom;
  const DonutChart({super.key, required this.segments, this.size = 140, required this.centerTop, required this.centerBottom});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: Size.square(size), painter: _DonutPainter(segments, t)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(centerTop, style: ui(size * 0.22, w: 750)),
            Text(centerBottom, style: ui(size * 0.085, color: C.inkSoft, w: 650)),
          ]),
        ]),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<Segment> segs;
  final double t;
  _DonutPainter(this.segs, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.15;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: (size.width - stroke) / 2);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = C.muted);
    final total = segs.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0) return;
    const gap = 0.045;
    var start = -math.pi / 2;
    final live = segs.where((s) => s.value > 0).length;
    for (final s in segs) {
      if (s.value <= 0) continue;
      final full = s.value / total * math.pi * 2;
      final sweep = (full - (live > 1 ? gap : 0)) * t;
      if (sweep > 0) {
        canvas.drawArc(
          rect, start + (live > 1 ? gap / 2 : 0), sweep, false,
          Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round..color = s.color,
        );
      }
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.t != t || old.segs != segs;
}

/// Horizontal bars: total per row with the "open" share in the accent colour.
class BarRow {
  final String label;
  final int total, open;
  const BarRow(this.label, this.total, this.open);
}

class HorizontalBars extends StatelessWidget {
  final List<BarRow> rows;
  final Color accent, base;
  const HorizontalBars({super.key, required this.rows, this.accent = C.ember, this.base = C.lime});

  @override
  Widget build(BuildContext context) {
    final maxV = rows.fold<int>(1, (a, b) => math.max(a, b.total));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 88, child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12.5, w: 650))),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 16, child: CustomPaint(painter: _BarPainter(r.total / maxV * t, r.open / maxV * t, accent, base)))),
              const SizedBox(width: 8),
              SizedBox(width: 30, child: Text('${r.total}', textAlign: TextAlign.right, style: ui(12.5, w: 750))),
            ]),
          ),
      ]),
    );
  }
}

class _BarPainter extends CustomPainter {
  final double total, open;
  final Color accent, base;
  _BarPainter(this.total, this.open, this.accent, this.base);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = C.muted);
    final w = size.width * total;
    if (w > 0) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, math.max(w, size.height), size.height), r), Paint()..color = base);
    final o = size.width * open;
    if (o > 0) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, math.max(o, size.height), size.height), r), Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.total != total || old.open != open;
}

/// Circular gauge for a 0..1 rate (e.g. resolution rate).
class RingGauge extends StatelessWidget {
  final double value;
  final double size;
  final Color color, track;
  final String label;
  const RingGauge({super.key, required this.value, this.size = 84, this.color = C.lime, this.track = const Color(0x33FFFFFF), required this.label});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(size: Size.square(size), painter: _RingPainter(v, color, track)),
            Text(label, style: ui(size * 0.2, color: Colors.white, w: 750)),
          ]),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color, track;
  _RingPainter(this.v, this.color, this.track);
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.13;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: (size.width - stroke) / 2);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = track);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v;
}
