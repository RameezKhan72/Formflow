import 'dart:math' as math;

import 'exercise.dart';
import 'profile.dart';

class RoutineItem {
  final String exerciseId;
  final int sets;
  final int reps;
  final int seconds;
  const RoutineItem(this.exerciseId, {this.sets = 3, this.reps = 10, this.seconds = 30});

  RoutineItem copyWith({int? sets, int? reps, int? seconds}) =>
      RoutineItem(exerciseId, sets: sets ?? this.sets, reps: reps ?? this.reps, seconds: seconds ?? this.seconds);

  Map<String, dynamic> toJson() => {'ex': exerciseId, 'sets': sets, 'reps': reps, 'seconds': seconds};
  factory RoutineItem.fromJson(Map<String, dynamic> j) => RoutineItem(
        j['ex'] as String,
        sets: (j['sets'] as num?)?.toInt() ?? 3,
        reps: (j['reps'] as num?)?.toInt() ?? 10,
        seconds: (j['seconds'] as num?)?.toInt() ?? 30,
      );

  static RoutineItem defaults(ExerciseDef e) => RoutineItem(e.id, sets: e.sets, reps: e.reps, seconds: e.seconds);
}

class Routine {
  final String id;
  final String name;
  final String source; // preset | user | generated
  final String emoji;
  final List<RoutineItem> items;
  const Routine({required this.id, required this.name, this.source = 'user', this.emoji = '', required this.items});

  Routine copyWith({String? id, String? name, String? source, List<RoutineItem>? items}) => Routine(
        id: id ?? this.id,
        name: name ?? this.name,
        source: source ?? this.source,
        emoji: emoji,
        items: items ?? this.items,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'source': source,
        'emoji': emoji,
        'items': items.map((i) => i.toJson()).toList(),
      };

