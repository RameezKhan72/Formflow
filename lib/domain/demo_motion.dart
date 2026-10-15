import 'dart:math' as math;

import 'exercise.dart';
import 'geometry.dart';
import 'landmarks.dart';

/// Segment lengths of the 2D mannequin (fraction of the drawing box).
class MannequinDims {
  static const shin = 0.23;
  static const thigh = 0.24;
  static const torso = 0.29;
  static const neck = 0.05;
  static const headR = 0.052;
  static const upperArm = 0.16;
  static const forearm = 0.15;
  static const footFwd = 0.085;
  static const heelBack = 0.03;
  static const footDrop = 0.035;
  static const floorY = 0.93;
  static const hipHalf = 0.055;
  static const shoulderHalf = 0.095;
}

/// Joint positions of the mannequin in a unit box (x right, y down).
class MannequinPose {
  final Map<String, Vec2> j;
  final bool front;
  final double scale;
  const MannequinPose(this.j, {this.front = false, this.scale = 1.0});

  Vec2 operator [](String k) => j[k]!;
}

/// Smooth loop timing from the SRS: u = 0.5 - 0.5 cos(2 pi t / T).
double loopU(double tSeconds, double period) => 0.5 - 0.5 * math.cos(2 * math.pi * tSeconds / period);

Map<String, double> lerpAngles(Map<String, double> a, Map<String, double> b, double u) {
  final keys = {...a.keys, ...b.keys};
  final out = <String, double>{};
  for (final k in keys) {
    final va = a[k] ?? b[k]!;
    final vb = b[k] ?? a[k]!;
    out[k] = va + (vb - va) * u;
  }
  return out;
}

/// Forward kinematics from keyframe angles (degrees; 0 = up, 90 = right).
class MannequinRig {
  static double _g(Map<String, double> a, String k, double d) => a[k] ?? d;

  /// Fills missing keys so both keyframes interpolate the same joints
  /// (far limbs default to the near limb of the same frame).
  static Map<String, double> complete(Map<String, double> m) {
    final out = Map<String, double>.from(m);
    const defaults = {'shin': 0.0, 'thigh': 0.0, 'torso': 0.0, 'upperArm': 180.0, 'forearm': 180.0, 'foot': 90.0};
    defaults.forEach((k, v) => out.putIfAbsent(k, () => v));
    for (final k in ['shin', 'thigh', 'foot', 'upperArm', 'forearm']) {
      out.putIfAbsent('${k}2', () => out[k]!);
    }
    out.putIfAbsent('head', () => out['torso']!);
    return out;
  }

  static MannequinPose solve(Keyframes kf, double u) {
    final a = lerpAngles(complete(kf.start), complete(kf.end), u);
    return kf.view == 'front' ? _front(kf, a) : _side(kf, a);
  }

  static Vec2 _d(double deg) => Vec2.fromDirection(deg);

  static MannequinPose _side(Keyframes kf, Map<String, double> a) {
    final k = kf.scale;
    final shinA = _g(a, 'shin', 0), thighA = _g(a, 'thigh', 0), torsoA = _g(a, 'torso', 0);
    final footA = _g(a, 'foot', 90);
    final ua = _g(a, 'upperArm', 180), fa = _g(a, 'forearm', 180);
    final shin2 = _g(a, 'shin2', shinA), thigh2 = _g(a, 'thigh2', thighA), foot2 = _g(a, 'foot2', footA);
    final ua2 = _g(a, 'upperArm2', ua), fa2 = _g(a, 'forearm2', fa);
    final headA = _g(a, 'head', torsoA);

    final j = <String, Vec2>{};
    const ankle = Vec2(0, 0);
    j['ankle'] = ankle;
    j['knee'] = ankle + _d(shinA) * (MannequinDims.shin * k);
    j['hip'] = j['knee']! + _d(thighA) * (MannequinDims.thigh * k);
    j['shoulder'] = j['hip']! + _d(torsoA) * (MannequinDims.torso * k);
    j['neck'] = j['shoulder']! + _d(headA) * (MannequinDims.neck * k);
    j['head'] = j['neck']! + _d(headA) * (MannequinDims.headR * k);
    j['elbow'] = j['shoulder']! + _d(ua) * (MannequinDims.upperArm * k);
    j['wrist'] = j['elbow']! + _d(fa) * (MannequinDims.forearm * k);
    _foot(j, '', ankle, footA, k);
    // far leg hangs from the hip
    j['knee2'] = j['hip']! + _d(thigh2 + 180) * (MannequinDims.thigh * k);
    j['ankle2'] = j['knee2']! + _d(shin2 + 180) * (MannequinDims.shin * k);
    _foot(j, '2', j['ankle2']!, foot2, k);
    j['elbow2'] = j['shoulder']! + _d(ua2) * (MannequinDims.upperArm * k);
    j['wrist2'] = j['elbow2']! + _d(fa2) * (MannequinDims.forearm * k);

    _anchor(kf, j);
    if (kf.armIk) _armIk(j, k);
    return MannequinPose(j, scale: k);
  }

