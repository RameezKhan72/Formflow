import 'dart:math' as math;

import 'exercise.dart';
import 'geometry.dart';
import 'landmarks.dart';

/// Computes named measurements from a pose. All distances are normalised by
/// torso or leg length so rules do not depend on distance from the camera
/// (PRD Section 10, "unit fix").
class Measurements {
  static const double frontViewRatio = 0.45;

  /// Front view when shoulders appear wide relative to torso length.
  static CameraView viewOf(BodyPose p, {double gate = 0.5}) {
    final ls = p.point(LandmarkId.leftShoulder, gate: gate);
    final rs = p.point(LandmarkId.rightShoulder, gate: gate);
    final lh = p.point(LandmarkId.leftHip, gate: gate);
    final rh = p.point(LandmarkId.rightHip, gate: gate);
    if (ls == null || rs == null) return CameraView.side;
    final hip = lh ?? rh;
    final shoulderMid = (ls + rs) * 0.5;
    final torso = hip == null ? null : distance(shoulderMid, hip);
    if (torso == null || torso < 1e-6) return CameraView.side;
    return (ls.x - rs.x).abs() / torso > frontViewRatio ? CameraView.front : CameraView.side;
  }

  static BodySide moreVisibleSide(BodyPose p, {List<Joint>? focus}) =>
      p.sideConfidence(BodySide.left, joints: focus) >= p.sideConfidence(BodySide.right, joints: focus)
          ? BodySide.left
          : BodySide.right;

  /// Measurements for one body side. Missing landmarks simply omit keys.
  static Map<String, double> forSide(BodyPose p, BodySide s, {double gate = 0.5}) {
    final m = <String, double>{};
    Vec2? j(Joint joint) => p.joint(joint, s, gate: gate);
    final sh = j(Joint.shoulder), el = j(Joint.elbow), wr = j(Joint.wrist);
    final hip = j(Joint.hip), kn = j(Joint.knee), an = j(Joint.ankle);
    final heel = j(Joint.heel), toe = j(Joint.toe);

    void put(String k, double? v) {
      if (v != null && v.isFinite) m[k] = v;
    }

    if (hip != null && kn != null && an != null) put('kneeAngle', angleAt(hip, kn, an));
    if (sh != null && hip != null && kn != null) put('hipAngle', angleAt(sh, hip, kn));
    if (sh != null && el != null && wr != null) put('elbowAngle', angleAt(sh, el, wr));
    if (hip != null && sh != null && el != null) put('shoulderAngle', angleAt(hip, sh, el));
    if (sh != null && hip != null && an != null) put('bodyLine', angleAt(sh, hip, an));
    if (kn != null && an != null && toe != null) put('ankleAngle', angleAt(kn, an, toe));

    final torso = (sh != null && hip != null) ? distance(sh, hip) : null;
    final leg = (hip != null && an != null) ? distance(hip, an) : null;

    if (hip != null && kn != null) put('thighAngle', angleFromVertical(kn, hip));
    if (sh != null && hip != null) {
      put('torsoLean', angleFromVertical(hip, sh));
      put('torsoHorizontal', angleFromHorizontal(hip, sh));
    }
    if (torso != null && torso > 1e-6) {
      if (el != null && sh != null) put('elbowDrift', (el.x - sh.x).abs() / torso);
      if (wr != null && an != null) put('barGap', (wr.x - an.x).abs() / torso);
      if (wr != null && sh != null) put('wristAboveShoulder', (sh.y - wr.y) / torso);
      if (kn != null && toe != null && heel != null) {
        final facing = (toe.x - heel.x) >= 0 ? 1.0 : -1.0;
        put('kneePastToe', (kn.x - toe.x) * facing / torso);
      }
      if (sh != null && hip != null && an != null) {
        final line = sh - an;
        final len = line.length;
        if (len > 1e-6) {
          final cross = line.cross(hip - an);
          final sign = line.x >= 0 ? 1.0 : -1.0;
          // Positive = hips below the shoulder-ankle line (sagging).
          put('hipOffset', cross / len * sign / torso);
        }
      }
    }
    if (leg != null && leg > 1e-6 && heel != null && toe != null) {
      put('heelRise', (toe.y - heel.y) / leg);
    }
    return m;
  }

