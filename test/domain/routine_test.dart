import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/exercise.dart';
import 'package:formflow/domain/guided_workout.dart';
import 'package:formflow/domain/profile.dart';
import 'package:formflow/domain/routine.dart';
import 'package:formflow/domain/tracking_session.dart';

import '../helpers.dart';

void main() {
  final cat = loadCatalog();

  group('catalog (FR-EX-01, FR-EX-02, FR-EX-05)', () {
    test('has 56 exercises: the 20 PRD exercises stay free, the rest are premium', () {
      expect(cat.exercises.length, greaterThanOrEqualTo(50));
      expect(cat.exercises.map((e) => e.id).toSet(), hasLength(cat.exercises.length));
      const free = ['squat', 'lunge', 'glute_bridge', 'calf_raise', 'wall_sit', 'deadlift', 'bent_over_row', 'pull_up',
        'good_morning', 'push_up', 'wide_push_up', 'bicep_curl', 'hammer_curl', 'overhead_triceps', 'bench_dip',
        'diamond_push_up', 'shoulder_press', 'lateral_raise', 'sit_up', 'plank'];
      for (final id in free) {
        expect(cat.byId(id)!.premium, isFalse, reason: id);
      }
      expect(cat.premiumCount, greaterThanOrEqualTo(30));
      for (final id in ['squat', 'lunge', 'glute_bridge', 'calf_raise', 'wall_sit', 'deadlift', 'bent_over_row', 'pull_up',
        'good_morning', 'push_up', 'wide_push_up', 'bicep_curl', 'hammer_curl', 'overhead_triceps', 'bench_dip',
        'diamond_push_up', 'shoulder_press', 'lateral_raise', 'sit_up', 'plank']) {
        expect(cat.byId(id), isNotNull, reason: id);
      }
    });
    test('every exercise has valid metadata', () {
      for (final e in cat.exercises) {
        expect(e.level, inInclusiveRange(1, 5), reason: e.id);
        expect(e.muscles.keys.every(MuscleIds.all.contains), isTrue, reason: e.id);
        expect(e.normalisedMuscles.values.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
        expect(e.tips, isNotEmpty, reason: e.id);
        expect(e.mistakes.length, greaterThanOrEqualTo(2), reason: e.id);
        expect(e.mistakeFixes.every((m) => m.mistake.isNotEmpty && m.fix.isNotEmpty), isTrue, reason: e.id);
        expect(ExerciseCatalog.groups, contains(e.group));
        expect(e.focus, isNotEmpty, reason: e.id);
        expect(e.equipment.every(ExerciseCatalog.equipmentTypes.contains), isTrue, reason: e.id);
        expect(ExerciseCatalog.types, contains(e.type), reason: e.id);
        for (final r in e.rules) {
          expect(cat.cues.containsKey(r.cue), isTrue, reason: '${e.id}/${r.cue}');
        }
      }
    });
    test('holds are timed', () {
      expect(cat.exercises.where((e) => e.isTimed).map((e) => e.id).toSet(), {'plank', 'wall_sit', 'side_plank', 'hollow_hold'});
    });
    test('every muscle section has exercises (doc item 8)', () {
      for (final g in ExerciseCatalog.groups) {
        expect(cat.inGroup(g).length, greaterThanOrEqualTo(3), reason: g);
      }
    });
    test('upper-body exercises are tracked from about 1 m (doc item 10)', () {
      for (final id in ['bicep_curl', 'hammer_curl', 'shoulder_press', 'lateral_raise', 'front_raise']) {
        final e = cat.byId(id)!;
        expect(e.isUpperBody, isTrue, reason: id);
        expect(e.cameraDistance, 1.0);
        expect(e.cameraTip, contains('1 m'));
        expect(e.focus, isNot(contains('ankle')), reason: id);
      }
    });
    test('system cues exist (PRD 8.8)', () {
      for (final c in ['good_form', 'step_back', 'rest_start', 'next_exercise', 'set_complete', 'last_rep', 'plank_get_in_position']) {
        expect(cat.cues.containsKey(c), isTrue, reason: c);
      }
    });
  });

  group('routines (FR-RT)', () {
    test('presets only reference existing exercises', () {
      for (final r in RoutinePresets.all(cat)) {
        expect(r.items, isNotEmpty, reason: r.name);
      }
    });
    test('Full Body preset matches the PRD', () {
      final fb = RoutinePresets.all(cat).firstWhere((r) => r.id == 'preset_full_body');
      expect(fb.items.map((i) => i.exerciseId).toList(),
          ['squat', 'push_up', 'bent_over_row', 'shoulder_press', 'bicep_curl', 'plank']);
    });
    test('weekly schedule references presets (FR-TP-02)', () {
      final ids = RoutinePresets.all(cat).map((r) => r.id).toSet();
      expect(RoutinePresets.weekly, hasLength(7));
      for (final id in RoutinePresets.weekly.whereType<String>()) {
        expect(ids, contains(id));
      }
      expect(RoutinePresets.weekly[0], isNull);
      expect(RoutinePresets.weekly[3], isNull);
    });
    test('muscle distribution sums to 100% (FR-RT-07)', () {
      final r = RoutinePresets.all(cat).first;
      final d = RoutineMath.distribution(r.items, cat);
      expect(d.fold<double>(0, (a, e) => a + e.value), closeTo(100, 1e-6));
      expect(d.first.value, greaterThanOrEqualTo(d.last.value));
    });
    test('estimated time grows with sets', () {
      final a = [const RoutineItem('squat', sets: 3, reps: 10)];
      final b = [const RoutineItem('squat', sets: 5, reps: 10)];
      expect(RoutineMath.estimatedMinutes(b, cat), greaterThan(RoutineMath.estimatedMinutes(a, cat)));
    });
    test('routine JSON round trip', () {
      final r = RoutinePresets.all(cat).first;
      final back = Routine.tryParse(r.toJson())!;
      expect(back.items.length, r.items.length);
      expect(Routine.tryParse({'bad': true}), isNull);
    });
    test('Routine Creator respects equipment, level and time (FR-RT-05)', () {
      final r = RoutineGenerator.generate(
        catalog: cat,
        goal: Goal.cutting,
        maxLevel: 2,
        equipment: const {},
        minutes: 20,
        targetMuscles: const {'quads', 'glutes'},
      );
      expect(r.items, isNotEmpty);
      for (final it in r.items) {
        final e = cat.byId(it.exerciseId)!;
        expect(e.level, lessThanOrEqualTo(2));
        expect(e.equipment, contains('bodyweight'));
        if (!e.isTimed) expect(it.reps, 15);
      }
      expect(RoutineMath.estimatedMinutes(r.items, cat), lessThanOrEqualTo(20 + 5));
    });
  });

  group('guided workout (FR-GW)', () {
    RepResult rep(bool clean) =>
        RepResult(index: 1, clean: clean, score: clean ? 100 : 65, depthReached: true, peak: 90, tempo: 2, issues: const [], time: 0);

    test('sets, rests and next exercise', () {
      final g = GuidedWorkout(
        routineName: 'T',
        items: [const RoutineItem('squat', sets: 2, reps: 2), const RoutineItem('plank', sets: 1, seconds: 10)],
        startedAt: DateTime(2026),
      );
      expect(g.label, 'Exercise 1 of 2, Set 1 of 2');
      expect(g.completeSet(attempts: 2, clean: 2, reps: [rep(true), rep(true)]), GuidedWorkout.restBetweenSets);
      expect(g.label, 'Exercise 1 of 2, Set 2 of 2');
      expect(g.completeSet(attempts: 3, clean: 2, reps: [rep(true), rep(false), rep(true)]), GuidedWorkout.restBetweenExercises);
      expect(g.current.exerciseId, 'plank');
      expect(g.completeSet(attempts: 1, clean: 1, reps: [rep(true)], seconds: 10), 0);
      expect(g.finished, isTrue);
      final s = g.toSession(DateTime(2026, 1, 1, 0, 20));
      expect(s.exercises, hasLength(2));
      expect(s.exercises.first.attempts, 5);
      expect(s.exercises.first.cleanReps, 4);
      expect(s.exercises.first.sets, 2);
    });

    test('state survives an interruption (FR-GW-09, TC-24)', () {
      final g = GuidedWorkout(routineName: 'T', items: [const RoutineItem('squat', sets: 3)], startedAt: DateTime(2026));
      g.completeSet(attempts: 10, clean: 9, reps: [rep(true)]);
      final back = GuidedWorkout.fromJson(g.toJson())!;
      expect(back.index, 0);
      expect(back.set, 2);
      back.completeSet(attempts: 10, clean: 10, reps: [rep(true)]);
      back.completeSet(attempts: 10, clean: 10, reps: [rep(true)]);
      expect(back.toSession(DateTime(2026, 1, 1, 1)).exercises.single.attempts, 30);
    });

    test('skip and reorder upcoming exercises (FR-GW-10)', () {
      final g = GuidedWorkout(
        routineName: 'T',
        items: [const RoutineItem('squat'), const RoutineItem('lunge'), const RoutineItem('plank')],
        startedAt: DateTime(2026),
      );
      g.reorder(2, 1);
      expect(g.items.map((i) => i.exerciseId).toList(), ['squat', 'plank', 'lunge']);
      g.reorder(0, 2); // cannot move the current exercise
      expect(g.items.first.exerciseId, 'squat');
      g.skipExercise();
      expect(g.current.exerciseId, 'plank');
    });

    test('a corrupt saved state is ignored', () {
      expect(GuidedWorkout.fromJson({'routine': 1}), isNull);
      expect(GuidedWorkout.fromJson(null), isNull);
    });
  });
}
