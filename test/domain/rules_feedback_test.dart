import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/exercise.dart';
import 'package:formflow/domain/feedback.dart';
import 'package:formflow/domain/landmarks.dart';
import 'package:formflow/domain/rules.dart';

import '../helpers.dart';

RuleDef rule(String id, {CueCategory cat = CueCategory.form, Severity sev = Severity.moderate, String phase = 'moving'}) =>
    RuleDef(id: id, when: const {'x': Condition(gt: 0)}, cue: id, category: cat, severity: sev, phase: phase);

void main() {
  final cues = CueBook(loadCatalog().cues);

  group('CueBook (FR-VF-02)', () {
    test('names the side for bilateral cues', () {
      expect(cues.text('squat_knees_out', side: BodySide.left), 'Push your left knee out');
      expect(cues.text('squat_knees_out', side: BodySide.right), 'Push your right knee out');
    });
    test('uses the neutral wording when the side is unknown', () {
      expect(cues.text('squat_knees_out'), 'Push your knees out');
      expect(cues.text('squat_go_lower'), 'Go lower, bend your knees more');
    });
    test('clip path follows cue id and side', () {
      expect(CueBook.clipPath('squat_knees_out', side: BodySide.left), 'assets/audio/en/squat_knees_out_left.ogg');
    });
  });

  group('Scoring (FR-FA-06)', () {
    test('severity weights', () {
      expect(Scoring.repScore([]), 100);
      expect(Scoring.repScore([Severity.minor]), 90);
      expect(Scoring.repScore([Severity.moderate]), 80);
      expect(Scoring.repScore([Severity.major]), 65);
      expect(Scoring.repScore([Severity.major, Severity.moderate]), 45);
    });
    test('never below zero', () {
      expect(Scoring.repScore([Severity.major, Severity.major, Severity.major, Severity.major]), 0);
    });
    test('bands', () {
      expect(Scoring.band(85), 'good');
      expect(Scoring.band(60), 'fair');
      expect(Scoring.band(30), 'poor');
    });
  });

  group('Conditions', () {
    test('gt / lt / bool', () {
      expect(const Condition(gt: 5).test(6), isTrue);
      expect(const Condition(gt: 5).test(5), isFalse);
      expect(const Condition(lt: 5, gt: 1).test(3), isTrue);
      expect(RuleEngine.conditionsHold({'depthReached': const Condition(equals: false)}, {'depthReached': 0}), isTrue);
      expect(RuleEngine.conditionsHold({'depthReached': const Condition(equals: false)}, {'depthReached': 1}), isFalse);
      expect(RuleEngine.conditionsHold({'missing': const Condition(gt: 0)}, {}), isFalse);
    });
  });

  group('RuleEngine persistence (FR-FA-04)', () {
    final def = loadCatalog().byId('squat')!;
    test('back lean is reported only after 4 consecutive frames', () {
      final engine = RuleEngine(def.rules);
      final leaning = sideSquat(100); // torso lean handled below
      // build a strongly leaning pose by moving the shoulder forward
      final l = leaning.landmarks.toList();
      final hip = leaning[LandmarkId.leftHip];
      l[LandmarkId.leftShoulder.index] = Landmark(hip.x + 0.27, hip.y - 0.1, confidence: 0.95);
      l[LandmarkId.rightShoulder.index] = Landmark(hip.x + 0.26, hip.y - 0.1, confidence: 0.9);
      final pose = BodyPose(l, aspect: 1);
      final counts = <int>[];
      for (var i = 0; i < 6; i++) {
        counts.add(engine.evaluate(pose, Phase.lowering, CameraView.side, BodySide.left).length);
      }
      expect(counts.take(3), everyElement(0));
      expect(counts.skip(3), everyElement(1));
    });

    test('front-only rules are skipped in side view (FR-FA-10)', () {
      final engine = RuleEngine(def.rules);
      expect(engine.skippedForView(CameraView.side).map((r) => r.id), contains('knee_cave'));
      expect(engine.skippedForView(CameraView.front), isEmpty);
    });

    test('rep-end rule fires when depth not reached', () {
      final engine = RuleEngine(def.rules);
      final issues = engine.evaluateRepEnd({'depthReached': 0});
      expect(issues.map((i) => i.cue), ['squat_go_lower']);
      expect(engine.evaluateRepEnd({'depthReached': 1}), isEmpty);
    });
  });

  group('FeedbackManager', () {
    test('at most one spoken correction every 3 s (FR-VF-03)', () {
      final f = FeedbackManager(cues: cues);
      final a = Issue(rule('a'), null), b = Issue(rule('b'), null);
      expect(f.onFrame([a], 0).where((x) => x.kind == FeedbackKind.speak), hasLength(1));
      expect(f.onFrame([b], 1.0).where((x) => x.kind == FeedbackKind.speak), isEmpty);
      expect(f.onFrame([b], 3.1).where((x) => x.kind == FeedbackKind.speak), hasLength(1));
    });

    test('same cue at least 4 s apart', () {
      final f = FeedbackManager(cues: cues);
      final a = Issue(rule('a'), null);
      expect(f.onFrame([a], 0).any((x) => x.kind == FeedbackKind.speak), isTrue);
      expect(f.onFrame([a], 3.5).any((x) => x.kind == FeedbackKind.speak), isFalse);
      expect(f.onFrame([a], 4.1).any((x) => x.kind == FeedbackKind.speak), isTrue);
    });

    test('safety beats form beats depth', () {
      final f = FeedbackManager(cues: cues);
      final form = Issue(rule('form_cue', sev: Severity.major), null);
      final safety = Issue(rule('safety_cue', cat: CueCategory.safety, sev: Severity.minor), null);
      final spoken = f.onFrame([form, safety], 0).firstWhere((x) => x.kind == FeedbackKind.speak);
      expect(spoken.cueId, 'safety_cue');
    });

    test('depth cues are not spoken mid-rep (FR-VF-05)', () {
      final f = FeedbackManager(cues: cues);
      final depth = Issue(rule('squat_go_lower', cat: CueCategory.depth), null);
      expect(f.onFrame([depth], 0), isEmpty);
      final end = f.onRepEnd(repIssues: [depth], clean: false, cleanCount: 0, t: 0.1);
      expect(end.any((x) => x.kind == FeedbackKind.speak && x.cueId == 'squat_go_lower'), isTrue);
    });

    test('correction loop confirms a fixed error (FR-VF-04, TC-21)', () {
      final f = FeedbackManager(cues: cues);
      final cave = Issue(rule('squat_knees_out'), BodySide.left);
      final spoken = f.onFrame([cave], 0);
      expect(spoken.first.text, 'Push your left knee out');
      f.onRepEnd(repIssues: [cave], clean: false, cleanCount: 0, t: 1.0);
      final next = f.onRepEnd(repIssues: const [], clean: true, cleanCount: 1, t: 3.5);
      expect(next.any((x) => x.cueId == 'good_form' && x.text == "Good, that's right"), isTrue);
      expect(f.pendingRecheck, isEmpty);
    });

    test('repeats once, then visual and haptic only (FR-VF-04, TC-22)', () {
      final f = FeedbackManager(cues: cues);
      final cave = Issue(rule('squat_knees_out'), BodySide.right);
      var spokenCount = 0;
      var hapticOnly = 0;
      for (var rep = 0; rep < 6; rep++) {
        final t = rep * 4.5;
        final acts = f.onRepEnd(repIssues: [cave], clean: false, cleanCount: 0, t: t);
        if (acts.any((a) => a.kind == FeedbackKind.speak)) spokenCount++;
        if (acts.isNotEmpty && acts.every((a) => a.kind == FeedbackKind.haptic)) hapticOnly++;
      }
      expect(spokenCount, 2);
      expect(hapticOnly, 4);
    });

    test('rep numbers every 5th clean rep by default (FR-VF-06)', () {
      final f = FeedbackManager(cues: cues);
      final spokenNumbers = <String>[];
      for (var i = 1; i <= 10; i++) {
        final acts = f.onRepEnd(repIssues: const [], clean: true, cleanCount: i, t: i * 2.0);
        expect(acts.any((a) => a.kind == FeedbackKind.tone), isTrue);
        spokenNumbers.addAll(acts.where((a) => a.cueId == 'count').map((a) => a.text!));
      }
      expect(spokenNumbers, ['5', '10']);
    });

    test('muted voice produces no speech', () {
      final f = FeedbackManager(cues: cues, voiceEnabled: false);
      expect(f.onFrame([Issue(rule('a'), null)], 0).where((a) => a.kind == FeedbackKind.speak), isEmpty);
    });
  });
}
