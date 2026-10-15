import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/demo_motion.dart';
import 'package:formflow/domain/exercise.dart';
import 'package:formflow/domain/geometry.dart';
import 'package:formflow/domain/landmarks.dart';
import 'package:formflow/domain/measurements.dart';
import 'package:formflow/domain/rules.dart';
import 'package:formflow/domain/tracking_session.dart';

import '../helpers.dart';

/// Replay tests: synthetic landmark sequences from the demonstrator are fed
/// through the real engine (PRD 11.1 "Replay").
void main() {
  final cat = loadCatalog();
  final cues = CueBook(cat.cues);

  TrackingSession replay(ExerciseDef def, {bool mistake = false, double seconds = 0, double fps = 15}) {
    final s = TrackingSession(def, cues: cues, voice: false);
    final m = DemoMotion(def, mistake: mistake);
    final total = seconds > 0 ? seconds : def.keyframes.period * 3.2;
    for (var i = 0; i < total * fps; i++) {
      final t = i / fps;
      s.process(m.pose(t), t);
    }
    return s;
  }

  group('every exercise demonstration is counted by the engine', () {
    for (final def in cat.exercises.where((e) => !e.isTimed)) {
      test('${def.id}: correct reps are clean', () {
        final s = replay(def);
        expect(s.attempts, greaterThanOrEqualTo(2), reason: 'attempts');
        expect(s.cleanReps, s.attempts, reason: 'all reps clean');
        expect(s.averageForm, greaterThanOrEqualTo(80));
      });

      test('${def.id}: shallow reps are flagged', () {
        final s = replay(def, mistake: true);
        expect(s.attempts, greaterThanOrEqualTo(2));
        expect(s.cleanReps, 0);
        expect(s.reps.every((r) => !r.depthReached), isTrue);
        expect(s.topIssue, isNotNull);
      });
    }
  });

  group('timed holds (FR-FA-07)', () {
    test('plank: correct form accumulates seconds', () {
      final s = replay(cat.byId('plank')!, seconds: 5);
      expect(s.holdSeconds, closeTo(5, 0.4));
    });
    test('plank: sagging hips stop the timer and raise a safety cue', () {
      final s = replay(cat.byId('plank')!, mistake: true, seconds: 5);
      expect(s.holdSeconds, lessThan(0.5));
      s.recordTimedResult(5);
      expect(s.reps.single.issues, contains('plank_hips_sag'));
    });
    test('wall sit: sitting too high stops the timer', () {
      final s = replay(cat.byId('wall_sit')!, mistake: true, seconds: 4);
      expect(s.holdSeconds, lessThan(0.5));
    });
  });

  test('front-view squat with the left knee caving names the left knee (TC-21)', () {
    final def = cat.byId('squat')!;
    final s = TrackingSession(def, cues: cues, voice: false);
    BodyPose frontSquat(double depth, {bool cave = false}) {
      // depth 0 = standing, 1 = bottom. Hips drop, knees bend forward (towards camera).
      final hipY = 0.45 + 0.18 * depth;
      final kneeY = 0.68 + 0.02 * depth;
      final leftKneeX = cave ? 0.52 : 0.6;
      // knee angle from the side is approximated by moving the hip down
      final pose = poseFrom(
        left: {
          'shoulder': Vec2(0.62, hipY - 0.3),
          'elbow': Vec2(0.68, hipY - 0.15),
          'wrist': Vec2(0.7, hipY - 0.02),
          'hip': Vec2(0.56, hipY),
          'knee': Vec2(leftKneeX, kneeY),
          'ankle': const Vec2(0.6, 0.9),
          'heel': const Vec2(0.6, 0.93),
          'toe': const Vec2(0.62, 0.94),
        },
        right: {
          'shoulder': Vec2(0.38, hipY - 0.3),
          'elbow': Vec2(0.32, hipY - 0.15),
          'wrist': Vec2(0.3, hipY - 0.02),
          'hip': Vec2(0.44, hipY),
          'knee': Vec2(0.4, kneeY),
          'ankle': const Vec2(0.4, 0.9),
          'heel': const Vec2(0.4, 0.93),
          'toe': const Vec2(0.38, 0.94),
        },
        leftConf: 0.95,
        rightConf: 0.95,
      );
      return pose;
    }

    final pose = frontSquat(1, cave: true);
    expect(Measurements.viewOf(pose), CameraView.front);
    final m = Measurements.all(pose, BodySide.left);
    expect(m['kneeInward']!, greaterThan(0.12));
    expect(m['kneeAngle']!, lessThan(140));
    var issues = <Issue>[];
    for (var i = 0; i < 4; i++) {
      issues = s.engine.evaluate(pose, Phase.lowering, CameraView.front, BodySide.left);
    }
    final cave = issues.where((i) => i.rule.id == 'knee_cave').toList();
    expect(cave, hasLength(1));
    expect(cave.single.side, BodySide.left);
    expect(cues.text(cave.single.cue, side: cave.single.side), 'Push your left knee out');
    expect(Measurements.kneeInward(pose, BodySide.right)!, lessThan(0.12));
  });

  test('person leaving the frame pauses and resumes (FR-PE-10, TC-32)', () {
    final def = cat.byId('squat')!;
    final s = TrackingSession(def, cues: cues, voice: false);
    final m = DemoMotion(def);
    var t = 0.0;
    for (var i = 0; i < 15; i++, t += 1 / 15) {
      s.process(m.pose(t), t);
    }
    FrameResult? r;
    var spokeStepBack = false;
    for (var i = 0; i < 30; i++, t += 1 / 15) {
      r = s.process(null, t);
      if (r.actions.any((a) => a.cueId == 'step_back')) spokeStepBack = true;
    }
    expect(r!.paused, isTrue);
    expect(spokeStepBack, isTrue);
    r = s.process(m.pose(t), t);
    expect(r.paused, isFalse);
  });

  test('low-confidence landmarks are ignored (FR-PE-05)', () {
    final pose = sideSquat(90);
    final weak = BodyPose(pose.landmarks.map((l) => Landmark(l.x, l.y, confidence: 0.3)).toList(), aspect: 1);
    expect(Measurements.metricValue(weak, const MetricDef(measure: 'kneeAngle')), isNull);
  });

  test('random landmark fuzz never throws (TC-20)', () {
    final def = cat.byId('push_up')!;
    final s = TrackingSession(def, cues: cues, voice: false);
    var seed = 7;
    double rnd() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    for (var i = 0; i < 400; i++) {
      final lm = List.generate(LandmarkId.values.length, (_) => Landmark(rnd(), rnd(), confidence: rnd()));
      expect(() => s.process(BodyPose(lm, aspect: 1), i / 15), returnsNormally);
    }
  });

  test('mannequin keeps feet on the floor for standing exercises (FR-DM-02)', () {
    for (final id in ['squat', 'deadlift', 'bicep_curl', 'shoulder_press', 'calf_raise']) {
      final def = cat.byId(id)!;
      for (final u in [0.0, 0.5, 1.0]) {
        final p = MannequinRig.solve(def.keyframes, u);
        final lowest = [p['toe'].y, p['heel'].y].reduce((a, b) => a > b ? a : b);
        expect(lowest, closeTo(MannequinDims.floorY, 0.03), reason: '$id u=$u');
        for (final j in p.j.values) {
          expect(j.y, lessThanOrEqualTo(MannequinDims.floorY + 0.001), reason: '$id u=$u below floor');
        }
      }
    }
  });
}
