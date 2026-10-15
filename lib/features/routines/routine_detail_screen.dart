import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/routine.dart';
import '../../state/app_state.dart';
import '../../widgets/exercise_row.dart';
import '../exercises/exercise_detail_screen.dart';
import '../premium/premium_screen.dart';
import 'routine_editor_screen.dart';

/// Routine detail (FR-RT-03): muscle chips, ordered list, estimated time,
/// Save, Edit and Start.
class RoutineDetailScreen extends ConsumerWidget {
  final Routine routine;
  const RoutineDetailScreen({super.key, required this.routine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final cat = app.catalog;
    final r = app.routineById(routine.id) ?? routine;
    final dist = RoutineMath.distribution(r.items, cat);
    final isMine = app.myRoutines.any((x) => x.id == r.id);
    return Scaffold(
      appBar: AppBar(title: Text(r.name), actions: [
        IconButton(
          tooltip: 'Edit',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RoutineEditorScreen(initial: isMine ? r : r.copyWith(id: 'user_${DateTime.now().microsecondsSinceEpoch}', source: 'user')))),
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          tooltip: isMine ? 'Saved' : 'Save',
          onPressed: isMine ? null : () => app.saveRoutine(r.copyWith(source: 'user')),
          icon: Icon(isMine ? Icons.bookmark : Icons.bookmark_border),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
        Text('~${RoutineMath.estimatedMinutes(r.items, cat)} min · ${r.items.length} exercises',
            style: const TextStyle(color: FF.muted)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: dist.take(6).map((m) => MusclePercent(muscle: m.key, percent: m.value)).toList()),
        ),
        const Divider(height: 28),
        for (var i = 0; i < r.items.length; i++)
          if (cat.byId(r.items[i].exerciseId) != null)
            ExerciseRow(
              def: cat.byId(r.items[i].exerciseId)!,
              subtitle: '${i + 1}. ${cat.byId(r.items[i].exerciseId)!.isTimed ? '${r.items[i].sets} x ${r.items[i].seconds}s' : '${r.items[i].sets} x ${r.items[i].reps} reps'}',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ExerciseDetailScreen(def: cat.byId(r.items[i].exerciseId)!))),
            ),
      ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: MediaQuery.of(context).size.width - 32,
        height: 56,
        child: FilledButton.icon(
          onPressed: r.items.isEmpty
              ? null
              : () => startWorkout(context, ref, r),
          icon: const Icon(Icons.bolt),
          label: const Text('Start guided workout'),
        ),
      ),
    );
  }
}
