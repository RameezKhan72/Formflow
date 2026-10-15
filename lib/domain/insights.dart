import 'dart:math' as math;

import 'exercise.dart';
import 'history.dart';
import 'profile.dart';
import 'routine.dart';

/// Per-muscle recovery estimate (FR-PG-03). About 25 % right after a hard
/// session, rising linearly to 100 % over 48 hours, scaled by work done.
/// This is an estimate, not a measurement.
class RecoveryModel {
  static const double windowHours = 48;
  static const double maxDrop = 75;

  /// Reference load (weighted sets) that produces the full drop.
  static const double referenceLoad = 6;

  static Map<String, double> estimate(List<WorkoutSession> sessions, ExerciseCatalog cat, DateTime now) {
    final drop = {for (final m in MuscleIds.all) m: 0.0};
    for (final s in sessions) {
      final hours = now.difference(s.endedAt).inMinutes / 60.0;
      if (hours < 0 || hours >= windowHours) continue;
      final remaining = 1 - hours / windowHours;
      final load = <String, double>{};
      for (final se in s.exercises) {
        final e = cat.byId(se.exerciseId);
        if (e == null) continue;
        final intensity = 0.6 + 0.4 * (e.level / 5);
        final work = se.sets * intensity * (se.attempts > 0 ? 1.0 : 0.5);
        e.normalisedMuscles.forEach((m, w) => load[m] = (load[m] ?? 0) + w * work);
      }
      load.forEach((m, l) {
        final d = maxDrop * math.min(1.0, l / referenceLoad) * remaining;
        drop[m] = (drop[m] ?? 0) + d;
      });
    }
    return drop.map((m, d) => MapEntry(m, (100 - math.min(maxDrop, d)).clamp(0, 100).toDouble()));
  }

  /// "Fresh muscle workout": exercises whose main muscles are recovered.
  static Routine freshRoutine(Map<String, double> recovery, ExerciseCatalog cat, {double threshold = 90}) {
    final fresh = recovery.entries.where((e) => e.value >= threshold).map((e) => e.key).toSet();
    final picks = <RoutineItem>[];
    final used = <String>{};
    final sorted = [...cat.exercises]..sort((a, b) => a.level.compareTo(b.level));
    for (final e in sorted) {
      final main = e.normalisedMuscles.entries.where((m) => m.value >= 0.25).map((m) => m.key);
      if (main.isEmpty || !main.every(fresh.contains)) continue;
      if (used.contains(e.primaryMuscle)) continue;
      used.add(e.primaryMuscle);
      picks.add(RoutineItem.defaults(e));
      if (picks.length >= 5) break;
    }
    return Routine(id: 'fresh_${DateTime.now().millisecondsSinceEpoch}', name: 'Fresh Muscle Workout', source: 'generated', items: picks);
  }
}

/// Rule-based coach (FR-CO-01..03). Runs on the device; never gives
/// medical advice.
class Coach {
  static String sideIssueLabel(String key, ExerciseCatalog cat) {
    final parts = key.split(':');
    final cue = cat.cues[parts.first] ?? parts.first;
    final text = cue.split('|').last;
    return parts.length > 1 ? '${parts[1]} side: $text' : text;
  }

  static List<String> insights({
    required List<WorkoutSession> sessions,
    required UserProfile profile,
    required ExerciseCatalog catalog,
    required DateTime now,
  }) {
    final out = <String>[];
    final weekStart = startOfWeek(now);
    final week = sessions.where((s) => !s.startedAt.isBefore(weekStart)).toList();
    out.add('${week.length} of ${profile.weeklyTarget} workouts done this week');

    // Most frequent issue this week, per exercise, with side when known.
    final issueCount = <String, int>{};
    final repsPerEx = <String, int>{};
    for (final s in week) {
      for (final e in s.exercises) {
        repsPerEx[e.exerciseId] = (repsPerEx[e.exerciseId] ?? 0) + e.reps.length;
        for (final r in e.reps) {
          for (final i in r.issues.toSet()) {
            final k = '${e.exerciseId}|$i';
            issueCount[k] = (issueCount[k] ?? 0) + 1;
          }
        }
      }
    }
    if (issueCount.isNotEmpty) {
      final top = issueCount.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final exId = top.key.split('|').first;
      final issue = top.key.split('|').last;
      final total = repsPerEx[exId] ?? 0;
      final ex = catalog.byId(exId);
      if (total > 0 && ex != null) {
        final pct = (top.value / total * 100).round();
        final parts = issue.split(':');
        final side = parts.length > 1 ? '${parts[1][0].toUpperCase()}${parts[1].substring(1)} side: ' : '';
        final cueText = (catalog.cues[parts.first] ?? parts.first).split('|').last;
        out.add('$side"$cueText" on $pct% of ${ex.name.toLowerCase()} reps this week');
      }
    }

    // Form trend vs last week.
    final lastStart = weekStart.subtract(const Duration(days: 7));
    final last = sessions.where((s) => !s.startedAt.isBefore(lastStart) && s.startedAt.isBefore(weekStart)).toList();
    double avg(List<WorkoutSession> l) =>
        l.isEmpty ? 0 : l.map((s) => s.avgForm).reduce((a, b) => a + b) / l.length;
    if (week.isNotEmpty && last.isNotEmpty) {
      final diff = avg(week) - avg(last);
      if (diff.abs() >= 3) {
        out.add(diff > 0
            ? 'Average form is up ${diff.round()} points on last week'
            : 'Average form is down ${diff.abs().round()} points; slow the tempo down');
      } else {
        out.add('Average form is steady at ${avg(week).round()}%');
      }
    } else if (sessions.isEmpty) {
      out.add('Start your first workout to unlock form insights');
    }
    return out.take(3).toList();
  }
}

