import 'dart:math' as math;

import 'exercise.dart';

/// Result of one completed movement (an "attempt").
class RepEvent {
  final bool depthReached;

  /// Most extreme metric value reached (min for "down", max for "up").
  final double peak;
  final double durationSeconds;
  const RepEvent({required this.depthReached, required this.peak, required this.durationSeconds});
}

/// Four-phase rep state machine with hysteresis and minimum rep time
/// (FR-FA-03): Ready -> Lowering -> Bottom -> Rising -> Ready.
///
/// For "up" exercises (the metric increases towards depth, e.g. lateral
/// raise) values are mirrored internally so a single implementation works.
class RepCounter {
  final Direction direction;
  Thresholds thresholds;
  final double minRepSeconds;

  /// Fraction of the start->depth range that must be covered to count an
  /// attempt; smaller wobbles are ignored as noise.
  final double minExcursion;

  Phase _phase = Phase.idle;
  double _extreme = 0; // internal (mirrored) minimum
  bool _depth = false;
  double _startT = 0;

  RepCounter({
    required this.direction,
    required this.thresholds,
    this.minRepSeconds = 0.6,
    this.minExcursion = 0.25,
  });

  Phase get phase => _phase;
  bool get depthReachedThisRep => _depth;

  double _m(double v) => direction == Direction.down ? v : -v;
  double get _start => _m(thresholds.start);
  double get _complete => _m(thresholds.complete);
  double get _depthT => _m(thresholds.depth);
  double get _hyst => thresholds.hysteresis;

  void reset() {
    _phase = Phase.idle;
    _depth = false;
  }

  /// 0 at the top position, 1 at full depth (for the depth meter).
  double progress(double value) {
    final v = _m(value);
    final range = _start - _depthT;
    if (range.abs() < 1e-9) return 0;
    return ((_start - v) / range).clamp(0.0, 1.2);
  }

  /// Feed one analysed frame. Returns a [RepEvent] when a movement finishes.
  RepEvent? update(double value, double tSeconds) {
    final v = _m(value);
    switch (_phase) {
      case Phase.idle:
        if (v >= _complete) _phase = Phase.ready;
        return null;
      case Phase.ready:
        if (v < _start) {
          _phase = Phase.lowering;
          _extreme = v;
          _depth = false;
          _startT = tSeconds;
          if (v <= _depthT) {
            _phase = Phase.bottom;
            _depth = true;
          }
        }
        return null;
      case Phase.lowering:
        _extreme = math.min(_extreme, v);
        if (v <= _depthT) {
          _phase = Phase.bottom;
          _depth = true;
        } else if (v > _extreme + _hyst) {
          _phase = Phase.rising;
        }
        return _checkFinish(v, tSeconds);
      case Phase.bottom:
        _extreme = math.min(_extreme, v);
        if (v > _extreme + _hyst) _phase = Phase.rising;
        return _checkFinish(v, tSeconds);
      case Phase.rising:
        if (v <= _depthT) {
          _phase = Phase.bottom;
          _depth = true;
          _extreme = math.min(_extreme, v);
          return null;
        }
        if (v < _extreme) {
          _extreme = v;
          _phase = Phase.lowering;
          return null;
        }
        return _checkFinish(v, tSeconds);
    }
  }

  RepEvent? _checkFinish(double v, double t) {
    if (v < _complete) return null;
    final excursion = _start - _extreme;
    final needed = (_start - _depthT) * minExcursion;
    final duration = t - _startT;
    _phase = Phase.ready;
    if (excursion < needed || duration < minRepSeconds) return null; // noise / bounce
    final peak = direction == Direction.down ? _extreme : -_extreme;
    final ev = RepEvent(depthReached: _depth, peak: peak, durationSeconds: duration);
    _depth = false;
    return ev;
  }
}
