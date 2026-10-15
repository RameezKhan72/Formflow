import 'dart:convert';
import 'dart:io';

import 'package:formflow/domain/exercise.dart';
import 'package:formflow/domain/geometry.dart';
import 'package:formflow/domain/landmarks.dart';

ExerciseCatalog loadCatalog() =>
    ExerciseCatalog.fromJson(jsonDecode(File('assets/data/exercises.json').readAsStringSync()) as Map<String, dynamic>);

/// Builds a pose from joint positions. [left] and [right] map joint names
/// (shoulder, elbow, wrist, hip, knee, ankle, heel, toe) to points.
BodyPose poseFrom({
  required Map<String, Vec2> left,
  Map<String, Vec2>? right,
  double leftConf = 0.95,
  double rightConf = 0.9,
  Vec2? nose,
}) {
  final lm = List<Landmark>.filled(LandmarkId.values.length, const Landmark(0, 0, confidence: 0));
  void put(Map<String, Vec2> m, BodySide s, double c) {
    m.forEach((k, v) => lm[landmarkFor(jointFromName(k), s).index] = Landmark(v.x, v.y, confidence: c));
  }

  put(left, BodySide.left, leftConf);
  put(right ?? left.map((k, v) => MapEntry(k, v + const Vec2(-0.01, 0))), BodySide.right, rightConf);
  final n = nose ?? (left['shoulder']! + const Vec2(0, -0.12));
  lm[LandmarkId.nose.index] = Landmark(n.x, n.y, confidence: 0.95);
  return BodyPose(lm, aspect: 1);
}

/// Standing side-view pose with a given knee angle produced by bending.
BodyPose sideSquat(double kneeDeg) {
  const ankle = Vec2(0.5, 0.9);
  final shin = Vec2.fromDirection(20) * 0.23;
  final knee = ankle + shin;
  // thigh direction: rotate so that the knee angle equals kneeDeg
  final thighDir = 20 + 180 + kneeDeg; // knee->hip direction measured from knee->ankle
  final hip = knee + Vec2.fromDirection(thighDir) * 0.24;
  final shoulder = hip + Vec2.fromDirection(15) * 0.29;
  return poseFrom(left: {
    'ankle': ankle,
    'knee': knee,
    'hip': hip,
    'shoulder': shoulder,
    'elbow': shoulder + const Vec2(0.05, 0.1),
    'wrist': shoulder + const Vec2(0.15, 0.1),
    'heel': ankle + const Vec2(-0.03, 0.03),
    'toe': ankle + const Vec2(0.08, 0.03),
  });
}
