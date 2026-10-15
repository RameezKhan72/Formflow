import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/guided_workout.dart';
import '../../domain/history.dart';
import '../../domain/insights.dart';
import '../../domain/routine.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/exercise_row.dart';
import '../../domain/exercise.dart';
import '../../widgets/muscle_map.dart';
import '../exercises/exercise_detail_screen.dart';
import '../exercises/exercises_tab.dart';
import '../shell/home_shell.dart';
import '../premium/premium_screen.dart';
import '../tracking/workout_run_screen.dart';

/// Workout home (PRD 3.2a): active plan, Coach strip, "Your next workout"
/// with muscle distribution and a pinned Start button.
class WorkoutTab extends ConsumerWidget {
  const WorkoutTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final cat = app.catalog;
    final now = appClock();
    final today = app.todaysRoutine(now);
    final routine = today ?? app.nextRoutine(now);
    final dist = {for (final e in RoutineMath.distribution(routine.items, cat)) e.key: e.value};
    final insights = Coach.insights(sessions: app.data.history, profile: app.profile, catalog: cat, now: now);
    final done = ProgressStats.workoutsThisWeek(app.data.history, now);
    final planName = app.data.activeRoutineId == 'weekly'
        ? '${app.profile.name.split(' ').first} Weekly Plan'
        : (app.routineById(app.data.activeRoutineId)?.name ?? 'Plan');
    final resume = GuidedWorkout.fromJson(app.data.resumeState);

    return Stack(children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          if (resume != null) ...[
            Card(
              color: FF.accentSoft,
              child: ListTile(
                leading: const Icon(Icons.play_circle_fill, color: FF.accent, size: 36),
                title: Text('Resume ${resume.routineName}'),
                subtitle: Text(resume.label),
                trailing: TextButton(onPressed: () => app.saveResume(null), child: const Text('Discard')),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutRunScreen.resume(resume))),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                ProgressRing(
                  value: done / app.profile.weeklyTarget,
                  size: 54,
                  child: Text('$done/${app.profile.weeklyTarget}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, fontFeatures: FF.tabular)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Active plan', style: TextStyle(color: FF.muted)),
                    Text(planName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text('Today ${DayPlan.clock(app.profile.slotMinutes)}',
                        style: const TextStyle(color: FF.muted, fontSize: 12)),
                  ]),
                ),
                OutlinedButton.icon(
                  key: const Key('plans_button'),
                  onPressed: () => _plans(context, ref),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Plans'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          CoachStrip(insights: insights),
          const SizedBox(height: 14),
          const Text('Train by muscle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const MuscleSectionGrid(),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.skip_next_rounded),
            const SizedBox(width: 6),
            Expanded(
              child: Text(today == null ? 'Rest day · Your next workout' : 'Your next workout',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(routine.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                  Text('~${RoutineMath.estimatedMinutes(routine.items, cat)} min', style: const TextStyle(color: FF.muted)),
                ]),
                const Divider(height: 20),
                ...routine.items.map((it) {
                  final e = cat.byId(it.exerciseId);
                  if (e == null) return const SizedBox.shrink();
                  final m = e.primaryMuscle;
                  return ExerciseRow(
                    def: e,
                    subtitle: e.isTimed ? '${it.sets} sets x ${it.seconds}s' : '${it.sets} sets x ${it.reps} reps',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExerciseDetailScreen(def: e))),
                    trailing: MusclePercent(muscle: m, percent: dist[m] ?? 0),
                  );
                }),
              ]),
            ),
          ),
        ],
      ),
      Positioned(
        left: 16,
        right: 16,
        bottom: 16,
        child: SizedBox(
          height: 58,
          child: FilledButton.icon(
            key: const Key('start_workout'),
            onPressed: () => startWorkout(context, ref, routine),
            icon: const Icon(Icons.bolt, size: 28),
            label: const Text('Start', style: TextStyle(fontSize: 20)),
          ),
        ),
      ),
    ]);
  }

  void _plans(BuildContext context, WidgetRef ref) {
    final app = ref.read(appProvider);
    final options = [
      ('weekly', 'Weekly schedule'),
      ...[...app.myRoutines, ...RoutinePresets.all(app.catalog).take(6)].map((r) => (r.id, r.name)),
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Choose your plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final o in {for (final o in options) o.$1: o}.values)
              ListTile(
                title: Text(o.$2),
                trailing: app.data.activeRoutineId == o.$1 ? const Icon(Icons.check, color: FF.accent) : null,
                onTap: () {
                  app.setActivePlan(o.$1);
                  Navigator.pop(c);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Eight body-part shortcuts on the home screen; each opens its library
/// section (doc item 8: separate sections per muscle).
class MuscleSectionGrid extends ConsumerWidget {
  const MuscleSectionGrid({super.key});

  static const _muscle = {
    'chest': 'chest',
    'back': 'lats',
    'shoulders': 'shoulders',
    'arms': 'biceps',
    'abs': 'abs',
    'legs': 'quads',
    'glutes': 'glutes',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(appProvider).catalog;
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.78,
      children: [
        for (final g in ExerciseCatalog.groups)
          Material(
            key: Key('muscle_tile_$g'),
            color: FF.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                ref.read(libraryGroupProvider.notifier).state = g;
                ref.read(tabIndexProvider.notifier).state = 1;
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  Expanded(
                    child: _muscle[g] == null
                        ? Container(
                            decoration: BoxDecoration(color: FF.accentSoft, borderRadius: BorderRadius.circular(12)),
                            child: const Center(child: Icon(Icons.directions_run, color: FF.accent, size: 30)),
                          )
                        : LayoutBuilder(
                            builder: (context, c) => MuscleChip(muscle: _muscle[g]!, size: c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Text(ExerciseCatalog.groupLabel(g).split(' ').first,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  Text('${cat.inGroup(g).length}', style: const TextStyle(fontSize: 11, color: FF.muted)),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}
