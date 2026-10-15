import 'history.dart';
import 'routine.dart';
import 'tracking_session.dart';

/// Guided workout state (FR-GW-01..10): "Exercise i of n, Set s of S",
/// rests of 45 s between sets and 60 s between exercises, skip, partial
/// results, resume after interruption.
class GuidedWorkout {
  final String routineName;
  final List<RoutineItem> items;
  final DateTime startedAt;
  int index;
  int set; // 1-based
  final Map<String, _Acc> _acc;

  static const restBetweenSets = 45;
  static const restBetweenExercises = 60;

  GuidedWorkout({required this.routineName, required this.items, required this.startedAt, this.index = 0, this.set = 1})
      : _acc = {};

  RoutineItem get current => items[index];
  bool get isLastSet => set >= current.sets;
  bool get isLastExercise => index >= items.length - 1;
  bool get finished => index >= items.length;
  RoutineItem? get next => isLastSet ? (isLastExercise ? null : items[index + 1]) : current;

  String get label => 'Exercise ${index + 1} of ${items.length}, Set $set of ${current.sets}';

  /// Records a finished set and returns the rest duration (0 = workout done).
  int completeSet({required int attempts, required int clean, required List<RepResult> reps, int seconds = 0, String view = 'side'}) {
    final id = current.exerciseId;
    final a = _acc.putIfAbsent(id, () => _Acc());
    a.sets++;
    a.attempts += attempts;
    a.clean += clean;
    a.seconds += seconds;
    a.view = view;
    a.reps.addAll(reps);
    if (isLastSet) {
      if (isLastExercise) {
        index = items.length;
        return 0;
      }
      index++;
      set = 1;
      return restBetweenExercises;
    }
    set++;
    return restBetweenSets;
  }

  /// Skip the rest of the current exercise (FR-GW-10).
  void skipExercise() {
    index++;
    set = 1;
  }

  /// Move an upcoming exercise (FR-GW-10). Only items after the current one.
  void reorder(int from, int to) {
    if (from <= index || to <= index || from >= items.length || to >= items.length) return;
    final it = items.removeAt(from);
    items.insert(to, it);
  }

  WorkoutSession toSession(DateTime end) {
    final exercises = <SessionExercise>[];
    for (final it in items) {
      final a = _acc[it.exerciseId];
      if (a == null) continue;
      final avg = a.reps.isEmpty ? 0.0 : a.reps.map((r) => r.score).reduce((x, y) => x + y) / a.reps.length;
      exercises.add(SessionExercise(
        exerciseId: it.exerciseId,
        sets: a.sets,
        attempts: a.attempts,
        cleanReps: a.clean,
        seconds: a.seconds,
        avgForm: avg,
        view: a.view,
        reps: List.of(a.reps),
      ));
    }
    return WorkoutSession(
      id: 'w_${startedAt.millisecondsSinceEpoch}',
      startedAt: startedAt,
      endedAt: end,
      routineName: routineName,
      exercises: exercises,
    );
  }

  Map<String, dynamic> toJson() => {
        'routine': routineName,
        'items': items.map((i) => i.toJson()).toList(),
        'start': startedAt.toIso8601String(),
        'index': index,
        'set': set,
        'acc': _acc.map((k, v) => MapEntry(k, v.toJson())),
      };

  static GuidedWorkout? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    try {
      final g = GuidedWorkout(
        routineName: j['routine'] as String,
        items: (j['items'] as List).map((e) => RoutineItem.fromJson(e as Map<String, dynamic>)).toList(),
        startedAt: DateTime.parse(j['start'] as String),
        index: (j['index'] as num).toInt(),
        set: (j['set'] as num).toInt(),
      );
      ((j['acc'] as Map<String, dynamic>?) ?? const {}).forEach((k, v) => g._acc[k] = _Acc.fromJson(v as Map<String, dynamic>));
      if (g.index >= g.items.length) return null;
      return g;
    } catch (_) {
      return null;
    }
  }
}

class _Acc {
  int sets = 0, attempts = 0, clean = 0, seconds = 0;
  String view = 'side';
  final List<RepResult> reps = [];

  Map<String, dynamic> toJson() => {
        'sets': sets,
        'attempts': attempts,
        'clean': clean,
        'seconds': seconds,
        'view': view,
        'reps': reps.map((r) => r.toJson()).toList(),
      };

  static _Acc fromJson(Map<String, dynamic> j) => _Acc()
    ..sets = (j['sets'] as num?)?.toInt() ?? 0
    ..attempts = (j['attempts'] as num?)?.toInt() ?? 0
    ..clean = (j['clean'] as num?)?.toInt() ?? 0
    ..seconds = (j['seconds'] as num?)?.toInt() ?? 0
    ..view = (j['view'] as String?) ?? 'side'
    ..reps.addAll(((j['reps'] as List?) ?? const []).map((r) => RepResult.fromJson(r as Map<String, dynamic>)));
}