  static void _foot(Map<String, Vec2> j, String s, Vec2 ankle, double footA, double k) {
    final along = _d(footA);
    final down = _d(footA + 90);
    j['toe$s'] = ankle + along * (MannequinDims.footFwd * k) + down * (MannequinDims.footDrop * k);
    j['heel$s'] = ankle - along * (MannequinDims.heelBack * k) + down * (MannequinDims.footDrop * k);
  }

  /// Half-thickness of the body at each joint, so limbs rest on the floor
  /// instead of sinking into it.
  static const Map<String, double> contactRadius = {
    'head': MannequinDims.headR,
    'shoulder': 0.04,
    'hip': 0.045,
    'knee': 0.028,
    'elbow': 0.022,
    'wrist': 0.015,
    'ankle': 0.02,
  };

  static void _anchor(Keyframes kf, Map<String, Vec2> j) {
    Vec2 shift;
    if (kf.anchor == 'wrist') {
      shift = Vec2(kf.anchorX, kf.anchorY) - j['wrist']!;
    } else {
      // floor: lowest contact point rests on the floor, near ankle at anchorX
      var maxY = -1e9;
      for (final e in j.entries) {
        if (e.key == 'neck') continue;
        if (kf.armIk && (e.key.startsWith('wrist') || e.key.startsWith('elbow'))) continue;
        maxY = math.max(maxY, e.value.y + (contactRadius[e.key.replaceAll('2', '')] ?? 0));
      }
      shift = Vec2(kf.anchorX - j['ankle']!.x, MannequinDims.floorY - maxY);
    }
    for (final k in j.keys.toList()) {
      j[k] = j[k]! + shift;
    }
  }

  /// Two-link IK so the hands rest on the floor under the shoulders
  /// (push-ups, plank); elbows bend towards the feet.
  static void _armIk(Map<String, Vec2> j, double k) {
    for (final s in ['', '2']) {
      final sh = j['shoulder']!;
      final target = Vec2(sh.x + 0.015, MannequinDims.floorY - 0.012);
      final toT = target - sh;
      var dist = toT.length;
      final maxReach = (MannequinDims.upperArm * k) + (MannequinDims.forearm * k) - 1e-4;
      if (dist > maxReach) dist = maxReach;
      final base = math.atan2(toT.y, toT.x);
      final cosA = (((MannequinDims.upperArm * k) * (MannequinDims.upperArm * k) + dist * dist - (MannequinDims.forearm * k) * (MannequinDims.forearm * k)) / (2 * (MannequinDims.upperArm * k) * dist))
          .clamp(-1.0, 1.0);
      final aa = math.acos(cosA);
      final e1 = sh + Vec2(math.cos(base + aa), math.sin(base + aa)) * (MannequinDims.upperArm * k);
      final e2 = sh + Vec2(math.cos(base - aa), math.sin(base - aa)) * (MannequinDims.upperArm * k);
      final elbow = e1.x < e2.x ? e1 : e2; // towards the feet (figure faces right)
      final dir = target - elbow;
      final len = dir.length < 1e-9 ? 1.0 : dir.length;
      j['elbow$s'] = elbow + (s == '2' ? const Vec2(-0.008, -0.004) : const Vec2(0, 0));
      j['wrist$s'] = elbow + dir * ((MannequinDims.forearm * k) / len) + (s == '2' ? const Vec2(-0.008, -0.004) : const Vec2(0, 0));
    }
  }

  static MannequinPose _front(Keyframes kf, Map<String, double> a) {
    final cx = kf.anchorX;
    final shinA = _g(a, 'shin', 0), thighA = _g(a, 'thigh', 0), torsoA = _g(a, 'torso', 0);
    final ua = _g(a, 'upperArm', 175), fa = _g(a, 'forearm', 178);
    final j = <String, Vec2>{};
    // screen-right side = person's left (camera image is not mirrored)
    final ankleL = Vec2(cx + 0.07, MannequinDims.floorY - MannequinDims.footDrop);
    final kneeL = ankleL + _d(shinA) * MannequinDims.shin;
    final hipL = kneeL + _d(thighA) * MannequinDims.thigh;
    final hipC = Vec2(hipL.x - MannequinDims.hipHalf, hipL.y);
    final shC = hipC + _d(torsoA) * MannequinDims.torso;
    Vec2 mirror(Vec2 p) => Vec2(2 * cx - p.x, p.y);
    final shL = Vec2(shC.x + MannequinDims.shoulderHalf, shC.y);
    final elL = shL + _d(ua) * MannequinDims.upperArm;
    final wrL = elL + _d(fa) * MannequinDims.forearm;
    j['ankle'] = ankleL;
    j['knee'] = kneeL;
    j['hip'] = hipL;
    j['shoulder'] = shL;
    j['elbow'] = elL;
    j['wrist'] = wrL;
    j['toe'] = ankleL + const Vec2(0.02, 0.03);
    j['heel'] = ankleL + const Vec2(0, 0.035);
    j['ankle2'] = mirror(ankleL);
    j['knee2'] = mirror(kneeL);
    j['hip2'] = mirror(hipL);
    j['shoulder2'] = mirror(shL);
    j['elbow2'] = mirror(elL);
    j['wrist2'] = mirror(wrL);
    j['toe2'] = mirror(j['toe']!);
    j['heel2'] = mirror(j['heel']!);
    j['neck'] = shC + _d(torsoA) * MannequinDims.neck;
    j['head'] = j['neck']! + _d(torsoA) * MannequinDims.headR;
    return MannequinPose(j, front: true);
  }
}

