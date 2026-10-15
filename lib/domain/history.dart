import 'tracking_session.dart';

/// One exercise inside a finished workout (session_exercise in PRD 8.7).
class SessionExercise {
  final String exerciseId;
  final int sets;
  final int attempts;
  final int cleanReps;
  final int seconds;
  final double avgForm;
  final double? bestPeak;
  final String view;
  final List<RepResult> reps;

  const SessionExercise({
    required this.exerciseId,
    required this.sets,
    required this.attempts,
    required this.cleanReps,
    this.seconds = 0,
    required this.avgForm,
    this.bestPeak,
    this.view = 'side',
    this.reps = const [],
  });

  Map<String, dynamic> toJson() => {
        'ex': exerciseId,
        'sets': sets,
        'attempts': attempts,
        'clean': cleanReps,
        'seconds': seconds,
        'avgForm': double.parse(avgForm.toStringAsFixed(1)),
        'best': bestPeak,
        'view': view,
        'reps': reps.map((r) => r.toJson()).toList(),
      };

  factory SessionExercise.fromJson(Map<String, dynamic> j) => SessionExercise(
        exerciseId: j['ex'] as String,
        sets: (j['sets'] as num?)?.toInt() ?? 1,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        cleanReps: (j['clean'] as num?)?.toInt() ?? 0,
        seconds: (j['seconds'] as num?)?.toInt() ?? 0,
        avgForm: (j['avgForm'] as num?)?.toDouble() ?? 0,
        bestPeak: (j['best'] as num?)?.toDouble(),
        view: (j['view'] as String?) ?? 'side',
        reps: ((j['reps'] as List?) ?? const [])
            .map((r) => RepResult.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}

class WorkoutSession {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final String routineName;
  final List<SessionExercise> exercises;
  final bool synced;

  const WorkoutSession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.routineName,
    required this.exercises,
    this.synced = false,
  });

  Duration get duration => endedAt.difference(startedAt);
  int get cleanReps => exercises.fold(0, (a, e) => a + e.cleanReps);
  int get attempts => exercises.fold(0, (a, e) => a + e.attempts);

  double get avgForm {
    final scored = exercises.where((e) => e.attempts > 0).toList();
    if (scored.isEmpty) return 0;
    return scored.map((e) => e.avgForm).reduce((a, b) => a + b) / scored.length;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': startedAt.toIso8601String(),
        'end': endedAt.toIso8601String(),
        'routine': routineName,
        'synced': synced,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  /// Malformed records return null instead of throwing (NFR-RL-02).
  static WorkoutSession? tryParse(dynamic j) {
    try {
      final m = j as Map<String, dynamic>;
      return WorkoutSession(
        id: m['id'] as String,
        startedAt: DateTime.parse(m['start'] as String),
        endedAt: DateTime.parse(m['end'] as String),
        routineName: (m['routine'] as String?) ?? 'Workout',
        synced: (m['synced'] as bool?) ?? false,
        exercises: (m['exercises'] as List)
            .map((e) => SessionExercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

DateTime startOfWeek(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday % 7)); // Sunday start
}

/// Weekly calendar and streak (FR-PG-02).
class ProgressStats {
  static Set<int> completedWeekdays(List<WorkoutSession> s, DateTime now) {
    final start = startOfWeek(now);
    final end = start.add(const Duration(days: 7));
    return s
        .where((w) => !w.startedAt.isBefore(start) && w.startedAt.isBefore(end))
        .map((w) => w.startedAt.weekday % 7)
        .toSet();
  }

  static int workoutsThisWeek(List<WorkoutSession> s, DateTime now) {
    final start = startOfWeek(now);
    return s.where((w) => !w.startedAt.isBefore(start)).length;
  }

  /// Consecutive weeks (ending this week or last week) that met the target.
  static int streakWeeks(List<WorkoutSession> s, DateTime now, int target) {
    var week = startOfWeek(now);
    var streak = 0;
    int countIn(DateTime ws) {
      final we = ws.add(const Duration(days: 7));
      return s.where((w) => !w.startedAt.isBefore(ws) && w.startedAt.isBefore(we)).length;
    }

    if (countIn(week) < target) week = week.subtract(const Duration(days: 7));
    while (countIn(week) >= target && streak < 520) {
      streak++;
      week = week.subtract(const Duration(days: 7));
    }
    return streak;
  }
}