  /// Measurements that need both sides (front view).
  static Map<String, double> bilateral(BodyPose p, {double gate = 0.5}) {
    final m = <String, double>{};
    final lk = p.point(LandmarkId.leftKnee, gate: gate), rk = p.point(LandmarkId.rightKnee, gate: gate);
    final la = p.point(LandmarkId.leftAnkle, gate: gate), ra = p.point(LandmarkId.rightAnkle, gate: gate);
    if (lk != null && rk != null && la != null && ra != null) {
      final ankleSpacing = (la.x - ra.x).abs();
      if (ankleSpacing > 1e-6) m['kneeSpacingToAnkleSpacing'] = (lk.x - rk.x).abs() / ankleSpacing;
    }
    final l = forSide(p, BodySide.left, gate: gate);
    final r = forSide(p, BodySide.right, gate: gate);
    final la2 = l['shoulderAngle'], ra2 = r['shoulderAngle'];
    if (la2 != null && ra2 != null) m['armAsym'] = (la2 - ra2).abs();
    return m;
  }

  /// Per-side knee cave: positive when the knee sits inside the ankle line,
  /// relative to hip width.
  static double? kneeInward(BodyPose p, BodySide s, {double gate = 0.5}) {
    final lh = p.point(LandmarkId.leftHip, gate: gate), rh = p.point(LandmarkId.rightHip, gate: gate);
    final kn = p.joint(Joint.knee, s, gate: gate), an = p.joint(Joint.ankle, s, gate: gate);
    if (lh == null || rh == null || kn == null || an == null) return null;
    final midX = (lh.x + rh.x) / 2;
    final hipW = (lh.x - rh.x).abs();
    if (hipW < 1e-6) return null;
    return ((an.x - midX).abs() - (kn.x - midX).abs()) / hipW;
  }

  /// Full measurement set for a side, including bilateral values.
  static Map<String, double> all(BodyPose p, BodySide s, {double gate = 0.5}) {
    final m = forSide(p, s, gate: gate)..addAll(bilateral(p, gate: gate));
    final ki = kneeInward(p, s, gate: gate);
    if (ki != null) m['kneeInward'] = ki;
    return m;
  }

  /// Value of the exercise metric according to its side policy.
  static ({double value, BodySide side})? metricValue(BodyPose p, MetricDef metric,
      {double gate = 0.5, List<Joint>? focus}) {
    final l = forSide(p, BodySide.left, gate: gate)[metric.measure];
    final r = forSide(p, BodySide.right, gate: gate)[metric.measure];
    if (l == null && r == null) return null;
    if (l == null) return (value: r!, side: BodySide.right);
    if (r == null) return (value: l, side: BodySide.left);
    switch (metric.side) {
      case 'min':
        return l <= r ? (value: l, side: BodySide.left) : (value: r, side: BodySide.right);
      case 'max':
        return l >= r ? (value: l, side: BodySide.left) : (value: r, side: BodySide.right);
      default:
        final s = moreVisibleSide(p, focus: focus);
        return (value: s == BodySide.left ? l : r, side: s);
    }
  }

  /// Rough quality checks for the camera setup screen (FR-PE-13).
  ///
  /// With [focus] (the exercise's tracked joints) only those landmarks must
  /// be in view, so upper-body exercises work from about 1 m with the legs
  /// out of frame; the distance check then uses the size of the focus area.
  static ({bool fullBody, bool distanceOk, double bodyHeight, bool tooClose}) framing(BodyPose p,
      {List<String>? focus}) {
    bool inView(LandmarkId k) {
      final l = p[k];
      final nx = l.x / p.aspect;
      return l.confidence >= 0.5 && nx > 0.02 && nx < 0.98 && l.y > 0.02 && l.y < 0.98;
    }

    if (focus != null && focus.isNotEmpty) {
      final joints = jointsFromNames(focus);
      var seen = 0;
      for (final j in joints) {
        if (inView(landmarkFor(j, BodySide.left)) || inView(landmarkFor(j, BodySide.right))) seen++;
      }
      final b = p.bounds(only: focusLandmarks(focus));
      final h = b == null ? 0.0 : math.max(b.maxY - b.minY, b.maxX - b.minX);
      final upper = !joints.contains(Joint.knee) && !joints.contains(Joint.ankle);
      final lo = upper ? 0.22 : 0.35;
      final hi = upper ? 0.96 : 0.995;
      return (fullBody: seen >= joints.length, distanceOk: h > lo && h < hi, bodyHeight: h, tooClose: h >= hi);
    }
    const key = [
      LandmarkId.nose, LandmarkId.leftShoulder, LandmarkId.rightShoulder, LandmarkId.leftHip,
      LandmarkId.rightHip, LandmarkId.leftAnkle, LandmarkId.rightAnkle,
    ];
    var visible = 0;
    for (final k in key) {
      if (inView(k)) visible++;
    }
    final b = p.bounds();
    final h = b == null ? 0.0 : math.max(b.maxY - b.minY, b.maxX - b.minX);
    return (fullBody: visible >= 6, distanceOk: h > 0.35 && h < 0.995, bodyHeight: h, tooClose: h >= 0.995);
  }
}
