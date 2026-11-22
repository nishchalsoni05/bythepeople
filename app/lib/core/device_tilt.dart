import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;
import 'package:sensors_plus/sensors_plus.dart';

/// Pure maths for turning raw accelerometer samples into a card tilt in about -1.3..1.3.
///
///  * low-pass smoothing removes hand tremor
///  * a slow-moving baseline (the way you normally hold the phone) is subtracted, so the card is
///    level in your resting posture and only the deviation from it tilts the card
///  * x: right edge down is positive, y: top edge tilted away is positive
class TiltFilter {
  static const g = 9.80665;
  final double range; // radians that map to |tilt| = 1 (about 26 degrees)
  final double smoothing; // seconds
  final double baselineTau; // seconds
  double _roll = 0, _pitch = 0, _rollBase = 0, _pitchBase = 0;
  bool _ready = false;

  TiltFilter({this.range = 0.45, this.smoothing = 0.07, this.baselineTau = 6.0});

  bool get ready => _ready;

  Offset update(double ax, double ay, double az, double dt) {
    final r = math.asin((ax / g).clamp(-1.0, 1.0));
    final p = math.atan2(ay, az);
    if (!_ready) {
      _roll = _rollBase = r;
      _pitch = _pitchBase = p;
      _ready = true;
      return Offset.zero;
    }
    final a = 1 - math.exp(-dt / smoothing);
    _roll += (r - _roll) * a;
    _pitch += _wrap(p - _pitch) * a;
    final b = 1 - math.exp(-dt / baselineTau);
    _rollBase += (_roll - _rollBase) * b;
    _pitchBase += _wrap(_pitch - _pitchBase) * b;
    return Offset(
      ((_roll - _rollBase) / range).clamp(-1.3, 1.3),
      (_wrap(_pitch - _pitchBase) / range).clamp(-1.3, 1.3),
    );
  }

  static double _wrap(double a) {
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }
}

/// Shared motion source for every card. Sensors only run while at least one card is on screen.
///  * accelerometer -> [tilt], drives the 3D tilt and the foil
///  * gyroscope     -> [energy], how fast the phone is being twisted (a flick makes the card flash)
class DeviceTilt {
  DeviceTilt._();
  static final DeviceTilt instance = DeviceTilt._();

  Offset tilt = Offset.zero;
  double energy = 0; // smoothed angular speed in rad/s
  bool available = false; // true once the first real sample arrives (false on simulators)

  final TiltFilter _filter = TiltFilter();
  final Stopwatch _clock = Stopwatch();
  StreamSubscription<dynamic>? _acc, _gyro;
  int _refs = 0;
  Duration _last = Duration.zero;

  void acquire() {
    if (_refs++ == 0) _start();
  }

  void release() {
    if (_refs > 0 && --_refs == 0) _stop();
  }

  void _start() {
    _clock.start();
    try {
      _acc = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
        final now = _clock.elapsed;
        final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.001, 0.1);
        _last = now;
        available = true;
        tilt = _filter.update(e.x, e.y, e.z, dt);
      }, onError: (_) {});
    } catch (_) {}
    try {
      _gyro = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
        final m = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
        energy += (m - energy) * 0.25;
      }, onError: (_) {});
    } catch (_) {}
  }

  void _stop() {
    _acc?.cancel();
    _gyro?.cancel();
    _acc = _gyro = null;
    _clock.stop();
    tilt = Offset.zero;
    energy = 0;
  }
}