  static Routine? tryParse(dynamic j) {
    try {
      final m = j as Map<String, dynamic>;
      return Routine(
        id: m['id'] as String,
        name: m['name'] as String,
        source: (m['source'] as String?) ?? 'user',
        emoji: (m['emoji'] as String?) ?? '',
        items: (m['items'] as List).map((i) => RoutineItem.fromJson(i as Map<String, dynamic>)).toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

class RoutineMath {
  /// Muscle distribution percentages from exercise muscle weights and
  /// volume (FR-RT-07). Returns muscle -> percent (0..100), sorted desc.
  static List<MapEntry<String, double>> distribution(Iterable<RoutineItem> items, ExerciseCatalog cat) {
    final totals = <String, double>{};
    for (final it in items) {
      final e = cat.byId(it.exerciseId);
      if (e == null) continue;
      final volume = it.sets.toDouble();
      e.normalisedMuscles.forEach((m, w) => totals[m] = (totals[m] ?? 0) + w * volume);
    }
    final sum = totals.values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return [];
    final out = totals.entries.map((e) => MapEntry(e.key, e.value / sum * 100)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return out;
  }

  /// Share of one exercise's own muscles (used in workout rows).
  static List<MapEntry<String, double>> exerciseShare(ExerciseDef e) {
    final out = e.normalisedMuscles.entries.map((m) => MapEntry(m.key, m.value * 100)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return out;
  }

  /// Estimated minutes: ~3 s per rep, rests of 45 s / 60 s, 30 s setup.
  static int estimatedMinutes(List<RoutineItem> items, ExerciseCatalog cat) {
    var s = 0.0;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final e = cat.byId(it.exerciseId);
      final work = (e?.isTimed ?? false) ? it.seconds.toDouble() : it.reps * 3.0;
      s += 30 + it.sets * work + (it.sets - 1) * 45 + (i < items.length - 1 ? 60 : 0);
    }
    return math.max(1, (s / 60).round());
  }

  static Set<String> muscles(Iterable<RoutineItem> items, ExerciseCatalog cat) =>
      distribution(items, cat).where((e) => e.value >= 8).map((e) => e.key).toSet();

  static int level(Iterable<RoutineItem> items, ExerciseCatalog cat) {
    final ls = items.map((i) => cat.byId(i.exerciseId)?.level ?? 1).toList();
    if (ls.isEmpty) return 1;
    return (ls.reduce((a, b) => a + b) / ls.length).round();
  }

  static Set<String> equipment(Iterable<RoutineItem> items, ExerciseCatalog cat) =>
      items.expand((i) => cat.byId(i.exerciseId)?.equipment.take(1) ?? const <String>[]).toSet();
}

/// Preset routines (FR-RT-02).
class RoutinePresets {
  static Routine _r(String id, String name, String emoji, List<String> ex, ExerciseCatalog c) => Routine(
        id: 'preset_$id',
        name: name,
        source: 'preset',
        emoji: emoji,
        items: ex.where((e) => c.byId(e) != null).map((e) => RoutineItem.defaults(c.byId(e)!)).toList(),
      );

  static List<Routine> all(ExerciseCatalog c) => [
        _r('full_body', 'Full Body', '', ['squat', 'push_up', 'bent_over_row', 'shoulder_press', 'bicep_curl', 'plank'], c),
        _r('beginner', 'Beginner Full Body', '', ['squat', 'glute_bridge', 'push_up', 'bicep_curl', 'sit_up', 'plank'], c),
        _r('push', 'Push Day', '', ['push_up', 'wide_push_up', 'shoulder_press', 'lateral_raise', 'overhead_triceps', 'bench_dip'], c),
        _r('pull', 'Pull Day', '', ['pull_up', 'bent_over_row', 'deadlift', 'bicep_curl', 'hammer_curl'], c),
        _r('legs_day', 'Leg Day', '', ['squat', 'lunge', 'glute_bridge', 'wall_sit', 'calf_raise'], c),
        _r('core', 'Core Crusher', '', ['sit_up', 'plank', 'glute_bridge', 'good_morning'], c),
        _r('legs', 'Legs', '', ['squat', 'lunge', 'glute_bridge', 'calf_raise', 'wall_sit'], c),
        _r('back', 'Back', '', ['deadlift', 'bent_over_row', 'pull_up', 'good_morning'], c),
        _r('chest', 'Chest', '', ['push_up', 'wide_push_up', 'diamond_push_up'], c),
        _r('arms', 'Arms', '', ['bicep_curl', 'hammer_curl', 'overhead_triceps', 'bench_dip', 'diamond_push_up'], c),
        _r('shoulders', 'Shoulders', '', ['shoulder_press', 'lateral_raise', 'push_up'], c),
        _r('abs', 'Abs', '', ['sit_up', 'plank'], c),
        _r('legs_core', 'Legs & Core', '', ['squat', 'lunge', 'glute_bridge', 'sit_up', 'plank'], c),
        _r('upper_core', 'Upper Body & Core', '', ['push_up', 'bent_over_row', 'shoulder_press', 'bicep_curl', 'overhead_triceps', 'plank'], c),
        _r('cardio_core', 'Cardio & Core', '', ['squat', 'lunge', 'calf_raise', 'sit_up', 'plank'], c),
      ];

  /// Weekly schedule Sunday..Saturday (FR-TP-02). null = rest day.
  static const weekly = <String?>[
    null, // Sun: rest or walk
    'preset_full_body', // Mon
    'preset_legs_core', // Tue
    null, // Wed: rest or stretching
    'preset_upper_core', // Thu
    'preset_full_body', // Fri
    'preset_cardio_core', // Sat
  ];

  static const weeklyLabels = [
    'Rest or walk', 'Full Body', 'Legs and Core', 'Rest or stretching',
    'Upper Body and Core', 'Full Body', 'Cardio and Core',
  ];
}

/// Rule-based Routine Creator (FR-RT-05), fully offline.
class RoutineGenerator {
  static Routine generate({
    required ExerciseCatalog catalog,
    required Goal goal,
    required int maxLevel,
    required Set<String> equipment,
    required int minutes,
    required Set<String> targetMuscles,
    String name = 'My Generated Routine',
  }) {
    final usable = catalog.exercises.where((e) {
      if (e.level > maxLevel) return false;
      return e.equipment.any((q) => q == 'bodyweight' || equipment.contains(q));
    }).toList();
    double score(ExerciseDef e) {
      if (targetMuscles.isEmpty) return e.level.toDouble() * 0.1 + e.muscles.length * 0.2;
      return e.normalisedMuscles.entries.where((m) => targetMuscles.contains(m.key)).fold(0.0, (a, m) => a + m.value);
    }

    usable.sort((a, b) => score(b).compareTo(score(a)));
    final sets = goal.nutritionGoal == Goal.bulking ? 4 : 3;
    final reps = goal.nutritionGoal == Goal.cutting ? 15 : (goal.nutritionGoal == Goal.bulking ? 8 : 12);
    final items = <RoutineItem>[];
    final usedPrimary = <String, int>{};
    for (final e in usable) {
      if (targetMuscles.isNotEmpty && score(e) < 0.2) continue;
      final p = e.primaryMuscle;
      if ((usedPrimary[p] ?? 0) >= 2) continue;
      final candidate = [...items, RoutineItem(e.id, sets: sets, reps: e.isTimed ? 0 : reps, seconds: e.seconds)];
      if (RoutineMath.estimatedMinutes(candidate, catalog) > minutes && items.isNotEmpty) break;
      items.add(candidate.last);
      usedPrimary[p] = (usedPrimary[p] ?? 0) + 1;
      if (items.length >= 8) break;
    }
    return Routine(id: 'gen_${DateTime.now().millisecondsSinceEpoch}', name: name, source: 'generated', items: items);
  }
}
