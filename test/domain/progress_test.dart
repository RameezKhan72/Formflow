import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/domain/history.dart';
import 'package:formflow/domain/insights.dart';
import 'package:formflow/domain/profile.dart';
import 'package:formflow/domain/sample_data.dart';
import 'package:formflow/domain/tracking_session.dart';

import '../helpers.dart';

WorkoutSession session(DateTime start, List<SessionExercise> ex, {String name = 'Full Body'}) =>
    WorkoutSession(id: 'x${start.millisecondsSinceEpoch}', startedAt: start, endedAt: start.add(const Duration(minutes: 30)), routineName: name, exercises: ex);

SessionExercise squats({int sets = 3, List<String> issues = const []}) => SessionExercise(
      exerciseId: 'squat',
      sets: sets,
      attempts: 10,
      cleanReps: 8,
      avgForm: 85,
      reps: List.generate(10, (i) => RepResult(index: i + 1, clean: i < 8, score: 85, depthReached: true, peak: 95, tempo: 2, issues: i < 4 ? issues : const [], time: i * 2.0)),
    );

void main() {
  final cat = loadCatalog();
  final now = DateTime(2026, 10, 10, 20); // Saturday

  group('history persistence (FR-PG-01, NFR-RL-02)', () {
    test('session JSON round trip keeps per-rep records', () {
      final s = session(now, [squats(issues: ['squat_knees_out:left'])]);
      final back = WorkoutSession.tryParse(s.toJson())!;
      expect(back.exercises.single.reps, hasLength(10));
      expect(back.exercises.single.reps.first.issues, ['squat_knees_out:left']);
      expect(back.cleanReps, 8);
      expect(back.avgForm, 85);
    });
    test('malformed records are ignored, not fatal', () {
      expect(WorkoutSession.tryParse({'id': 3}), isNull);
      expect(WorkoutSession.tryParse('garbage'), isNull);
    });
  });

  group('calendar and streak (FR-PG-02)', () {
    test('week starts on Sunday', () {
      expect(startOfWeek(now), DateTime(2026, 10, 4));
    });
    test('completed weekdays and weekly count', () {
      final h = [session(DateTime(2026, 10, 5, 18), [squats()]), session(DateTime(2026, 10, 7, 18), [squats()])];
      expect(ProgressStats.completedWeekdays(h, now), {1, 3});
      expect(ProgressStats.workoutsThisWeek(h, now), 2);
    });
    test('streak counts consecutive weeks that met the target', () {
      final h = <WorkoutSession>[];
      for (final weekStart in [DateTime(2026, 9, 20), DateTime(2026, 9, 27)]) {
        for (var d = 1; d <= 3; d++) {
          h.add(session(weekStart.add(Duration(days: d, hours: 18)), [squats()]));
        }
      }
      expect(ProgressStats.streakWeeks(h, now, 3), 2);
      expect(ProgressStats.streakWeeks(h, now, 4), 0);
    });
  });

  group('recovery estimate (FR-PG-03)', () {
    test('worked muscles drop to about 25% right after a heavy session', () {
      final heavy = session(now.subtract(const Duration(minutes: 31)), List.generate(4, (_) => squats(sets: 6)));
      final r = RecoveryModel.estimate([heavy], cat, now);
      expect(r['quads']!, closeTo(25, 3));
      expect(r['biceps'], 100);
    });
    test('fully recovered after 48 hours', () {
      final s = session(now.subtract(const Duration(hours: 49)), [squats(sets: 6)]);
      expect(RecoveryModel.estimate([s], cat, now)['quads'], 100);
    });
    test('recovers linearly in between', () {
      final s = session(now.subtract(const Duration(hours: 24, minutes: 30)), List.generate(4, (_) => squats(sets: 6)));
      expect(RecoveryModel.estimate([s], cat, now)['quads']!, closeTo(62.5, 3));
    });
    test('Fresh Muscle Workout avoids fatigued muscles', () {
      final s = session(now.subtract(const Duration(minutes: 35)), List.generate(4, (_) => squats(sets: 6)));
      final rec = RecoveryModel.estimate([s], cat, now);
      final r = RecoveryModel.freshRoutine(rec, cat);
      expect(r.items, isNotEmpty);
      for (final it in r.items) {
        final e = cat.byId(it.exerciseId)!;
        expect(e.normalisedMuscles['quads'] ?? 0, lessThan(0.25), reason: e.id);
      }
    });
  });

  group('Coach (FR-CO-01..03)', () {
    test('summarises weekly progress and the top issue with its side', () {
      final h = [session(DateTime(2026, 10, 6, 18), [squats(issues: ['squat_knees_out:left'])])];
      final ins = Coach.insights(sessions: h, profile: const UserProfile(weeklyTarget: 5), catalog: cat, now: now);
      expect(ins.first, '1 of 5 workouts done this week');
      expect(ins[1], contains('Left side'));
      expect(ins[1], contains('40%'));
      expect(ins.length, lessThanOrEqualTo(3));
    });
    test('never gives medical advice', () {
      final h = SampleData.history(cat, now);
      final ins = Coach.insights(sessions: h, profile: const UserProfile(), catalog: cat, now: now);
      for (final s in ins) {
        expect(s.toLowerCase(), isNot(contains('diagnos')));
        expect(s.toLowerCase(), isNot(contains('injur')));
      }
    });
  });

  group('Accuracy Test Lab (FR-TL)', () {
    test('confusion matrix, precision, recall and F1', () {
      final t = DateTime(2026);
      final labels = [
        LabLabel('squat', false, true, t), // app bad, truly bad -> TP
        LabLabel('squat', false, true, t), // TP
        LabLabel('squat', false, false, t), // app bad, truly good -> FP
        LabLabel('squat', true, true, t), // TN
        LabLabel('squat', true, false, t), // app good, truly bad -> FN
      ];
      final m = LabMetrics.of(labels);
      expect([m.tp, m.fp, m.tn, m.fn], [2, 1, 1, 1]);
      expect(m.accuracy, closeTo(0.6, 1e-9));
      expect(m.precision, closeTo(2 / 3, 1e-9));
      expect(m.recall, closeTo(2 / 3, 1e-9));
      expect(m.f1, closeTo(2 / 3, 1e-9));
      expect(m.falseAlarmRate, closeTo(0.5, 1e-9));
    });
    test('CSV export columns (FR-TL-03)', () {
      final csv = LabMetrics.csv([LabLabel('plank', true, false, DateTime.utc(2026, 1, 2))]);
      final lines = csv.trim().split('\n');
      expect(lines.first, 'exercise,app_verdict,app_was_right,time');
      expect(lines[1], startsWith('plank,good,false,2026-01-02'));
    });
    test('rep-count error', () {
      expect(LabMetrics.repCountError(19, 20), closeTo(0.05, 1e-9));
      expect(LabMetrics.repCountError(0, 0), 0);
    });
    test('empty lab is all zeros', () {
      final m = LabMetrics.of(const []);
      expect(m.accuracy, 0);
      expect(m.f1, 0);
    });
  });

  test('sample data is deterministic and valid', () {
    final a = SampleData.history(cat, now);
    final b = SampleData.history(cat, now);
    expect(a.length, b.length);
    expect(a, isNotEmpty);
    for (final s in a) {
      expect(s.startedAt.isBefore(now), isTrue);
      for (final e in s.exercises) {
        expect(cat.byId(e.exerciseId), isNotNull);
        expect(e.cleanReps, lessThanOrEqualTo(e.attempts));
      }
    }
  });

  test('device tier from benchmark (PRD 9.1)', () {
    expect(DeviceTierX.fromBenchmark(10), DeviceTier.lite);
    expect(DeviceTierX.fromBenchmark(3), DeviceTier.standard);
    expect(DeviceTierX.fromBenchmark(0.5), DeviceTier.high);
    expect(DeviceTier.lite.fps, 10);
    expect(DeviceTier.standard.fps, 15);
    expect(DeviceTier.lite.animatedDemos, isFalse);
  });
}