/// Converts mannequin joints into a 33-landmark [BodyPose] so the real
/// engine can run in Demo mode, in tests and in screenshots.
class SyntheticPose {
  static BodyPose fromMannequin(MannequinPose m, {double nearConf = 0.95, double farConf = 0.8}) {
    final lm = List<Landmark>.filled(LandmarkId.values.length, const Landmark(0, 0, confidence: 0));
    void put(LandmarkId id, Vec2 p, double c) => lm[id.index] = Landmark(p.x, p.y, confidence: c);

    Vec2 far(String k) => m.front ? m['${k}2'] : (m.j['${k}2'] ?? m[k]) + const Vec2(-0.01, -0.004);

    final head = m['head'];
    final facing = m.front ? 0.0 : 1.0;
    put(LandmarkId.nose, head + Vec2(0.04 * facing, 0.005), nearConf);
    for (final id in [LandmarkId.leftEyeInner, LandmarkId.leftEye, LandmarkId.leftEyeOuter]) {
      put(id, head + Vec2(m.front ? 0.018 : 0.03, -0.01), nearConf);
    }
    for (final id in [LandmarkId.rightEyeInner, LandmarkId.rightEye, LandmarkId.rightEyeOuter]) {
      put(id, head + Vec2(m.front ? -0.018 : 0.03, -0.01), m.front ? nearConf : farConf);
    }
    put(LandmarkId.leftEar, head + Vec2(m.front ? 0.045 : -0.005, 0), nearConf);
    put(LandmarkId.rightEar, head + Vec2(m.front ? -0.045 : -0.005, 0), m.front ? nearConf : farConf);
    put(LandmarkId.leftMouth, head + Vec2(m.front ? 0.012 : 0.035, 0.025), nearConf);
    put(LandmarkId.rightMouth, head + Vec2(m.front ? -0.012 : 0.035, 0.025), m.front ? nearConf : farConf);

    final fc = m.front ? nearConf : farConf;
    void limb(LandmarkId l, LandmarkId r, String key) {
      put(l, m[key], nearConf);
      put(r, m.front ? m['${key}2'] : far(key), fc);
    }

    // In side view the far hip/shoulder coincide with the near ones.
    put(LandmarkId.leftShoulder, m['shoulder'], nearConf);
    put(LandmarkId.rightShoulder, m.front ? m['shoulder2'] : m['shoulder'] + const Vec2(-0.01, -0.004), fc);
    put(LandmarkId.leftHip, m['hip'], nearConf);
    put(LandmarkId.rightHip, m.front ? m['hip2'] : m['hip'] + const Vec2(-0.01, -0.004), fc);
    limb(LandmarkId.leftElbow, LandmarkId.rightElbow, 'elbow');
    limb(LandmarkId.leftWrist, LandmarkId.rightWrist, 'wrist');
    limb(LandmarkId.leftKnee, LandmarkId.rightKnee, 'knee');
    limb(LandmarkId.leftAnkle, LandmarkId.rightAnkle, 'ankle');
    limb(LandmarkId.leftHeel, LandmarkId.rightHeel, 'heel');
    limb(LandmarkId.leftFootIndex, LandmarkId.rightFootIndex, 'toe');
    for (final pair in [
      [LandmarkId.leftPinky, LandmarkId.leftIndex, LandmarkId.leftThumb],
      [LandmarkId.rightPinky, LandmarkId.rightIndex, LandmarkId.rightThumb],
    ]) {
      final isLeft = pair.first == LandmarkId.leftPinky;
      final w = isLeft ? lm[LandmarkId.leftWrist.index] : lm[LandmarkId.rightWrist.index];
      final e = isLeft ? lm[LandmarkId.leftElbow.index] : lm[LandmarkId.rightElbow.index];
      final dir = w.point - e.point;
      final len = dir.length < 1e-9 ? 1.0 : dir.length;
      final tip = w.point + dir * (0.03 / len);
      for (final id in pair) {
        put(id, tip, w.confidence);
      }
    }
    return BodyPose(lm, aspect: 1.0);
  }
}

/// Generates a stream of demo poses for an exercise. [mistake] makes reps
/// shallow (or, for timed holds, uses the "mistake" end pose).
class DemoMotion {
  final ExerciseDef def;
  bool mistake;
  DemoMotion(this.def, {this.mistake = false});

  double u(double t) {
    if (def.isTimed) return mistake ? 1.0 : 0.0;
    final base = loopU(t, def.keyframes.period);
    return mistake ? base * 0.6 : base;
  }

  MannequinPose mannequin(double t) => MannequinRig.solve(def.keyframes, u(t));

  BodyPose pose(double t) => SyntheticPose.fromMannequin(mannequin(t));
}
