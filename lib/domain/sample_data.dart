import 'dart:math' as math;

import 'exercise.dart';
import 'history.dart';
import 'insights.dart';
import 'routine.dart';
import 'tracking_session.dart';

/// Generates realistic sample history so new installs (and screenshots)
/// can explore Progress, Recover and Coach. Deterministic for a seed.
class SampleData {
  static List<WorkoutSession> history(ExerciseCatalog cat, DateTime now, {int seed = 7}) {
    final rnd = math.Random(seed);
    final presets = {for (final r in RoutinePresets.all(cat)) r.id: r};
    final sessions = <WorkoutSession>[];
    // last 3 weeks following the weekly schedule, skipping a few days
    for (var back = 20; back >= 0; back--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: back));
      final plannedId = RoutinePresets.weekly[day.weekday % 7];
      if (plannedId == null) continue;
      if (back > 0 && rnd.nextDouble() < 0.18) continue;
      if (back == 0) continue; // today still to do
      final routine = presets[plannedId]!;
      final start = DateTime(day.year, day.month, day.day, 18, rnd.nextInt(20));
      final exercises = <SessionExercise>[];
      var minute = 0;
      final progress = (20 - back) / 20; // form improves over time
      for (final it in routine.items) {
        final e = cat.byId(it.exerciseId);
        if (e == null) continue;
        final reps = <RepResult>[];
        final total = e.isTimed ? it.sets : it.sets * it.reps;
        var clean = 0;
        for (var i = 0; i < total; i++) {
          final bad = rnd.nextDouble() < (0.38 - 0.2 * progress);
          final issues = <String>[];
          if (bad && e.rules.isNotEmpty) {
            final r = e.rules[rnd.nextInt(e.rules.length)];
            final side = r.bilateral ? (rnd.nextBool() ? ':left' : ':right') : '';
            issues.add('${r.cue}$side');
          }
          final score = issues.isEmpty ? 90 + rnd.nextInt(11) : 55 + rnd.nextInt(25);
          final ok = issues.isEmpty || score >= 65;
          if (ok) clean++;
          reps.add(RepResult(
            index: i + 1,
            clean: ok,
            score: score,
            depthReached: ok,
            peak: e.thresholds.depth + (rnd.nextDouble() * 10 - 5),
            tempo: 1.8 + rnd.nextDouble(),
            issues: issues,
            time: i * 2.4,
          ));
        }
        final avg = reps.map((r) => r.score).reduce((a, b) => a + b) / reps.length;
        exercises.add(SessionExercise(
          exerciseId: e.id,
          sets: it.sets,
          attempts: reps.length,
          cleanReps: clean,
          seconds: e.isTimed ? it.seconds * it.sets : 0,
          avgForm: avg,
          bestPeak: e.thresholds.depth - 4,
          reps: reps,
        ));
        minute += 6;
      }
      sessions.add(WorkoutSession(
        id: 's_${start.millisecondsSinceEpoch}',
        startedAt: start,
        endedAt: start.add(Duration(minutes: minute + 4)),
        routineName: routine.name,
        exercises: exercises,
      ));
    }
    return sessions;
  }

  static List<LabLabel> labLabels(DateTime now, {int seed = 3}) {
    final rnd = math.Random(seed);
    const ex = ['squat', 'lunge', 'push_up', 'bicep_curl', 'shoulder_press', 'lateral_raise', 'plank', 'deadlift'];
    final out = <LabLabel>[];
    for (var i = 0; i < 160; i++) {
      final e = ex[i % ex.length];
      final good = rnd.nextBool();
      final right = rnd.nextDouble() < 0.88;
      out.add(LabLabel(e, good, right, now.subtract(Duration(minutes: 160 - i))));
    }
    return out;
  }
}
