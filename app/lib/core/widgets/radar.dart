import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../tokens.dart';

const _mPerDegLat = 111320.0;

({double dx, double dy}) metersBetween(double lat0, double lng0, double lat, double lng) {
  final dy = (lat - lat0) * _mPerDegLat;
  final dx = (lng - lng0) * _mPerDegLat * math.cos(lat0 * math.pi / 180);
  return (dx: dx, dy: dy);
}

({double lat, double lng}) offsetLatLng(double lat0, double lng0, double dxM, double dyM) => (
      lat: lat0 + dyM / _mPerDegLat,
      lng: lng0 + dxM / (_mPerDegLat * math.cos(lat0 * math.pi / 180)),
    );

class RadarPin {
  final double lat, lng;
  final Color color;
  final bool big;
  const RadarPin(this.lat, this.lng, this.color, {this.big = false});
}

/// Stylised local "map": you at the centre, the allowed radius as a ring,
/// issues as pins. Optionally pick a location by tapping/dragging inside.
class RadarMap extends StatefulWidget {
  final double userLat, userLng, radiusKm;
  final List<RadarPin> pins;
  final bool pickable;
  final ValueChanged<({double lat, double lng})>? onPick;
  final double height;
  const RadarMap({
    super.key, required this.userLat, required this.userLng, required this.radiusKm,
    this.pins = const [], this.pickable = false, this.onPick, this.height = 260,
  });
  @override
  State<RadarMap> createState() => _RadarMapState();
}

class _RadarMapState extends State<RadarMap> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  Offset? _picked; // in metres relative to user

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _handle(Offset local, Size size, double metersPerPx) {
    final c = size.center(Offset.zero);
    var dx = (local.dx - c.dx) * metersPerPx;
    var dy = -(local.dy - c.dy) * metersPerPx;
    final maxM = widget.radiusKm * 1000 * 0.97;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d > maxM) {
      dx *= maxM / d;
      dy *= maxM / d;
    }
    setState(() => _picked = Offset(dx, dy));
    final ll = offsetLatLng(widget.userLat, widget.userLng, dx, dy);
    widget.onPick?.call(ll);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.card),
      child: Container(
        height: widget.height,
        color: const Color(0xFFEAF1EC),
        child: LayoutBuilder(builder: (context, cons) {
          final size = Size(cons.maxWidth, widget.height);
          // Show a little more than the radius so out-of-range pins are visible.
          final extentKm = math.max(widget.radiusKm * 1.35, _farthestKm() * 1.12);
          final metersPerPx = (extentKm * 1000) / (math.min(size.width, size.height) / 2);
          return GestureDetector(
            onPanStart: widget.pickable ? (d) => _handle(d.localPosition, size, metersPerPx) : null,
            onPanUpdate: widget.pickable ? (d) => _handle(d.localPosition, size, metersPerPx) : null,
            onTapDown: widget.pickable ? (d) => _handle(d.localPosition, size, metersPerPx) : null,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                size: size,
                painter: _RadarPainter(widget, _picked, metersPerPx, _c.value),
              ),
            ),
          );
        }),
      ),
    );
  }

  double _farthestKm() {
    double m = 0;
    for (final p in widget.pins) {
      final o = metersBetween(widget.userLat, widget.userLng, p.lat, p.lng);
      m = math.max(m, math.sqrt(o.dx * o.dx + o.dy * o.dy) / 1000);
    }
    return widget.pickable ? 0 : m;
  }
}

class _RadarPainter extends CustomPainter {
  final RadarMap w;
  final Offset? picked;
  final double mpp, t;
  _RadarPainter(this.w, this.picked, this.mpp, this.t);

  Offset _toPx(Size s, double dxM, double dyM) => s.center(Offset.zero) + Offset(dxM / mpp, -dyM / mpp);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // street-like grid
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 5;
    for (double x = (c.dx % 56) - 56; x < size.width; x += 56) {
      canvas.drawLine(Offset(x + 12, 0), Offset(x - 8, size.height), grid);
    }
    for (double y = (c.dy % 64) - 64; y < size.height; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 14), grid);
    }
    final park = Paint()..color = const Color(0xFFD5EBD9);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.06, size.height * 0.62, 70, 48), const Radius.circular(16)), park);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.7, size.height * 0.1, 84, 54), const Radius.circular(16)), park);

    final rPx = w.radiusKm * 1000 / mpp;
    canvas.drawCircle(c, rPx, Paint()..color = C.ember.withValues(alpha: 0.10));
    canvas.drawCircle(
      c, rPx,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = C.ember.withValues(alpha: 0.55),
    );
    // pulse
    canvas.drawCircle(
      c, rPx * t,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = C.ember.withValues(alpha: 0.35 * (1 - t)),
    );
    // radius label
    final tp = TextPainter(
      text: TextSpan(text: '${w.radiusKm % 1 == 0 ? w.radiusKm.toInt() : w.radiusKm} km', style: ui(11, color: C.ember, w: 700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - rPx - tp.height - 3 < 4 ? 4 : c.dy - rPx - tp.height - 3));

    for (final p in w.pins) {
      final o = metersBetween(w.userLat, w.userLng, p.lat, p.lng);
      final pos = _toPx(size, o.dx, o.dy);
      _pin(canvas, pos, p.color, p.big ? 12 : 7);
    }
    if (picked != null) {
      _pin(canvas, _toPx(size, picked!.dx, picked!.dy), C.ember, 13, ring: true);
    }
    // you
    canvas.drawCircle(c, 15, Paint()..color = C.sky.withValues(alpha: 0.35));
    canvas.drawCircle(c, 8, Paint()..color = Colors.white);
    canvas.drawCircle(c, 6, Paint()..color = const Color(0xFF2F80ED));
  }

  void _pin(Canvas canvas, Offset p, Color color, double r, {bool ring = false}) {
    canvas.drawCircle(p + const Offset(0, 2), r, Paint()..color = Colors.black.withValues(alpha: 0.15));
    canvas.drawCircle(p, r, Paint()..color = color);
    canvas.drawCircle(p, r * 0.38, Paint()..color = Colors.white);
    if (ring) {
      canvas.drawCircle(
        p, r + 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter o) => true;
}
