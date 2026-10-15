import 'dart:math' as math;

/// A 2D point in a uniform (aspect-corrected) coordinate space.
class Vec2 {
  final double x;
  final double y;
  const Vec2(this.x, this.y);

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double k) => Vec2(x * k, y * k);
  double dot(Vec2 o) => x * o.x + y * o.y;
  double cross(Vec2 o) => x * o.y - y * o.x;
  double get length => math.sqrt(x * x + y * y);

  /// Unit vector for a direction angle in degrees where 0 points up
  /// (screen -y) and 90 points right (+x).
  static Vec2 fromDirection(double degrees) {
    final r = degrees * math.pi / 180.0;
    return Vec2(math.sin(r), -math.cos(r));
  }

  @override
  String toString() => 'Vec2(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

double distance(Vec2 a, Vec2 b) => (a - b).length;

/// Joint angle at [b] (degrees, 0..180) formed by points a-b-c, using the
/// dot-product formula (SRS 6.4). Returns null for degenerate input.
double? angleAt(Vec2 a, Vec2 b, Vec2 c) {
  final ba = a - b;
  final bc = c - b;
  final denom = ba.length * bc.length;
  if (denom < 1e-9) return null;
  final cosv = (ba.dot(bc) / denom).clamp(-1.0, 1.0);
  return math.acos(cosv) * 180.0 / math.pi;
}

/// Angle (degrees, 0..180) between vector a->b and straight up.
double angleFromVertical(Vec2 a, Vec2 b) {
  final v = b - a;
  final len = v.length;
  if (len < 1e-9) return 0;
  final cosv = (-v.y / len).clamp(-1.0, 1.0);
  return math.acos(cosv) * 180.0 / math.pi;
}

/// Angle (degrees, 0..90) between segment a-b and the horizontal.
double angleFromHorizontal(Vec2 a, Vec2 b) {
  final v = b - a;
  if (v.length < 1e-9) return 0;
  return math.atan2(v.y.abs(), v.x.abs()) * 180.0 / math.pi;
}

/// Exponential moving average filter.
class EmaFilter {
  final double alpha;
  double? _value;
  EmaFilter({this.alpha = 0.4});

  double filter(double x) {
    final v = _value;
    _value = v == null ? x : alpha * x + (1 - alpha) * v;
    return _value!;
  }

  void reset() => _value = null;
}

/// One Euro filter (Casiez et al. 2012) for jitter-free yet responsive
/// landmark smoothing.
class OneEuroFilter {
  final double minCutoff;
  final double beta;
  final double dCutoff;
  double? _x;
  double _dx = 0;
  double? _lastT;

  OneEuroFilter({this.minCutoff = 1.2, this.beta = 0.02, this.dCutoff = 1.0});

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  /// [t] is time in seconds.
  double filter(double x, double t) {
    final prevX = _x;
    final lastT = _lastT;
    if (prevX == null || lastT == null || t <= lastT) {
      _x = x;
      _lastT = t;
      return x;
    }
    final dt = t - lastT;
    final dx = (x - prevX) / dt;
    final aD = _alpha(dCutoff, dt);
    _dx = aD * dx + (1 - aD) * _dx;
    final cutoff = minCutoff + beta * _dx.abs();
    final a = _alpha(cutoff, dt);
    final result = a * x + (1 - a) * prevX;
    _x = result;
    _lastT = t;
    return result;
  }

  void reset() {
    _x = null;
    _lastT = null;
    _dx = 0;
  }
}
