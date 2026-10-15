import 'geometry.dart';

/// 33-point BlazePose landmark layout (same order as ML Kit and MediaPipe).
enum LandmarkId {
  nose,
  leftEyeInner,
  leftEye,
  leftEyeOuter,
  rightEyeInner,
  rightEye,
  rightEyeOuter,
  leftEar,
  rightEar,
  leftMouth,
  rightMouth,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftPinky,
  rightPinky,
  leftIndex,
  rightIndex,
  leftThumb,
  rightThumb,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  leftHeel,
  rightHeel,
  leftFootIndex,
  rightFootIndex,
}

enum BodySide { left, right }

extension BodySideX on BodySide {
  String get word => this == BodySide.left ? 'left' : 'right';
  BodySide get other => this == BodySide.left ? BodySide.right : BodySide.left;
}

/// Generic joint names used by exercise definitions ("knee", "hip"...).
enum Joint { shoulder, elbow, wrist, hip, knee, ankle, heel, toe, ear }

Joint jointFromName(String s) {
  switch (s) {
    case 'shoulder':
      return Joint.shoulder;
    case 'elbow':
      return Joint.elbow;
    case 'wrist':
      return Joint.wrist;
    case 'hip':
      return Joint.hip;
    case 'knee':
      return Joint.knee;
    case 'ankle':
      return Joint.ankle;
    case 'heel':
      return Joint.heel;
    case 'toe':
    case 'foot':
      return Joint.toe;
    case 'ear':
      return Joint.ear;
  }
  throw ArgumentError('Unknown joint "$s"');
}

LandmarkId landmarkFor(Joint j, BodySide side) {
  final l = side == BodySide.left;
  switch (j) {
    case Joint.shoulder:
      return l ? LandmarkId.leftShoulder : LandmarkId.rightShoulder;
    case Joint.elbow:
      return l ? LandmarkId.leftElbow : LandmarkId.rightElbow;
    case Joint.wrist:
      return l ? LandmarkId.leftWrist : LandmarkId.rightWrist;
    case Joint.hip:
      return l ? LandmarkId.leftHip : LandmarkId.rightHip;
    case Joint.knee:
      return l ? LandmarkId.leftKnee : LandmarkId.rightKnee;
    case Joint.ankle:
      return l ? LandmarkId.leftAnkle : LandmarkId.rightAnkle;
    case Joint.heel:
      return l ? LandmarkId.leftHeel : LandmarkId.rightHeel;
    case Joint.toe:
      return l ? LandmarkId.leftFootIndex : LandmarkId.rightFootIndex;
    case Joint.ear:
      return l ? LandmarkId.leftEar : LandmarkId.rightEar;
  }
}

class Landmark {
  /// x in [0, aspect], y in [0, 1] (aspect-corrected so angles are true).
  final double x;
  final double y;
  final double z;
  final double confidence;
  const Landmark(this.x, this.y, {this.z = 0, this.confidence = 1});

  Vec2 get point => Vec2(x, y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'c': confidence};
}

/// One detected body. [aspect] = image width / height.
class BodyPose {
  final List<Landmark> landmarks;
  final double aspect;
  BodyPose(this.landmarks, {this.aspect = 0.75})
      : assert(landmarks.length == LandmarkId.values.length);

  Landmark operator [](LandmarkId id) => landmarks[id.index];

  /// Landmark if its confidence passes [gate], otherwise null (FR-PE-05).
  Vec2? point(LandmarkId id, {double gate = 0.5}) {
    final l = landmarks[id.index];
    return l.confidence >= gate ? l.point : null;
  }

  Vec2? joint(Joint j, BodySide s, {double gate = 0.5}) =>
      point(landmarkFor(j, s), gate: gate);

  static const defaultJoints = [Joint.shoulder, Joint.elbow, Joint.wrist, Joint.hip, Joint.knee, Joint.ankle];

  /// Summed confidence of one body side, only over [joints] (the exercise
  /// focus) so unrelated landmarks cannot pick the wrong side.
  double sideConfidence(BodySide s, {List<Joint>? joints}) {
    var sum = 0.0;
    for (final j in joints ?? defaultJoints) {
      sum += this[landmarkFor(j, s)].confidence;
    }
    return sum;
  }