/// Accuracy Test Lab (FR-TL). Positive class = "bad form".
class LabLabel {
  final String exerciseId;
  final bool appSaidGood;
  final bool appWasRight;
  final DateTime time;
  const LabLabel(this.exerciseId, this.appSaidGood, this.appWasRight, this.time);

  bool get truthGood => appWasRight ? appSaidGood : !appSaidGood;

  Map<String, dynamic> toJson() => {'ex': exerciseId, 'good': appSaidGood, 'right': appWasRight, 't': time.toIso8601String()};
  static LabLabel? tryParse(dynamic j) {
    try {
      final m = j as Map<String, dynamic>;
      return LabLabel(m['ex'] as String, m['good'] as bool, m['right'] as bool, DateTime.parse(m['t'] as String));
    } catch (_) {
      return null;
    }
  }
}

class LabMetrics {
  final int tp, tn, fp, fn;
  const LabMetrics(this.tp, this.tn, this.fp, this.fn);

  int get n => tp + tn + fp + fn;
  double get accuracy => n == 0 ? 0 : (tp + tn) / n;
  double get precision => tp + fp == 0 ? 0 : tp / (tp + fp);
  double get recall => tp + fn == 0 ? 0 : tp / (tp + fn);
  double get f1 => precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall);
  double get falseAlarmRate => fp + tn == 0 ? 0 : fp / (fp + tn);

  static LabMetrics of(Iterable<LabLabel> labels) {
    var tp = 0, tn = 0, fp = 0, fn = 0;
    for (final l in labels) {
      final appBad = !l.appSaidGood;
      final truthBad = !l.truthGood;
      if (appBad && truthBad) {
        tp++;
      } else if (!appBad && !truthBad) {
        tn++;
      } else if (appBad && !truthBad) {
        fp++;
      } else {
        fn++;
      }
    }
    return LabMetrics(tp, tn, fp, fn);
  }

  static double repCountError(int counted, int actual) => actual == 0 ? 0 : (counted - actual).abs() / actual;

  /// CSV columns: exercise, app_verdict, app_was_right, time (FR-TL-03).
  static String csv(Iterable<LabLabel> labels) {
    final b = StringBuffer('exercise,app_verdict,app_was_right,time\n');
    for (final l in labels) {
      b.writeln('${l.exerciseId},${l.appSaidGood ? 'good' : 'bad'},${l.appWasRight},${l.time.toIso8601String()}');
    }
    return b.toString();
  }
}

/// Daily timeline around the chosen workout time (FR-TP-01).
class DayPlan {
  static List<({int minutes, String title, String detail})> timeline(int workoutMinutes) {
    int t(int m) => ((m % 1440) + 1440) % 1440;
    return [
      (minutes: t(workoutMinutes - 90), title: 'Pre-workout meal', detail: 'Carbs plus a little protein'),
      (minutes: t(workoutMinutes - 15), title: 'Hydrate and warm up', detail: '10-minute warm-up, a glass of water'),
      (minutes: t(workoutMinutes), title: 'Workout', detail: '35 to 40 minutes'),
      (minutes: t(workoutMinutes + 45), title: 'Cool-down', detail: 'Stretch for 5 to 10 minutes'),
      (minutes: t(workoutMinutes + 60), title: 'Post-workout meal', detail: 'Protein and carbs to recover'),
    ];
  }

  static String clock(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }
}

/// Body Profile scan maths (FR-CB-03). Ratios relative to torso length.
class BodyProfileResult {
  final Map<String, double> ratios;
  final double symmetry; // 0..100
  final int quality; // 0..100
  final List<String> problems;
  const BodyProfileResult(this.ratios, this.symmetry, this.quality, this.problems);

  Map<String, dynamic> toJson() => {'ratios': ratios, 'symmetry': symmetry, 'quality': quality};
}

/// Device tier from a short CPU benchmark (PRD 9.1).
enum DeviceTier { lite, standard, high }

extension DeviceTierX on DeviceTier {
  String get label => name[0].toUpperCase() + name.substring(1);
  int get fps => this == DeviceTier.lite ? 10 : (this == DeviceTier.standard ? 15 : 24);
  bool get animatedDemos => this != DeviceTier.lite;

  static DeviceTier fromBenchmark(double msPerFrame) {
    if (msPerFrame > 6) return DeviceTier.lite;
    if (msPerFrame > 2) return DeviceTier.standard;
    return DeviceTier.high;
  }
}
