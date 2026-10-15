import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/entitlements.dart';
import 'package:formflow/domain/geometry.dart';
import 'package:formflow/domain/landmarks.dart';
import 'package:formflow/domain/measurements.dart';

import '../helpers.dart';

void main() {
  final cat = loadCatalog();
  final now = DateTime(2026, 10, 15, 12);

  group('premium and ads (doc item 11)', () {
    final free = cat.byId('squat')!;
    final pro = cat.byId('v_up')!;

    test('free users can use free exercises only', () {
      const e = Entitlements();
      expect(e.canUse(free, now), isTrue);
      expect(e.canUse(pro, now), isFalse);
      expect(e.showAds, isTrue);
    });

    test('a rewarded ad unlocks one exercise for 24 hours', () {
      final e = const Entitlements().unlock(pro.id, now);
      expect(e.canUse(pro, now), isTrue);
      expect(e.canUse(pro, now.add(const Duration(hours: 23))), isTrue);
      expect(e.canUse(pro, now.add(const Duration(hours: 25))), isFalse);
      expect(e.canUse(cat.byId('crunch')!, now), isFalse);
      expect(e.remaining(pro.id, now)!.inHours, 24);
      expect(e.showAds, isTrue, reason: 'an ad unlock is not Premium');
    });

    test('Premium and owner access unlock everything and remove ads', () {
      for (final e in [const Entitlements(premium: true), const Entitlements(owner: true)]) {
        expect(cat.exercises.every((x) => e.canUse(x, now)), isTrue);
        expect(e.showAds, isFalse);
      }
    });

    test('entitlements survive a save and load', () {
      final e = const Entitlements(premium: true).unlock(pro.id, now);
      final back = Entitlements.fromJson(e.toJson());
      expect(back.premium, isTrue);
      expect(back.isUnlocked(pro.id, now), isTrue);
      expect(Entitlements.fromJson(const {'unlocked': 'bad'}).unlocked, isEmpty);
    });

    test('expired ad unlocks are dropped on the next unlock', () {
      final e = const Entitlements().unlock('a', now).unlock('b', now.add(const Duration(days: 2)));
      expect(e.unlocked.keys, ['b']);
    });

    test('owner code check ignores case and spaces', () {
      expect(OwnerCode.check(' my-secret ', expected: 'MY-SECRET'), isTrue);
      expect(OwnerCode.check('wrong', expected: 'MY-SECRET'), isFalse);
      expect(OwnerCode.check('', expected: ''), isFalse);
    });
  });

  group('focus landmarks (doc items 9 and 10)', () {
    // Upper body only: legs are out of frame at 1 m.
    BodyPose upperOnly({double conf = 0.95}) {
      final lm = List<Landmark>.filled(LandmarkId.values.length, const Landmark(0, 0, confidence: 0.05));
      void put(LandmarkId id, double x, double y) => lm[id.index] = Landmark(x, y, confidence: conf);
      put(LandmarkId.nose, 0.5, 0.12);
      put(LandmarkId.leftShoulder, 0.6, 0.3);
      put(LandmarkId.rightShoulder, 0.4, 0.3);
      put(LandmarkId.leftElbow, 0.63, 0.55);
      put(LandmarkId.rightElbow, 0.37, 0.55);
      put(LandmarkId.leftWrist, 0.64, 0.78);
      put(LandmarkId.rightWrist, 0.36, 0.78);
      put(LandmarkId.leftHip, 0.57, 0.9);
      put(LandmarkId.rightHip, 0.43, 0.9);
      return BodyPose(lm, aspect: 1);
    }

    test('upper-body exercises frame head to hips; full-body ones need the legs', () {
      final p = upperOnly();
      final curl = cat.byId('bicep_curl')!;
      final squat = cat.byId('squat')!;
      final fc = Measurements.framing(p, focus: curl.focus);
      expect(fc.fullBody, isTrue);
      expect(fc.distanceOk, isTrue);
      expect(Measurements.framing(p, focus: squat.focus).fullBody, isFalse);
      expect(Measurements.framing(p).fullBody, isFalse);
    });

    test('side choice only uses the focus joints', () {
      // left arm is clear, right arm hidden; the right LEG is very confident
      final lm = List<Landmark>.filled(LandmarkId.values.length, const Landmark(0.5, 0.5, confidence: 0.1));
      void put(LandmarkId id, double c) => lm[id.index] = Landmark(0.5, 0.5, confidence: c);
      for (final id in [LandmarkId.leftShoulder, LandmarkId.leftElbow, LandmarkId.leftWrist]) {
        put(id, 0.9);
      }
      for (final id in [LandmarkId.rightShoulder, LandmarkId.rightElbow, LandmarkId.rightWrist]) {
        put(id, 0.6);
      }
      for (final id in [LandmarkId.rightHip, LandmarkId.rightKnee, LandmarkId.rightAnkle]) {
        put(id, 1.0);
      }
      final p = BodyPose(lm, aspect: 1);
      expect(Measurements.moreVisibleSide(p), BodySide.right, reason: 'all joints: the legs win');
      expect(Measurements.moreVisibleSide(p, focus: jointsFromNames(['shoulder', 'elbow', 'wrist'])), BodySide.left);
    });

    test('focus names map to both sides and skip unknown names', () {
      final s = focusLandmarks(['elbow', 'nonsense']);
      expect(s, {LandmarkId.leftElbow, LandmarkId.rightElbow});
    });

    test('thigh angle is measured for side-lift exercises', () {
      final p = poseFrom(left: {
        'hip': const Vec2(0.5, 0.5),
        'knee': const Vec2(0.7, 0.5),
        'ankle': const Vec2(0.7, 0.7),
        'shoulder': const Vec2(0.5, 0.2),
      });
      expect(Measurements.forSide(p, BodySide.left)['thighAngle'], closeTo(90, 1));
    });
  });
}