  /// Body bounds in normalised (0..1) coordinates, using confident points
  /// (optionally only [only]).
  ({double minX, double maxX, double minY, double maxY})? bounds({double gate = 0.5, Set<LandmarkId>? only}) {
    double? minX, maxX, minY, maxY;
    for (final id in LandmarkId.values) {
      if (only != null && !only.contains(id)) continue;
      final l = landmarks[id.index];
      if (l.confidence < gate) continue;
      final nx = l.x / aspect;
      minX = minX == null || nx < minX ? nx : minX;
      maxX = maxX == null || nx > maxX ? nx : maxX;
      minY = minY == null || l.y < minY ? l.y : minY;
      maxY = maxY == null || l.y > maxY ? l.y : maxY;
    }
    if (minX == null) return null;
    return (minX: minX, maxX: maxX!, minY: minY!, maxY: maxY!);
  }
}

/// Parses exercise focus names ("shoulder", "knee", ...) into joints.
List<Joint> jointsFromNames(Iterable<String> names) {
  final out = <Joint>[];
  for (final n in names) {
    for (final j in Joint.values) {
      if (j.name == n) out.add(j);
    }
  }
  return out;
}

/// Both-side landmarks for a set of focus joints.
Set<LandmarkId> focusLandmarks(Iterable<String> names) => {
      for (final j in jointsFromNames(names)) ...[landmarkFor(j, BodySide.left), landmarkFor(j, BodySide.right)],
    };

/// Skeleton connections used for drawing.
const List<List<LandmarkId>> skeletonBones = [
  [LandmarkId.leftShoulder, LandmarkId.rightShoulder],
  [LandmarkId.leftShoulder, LandmarkId.leftElbow],
  [LandmarkId.leftElbow, LandmarkId.leftWrist],
  [LandmarkId.rightShoulder, LandmarkId.rightElbow],
  [LandmarkId.rightElbow, LandmarkId.rightWrist],
  [LandmarkId.leftShoulder, LandmarkId.leftHip],
  [LandmarkId.rightShoulder, LandmarkId.rightHip],
  [LandmarkId.leftHip, LandmarkId.rightHip],
  [LandmarkId.leftHip, LandmarkId.leftKnee],
  [LandmarkId.leftKnee, LandmarkId.leftAnkle],
  [LandmarkId.rightHip, LandmarkId.rightKnee],
  [LandmarkId.rightKnee, LandmarkId.rightAnkle],
  [LandmarkId.leftAnkle, LandmarkId.leftHeel],
  [LandmarkId.leftHeel, LandmarkId.leftFootIndex],
  [LandmarkId.leftAnkle, LandmarkId.leftFootIndex],
  [LandmarkId.rightAnkle, LandmarkId.rightHeel],
  [LandmarkId.rightHeel, LandmarkId.rightFootIndex],
  [LandmarkId.rightAnkle, LandmarkId.rightFootIndex],
];

/// Smooths every landmark coordinate with a One Euro filter (FR-PE-06).
class PoseSmoother {
  final List<OneEuroFilter> _fx;
  final List<OneEuroFilter> _fy;
  PoseSmoother({double minCutoff = 1.2, double beta = 0.02})
      : _fx = List.generate(LandmarkId.values.length, (_) => OneEuroFilter(minCutoff: minCutoff, beta: beta)),
        _fy = List.generate(LandmarkId.values.length, (_) => OneEuroFilter(minCutoff: minCutoff, beta: beta));

  BodyPose smooth(BodyPose p, double tSeconds) {
    final out = <Landmark>[];
    for (var i = 0; i < p.landmarks.length; i++) {
      final l = p.landmarks[i];
      out.add(Landmark(_fx[i].filter(l.x, tSeconds), _fy[i].filter(l.y, tSeconds),
          z: l.z, confidence: l.confidence));
    }
    return BodyPose(out, aspect: p.aspect);
  }

  void reset() {
    for (final f in _fx) {
      f.reset();
    }
    for (final f in _fy) {
      f.reset();
    }
  }
}
