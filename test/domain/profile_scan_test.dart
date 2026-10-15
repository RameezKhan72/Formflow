import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/body_scan.dart';
import 'package:formflow/domain/demo_motion.dart';
import 'package:formflow/domain/exercise.dart';
import 'package:formflow/domain/geometry.dart';
import 'package:formflow/domain/landmarks.dart';
import 'package:formflow/domain/measurements.dart';
import 'package:formflow/domain/profile.dart';

import '../helpers.dart';

void main() {
  group('Validators (FR-AU-03, NFR-SC-04)', () {
    test('email', () {
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email(''), isNotNull);
    });
    test('password must be 6+ characters', () {
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });
    test('name required', () {
      expect(Validators.name('  '), isNotNull);
      expect(Validators.name('Rameez'), isNull);
    });
    test('age gate 18+ (FR-AU-10)', () {
      expect(Validators.age(17), isNotNull);
      expect(Validators.age(18), isNull);
    });
    test('profile JSON keeps values and fills missing ones with defaults (FR-PR-02)', () {
      const p = UserProfile(name: 'Rameez', age: 21, weightKg: 70, goal: Goal.cutting, useLb: true);
      final back = UserProfile.fromJson(p.toJson());
      expect(back.name, 'Rameez');
      expect(back.goal, Goal.cutting);
      expect(back.weightLabel, '154.3 lb');
      final partial = UserProfile.fromJson({'name': 'A'});
      expect(partial.weeklyTarget, 5);
      expect(partial.heightCm, 175);
    });
  });

  group('measurements', () {
    test('side view vs front view', () {
      expect(Measurements.viewOf(sideSquat(170)), CameraView.side);
      final front = SyntheticPose.fromMannequin(MannequinRig.solve(
          const Keyframes(view: 'front', anchorX: 0.5, start: {'upperArm': 170}, end: {'upperArm': 170}), 0));
      expect(Measurements.viewOf(front), CameraView.front);
    });

    test('knee angle from a synthetic squat', () {
      final m = Measurements.forSide(sideSquat(95), BodySide.left);
      expect(m['kneeAngle'], closeTo(95, 0.5));
    });

    test('hipOffset is positive when hips sag', () {
      Map<String, Vec2> body(double hipDrop) => {
            'ankle': const Vec2(0.1, 0.85),
            'hip': Vec2(0.45, 0.75 + hipDrop),
            'shoulder': const Vec2(0.8, 0.65),
            'knee': Vec2(0.28, 0.8 + hipDrop / 2),
            'elbow': const Vec2(0.8, 0.8),
            'wrist': const Vec2(0.82, 0.92),
            'heel': const Vec2(0.08, 0.84),
            'toe': const Vec2(0.12, 0.9),
          };
      expect(Measurements.forSide(poseFrom(left: body(0.06)), BodySide.left)['hipOffset']!, greaterThan(0.1));
      expect(Measurements.forSide(poseFrom(left: body(-0.06)), BodySide.left)['hipOffset']!, lessThan(-0.1));
      expect(Measurements.forSide(poseFrom(left: body(0)), BodySide.left)['hipOffset']!.abs(), lessThan(0.05));
    });

    test('metric side policy: auto uses the more visible side', () {
      final p = poseFrom(
        left: {'hip': const Vec2(0.5, 0.5), 'knee': const Vec2(0.55, 0.7), 'ankle': const Vec2(0.5, 0.9), 'shoulder': const Vec2(0.5, 0.2), 'elbow': const Vec2(0.5, 0.35), 'wrist': const Vec2(0.5, 0.5), 'heel': const Vec2(0.48, 0.92), 'toe': const Vec2(0.58, 0.93)},
        right: {'hip': const Vec2(0.5, 0.5), 'knee': const Vec2(0.5, 0.7), 'ankle': const Vec2(0.5, 0.9), 'shoulder': const Vec2(0.5, 0.2), 'elbow': const Vec2(0.5, 0.35), 'wrist': const Vec2(0.5, 0.5), 'heel': const Vec2(0.48, 0.92), 'toe': const Vec2(0.58, 0.93)},
        leftConf: 0.6,
        rightConf: 0.95,
      );
      final v = Measurements.metricValue(p, const MetricDef(measure: 'kneeAngle'))!;
      expect(v.side, BodySide.right);
      expect(v.value, closeTo(180, 0.1));
      final min = Measurements.metricValue(p, const MetricDef(measure: 'kneeAngle', side: 'min'))!;
      expect(min.side, BodySide.left);
    });

    test('framing checks for camera setup (FR-PE-13)', () {
      final p = SyntheticPose.fromMannequin(MannequinRig.solve(loadCatalog().byId('squat')!.keyframes, 0));
      final f = Measurements.framing(p);
      expect(f.fullBody, isTrue);
      expect(f.distanceOk, isTrue);
    });
  });

  group('Body Profile scan (FR-CB)', () {
    BodyPose front({double arms = 172}) => SyntheticPose.fromMannequin(MannequinRig.solve(
        Keyframes(view: 'front', anchorX: 0.5, start: {'upperArm': arms, 'forearm': arms}, end: {'upperArm': arms, 'forearm': arms}), 0));

    test('a symmetric, complete scan scores high quality', () {
      final caps = {for (final s in ScanStep.values) s: List.generate(30, (_) => front(arms: s == ScanStep.tPose ? 92 : 172))};
      final r = BodyScan.compute(caps);
      expect(r.symmetry, greaterThan(95));
      expect(r.quality, greaterThanOrEqualTo(60));
      expect(r.ratios['thigh_l'], closeTo(r.ratios['thigh_r']!, 1e-6));
    });

    test('missing poses lower the quality and explain what to fix (FR-CB-04)', () {
      final r = BodyScan.compute({ScanStep.front: [front()]});
      expect(r.problems, contains('Complete all five poses'));
    });

    test('no capture gives zero quality', () {
      expect(BodyScan.compute({}).quality, 0);
    });

    test('pre-checks give one instruction (FR-CB-02)', () {
      expect(BodyScan.precheck(null), 'Step into the frame');
      expect(BodyScan.precheck(front(), brightness: 0.1), contains('brighter'));
      expect(BodyScan.precheck(front()), isNull);
    });
  });
}
