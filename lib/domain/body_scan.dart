import 'dart:math' as math;

import 'geometry.dart';
import 'insights.dart';
import 'landmarks.dart';
import 'measurements.dart';

enum ScanStep { front, left, right, back, tPose }

extension ScanStepX on ScanStep {
  String get prompt {
    switch (this) {
      case ScanStep.front:
        return 'Face the camera, arms relaxed';
      case ScanStep.left:
        return 'Turn to show your left side';
      case ScanStep.right:
        return 'Turn to show your right side';
      case ScanStep.back:
        return 'Turn your back to the camera';
      case ScanStep.tPose:
        return 'Face the camera, arms out in a T';
    }
  }
}

/// Body Profile calibration (FR-CB-01..05). Ratios from one 2D camera are
/// approximate and must be validated in the Lab before use (FR-CB-06).
class BodyScan {
  static double? _len(BodyPose p, LandmarkId a, LandmarkId b) {
    final pa = p.point(a), pb = p.point(b);
    if (pa == null || pb == null) return null;
    return distance(pa, pb);
  }

  /// Pre-check for one frame (FR-CB-02). Returns an instruction or null.
  static String? precheck(BodyPose? p, {double brightness = 1}) {
    if (p == null) return 'Step into the frame';
    if (brightness < 0.25) return 'Find a brighter spot or face a light';
    final f = Measurements.framing(p);
    if (!f.fullBody) return 'Show your whole body, head to feet';
    if (f.bodyHeight >= 0.995) return 'Step back a little';
    if (f.bodyHeight < 0.35) return 'Come a little closer';
    return null;
  }

  static BodyProfileResult compute(Map<ScanStep, List<BodyPose>> captures) {
    final problems = <String>[];
    final front = [...?captures[ScanStep.front], ...?captures[ScanStep.tPose]];
    if (front.isEmpty) {
      return const BodyProfileResult({}, 0, 0, ['No front capture. Face the camera and try again.']);
    }
    double avg(Iterable<double?> xs) {
      final v = xs.whereType<double>().toList();
      return v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
    }

    final torso = avg(front.map((p) {
      final ls = p.point(LandmarkId.leftShoulder), rs = p.point(LandmarkId.rightShoulder);
      final lh = p.point(LandmarkId.leftHip), rh = p.point(LandmarkId.rightHip);
      if (ls == null || rs == null || lh == null || rh == null) return null;
      return distance((ls + rs) * 0.5, (lh + rh) * 0.5);
    }));
    if (torso <= 0) {
      return const BodyProfileResult({}, 0, 0, ['Shoulders and hips were not visible.']);
    }
    double seg(LandmarkId a, LandmarkId b) => avg(front.map((p) => _len(p, a, b))) / torso;

    final ratios = <String, double>{
      'shoulder_width': seg(LandmarkId.leftShoulder, LandmarkId.rightShoulder),
      'hip_width': seg(LandmarkId.leftHip, LandmarkId.rightHip),
      'upper_arm_l': seg(LandmarkId.leftShoulder, LandmarkId.leftElbow),
      'upper_arm_r': seg(LandmarkId.rightShoulder, LandmarkId.rightElbow),
      'forearm_l': seg(LandmarkId.leftElbow, LandmarkId.leftWrist),
      'forearm_r': seg(LandmarkId.rightElbow, LandmarkId.rightWrist),
      'thigh_l': seg(LandmarkId.leftHip, LandmarkId.leftKnee),
      'thigh_r': seg(LandmarkId.rightHip, LandmarkId.rightKnee),
      'shin_l': seg(LandmarkId.leftKnee, LandmarkId.leftAnkle),
      'shin_r': seg(LandmarkId.rightKnee, LandmarkId.rightAnkle),
    };

    var diffSum = 0.0;
    var n = 0;
    for (final k in ['upper_arm', 'forearm', 'thigh', 'shin']) {
      final l = ratios['${k}_l']!, r = ratios['${k}_r']!;
      if (l > 0 && r > 0) {
        diffSum += (l - r).abs() / math.max(l, r);
        n++;
      }
    }
    final symmetry = n == 0 ? 0.0 : (100 * (1 - diffSum / n)).clamp(0, 100).toDouble();

    // Quality: landmark confidence, step coverage, framing and jitter.
    final conf = avg(front.expand((p) => p.landmarks.map((l) => l.confidence)));
    final coverage = ScanStep.values.where((s) => (captures[s] ?? const []).isNotEmpty).length / ScanStep.values.length;
    final framed = front.where((p) => Measurements.framing(p).fullBody).length / front.length;
    var jitter = 0.0;
    for (var i = 1; i < front.length; i++) {
      final a = front[i - 1].point(LandmarkId.leftShoulder), b = front[i].point(LandmarkId.leftShoulder);
      if (a != null && b != null) jitter += distance(a, b) / torso;
    }
    jitter = front.length > 1 ? jitter / (front.length - 1) : 0;
    final steadiness = (1 - jitter * 5).clamp(0.0, 1.0);
    final quality = (100 * (0.35 * conf + 0.25 * coverage + 0.25 * framed + 0.15 * steadiness)).round().clamp(0, 100);

    if (conf < 0.7) problems.add('Improve the lighting so the body is clearer');
    if (coverage < 1) problems.add('Complete all five poses');
    if (framed < 0.8) problems.add('Keep your whole body inside the frame');
    if (steadiness < 0.6) problems.add('Hold still for each pose and keep the phone steady');
    if (symmetry < 85) problems.add('Stand straight, facing the camera squarely');
    return BodyProfileResult(ratios, symmetry, quality, problems);
  }
}
