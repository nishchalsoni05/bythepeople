import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:by_the_people/core/device_tilt.dart';

/// Gravity components for a phone held with the given pitch (0 = flat, pi/2 = upright) and roll.
List<double> gravity({required double pitch, double roll = 0}) {
  final g = TiltFilter.g;
  return [g * math.sin(roll), g * math.sin(pitch) * math.cos(roll), g * math.cos(pitch) * math.cos(roll)];
}

TiltFilter settle(double pitch) {
  final f = TiltFilter();
  final v = gravity(pitch: pitch);
  for (var i = 0; i < 400; i++) {
    f.update(v[0], v[1], v[2], 0.02);
  }
  return f;
}

void main() {
  test('a phone held still in any resting posture reads level', () {
    for (final p in [0.6, 1.0, 1.3]) {
      final f = settle(p);
      final v = gravity(pitch: p);
      final t = f.update(v[0], v[1], v[2], 0.02);
      expect(t.dx.abs(), lessThan(0.02));
      expect(t.dy.abs(), lessThan(0.02));
    }
  });

  test('rolling the phone to the right tilts the card right, and symmetric', () {
    final f = settle(1.0);
    var t = const Offset(0, 0).translate(0, 0);
    for (var i = 0; i < 20; i++) {
      final v = gravity(pitch: 1.0, roll: 0.3);
      t = f.update(v[0], v[1], v[2], 0.02);
    }
    expect(t.dx, greaterThan(0.4));
    final g = settle(1.0);
    for (var i = 0; i < 20; i++) {
      final v = gravity(pitch: 1.0, roll: -0.3);
      t = g.update(v[0], v[1], v[2], 0.02);
    }
    expect(t.dx, lessThan(-0.4));
  });

  test('pitching forward and back moves y with opposite signs', () {
    final f = settle(1.0);
    var up = const Offset(0, 0).translate(0, 0), down = up;
    for (var i = 0; i < 20; i++) {
      final a = gravity(pitch: 1.25);
      up = f.update(a[0], a[1], a[2], 0.02);
    }
    final g = settle(1.0);
    for (var i = 0; i < 20; i++) {
      final b = gravity(pitch: 0.75);
      down = g.update(b[0], b[1], b[2], 0.02);
    }
    expect(up.dy * down.dy, lessThan(0));
    expect(up.dy.abs(), greaterThan(0.3));
  });

  test('output is clamped and a tremor is smoothed away', () {
    final f = settle(1.0);
    var t = const Offset(0, 0).translate(0, 0);
    for (var i = 0; i < 40; i++) {
      final v = gravity(pitch: 1.0, roll: 1.4);
      t = f.update(v[0], v[1], v[2], 0.02);
    }
    expect(t.dx, lessThanOrEqualTo(1.3));
    final h = settle(1.0);
    var peak = 0.0;
    for (var i = 0; i < 100; i++) {
      final v = gravity(pitch: 1.0, roll: i.isEven ? 0.02 : -0.02); // +/-1 degree jitter
      peak = math.max(peak, h.update(v[0], v[1], v[2], 0.02).dx.abs());
    }
    expect(peak, lessThan(0.1));
  });

  test('a held tilt slowly recalibrates to the new resting posture', () {
    final f = settle(1.0);
    var t = const Offset(0, 0).translate(0, 0);
    final v = gravity(pitch: 1.0, roll: 0.25);
    for (var i = 0; i < 50; i++) {
      t = f.update(v[0], v[1], v[2], 0.02);
    }
    final early = t.dx;
    for (var i = 0; i < 2500; i++) {
      t = f.update(v[0], v[1], v[2], 0.02); // 50 s
    }
    expect(early, greaterThan(0.3));
    expect(t.dx.abs(), lessThan(early * 0.2));
  });
}
