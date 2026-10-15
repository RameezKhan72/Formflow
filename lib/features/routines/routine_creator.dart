import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/exercise.dart';
import '../../domain/profile.dart';
import '../../domain/routine.dart';
import '../../state/app_state.dart';
import 'routine_detail_screen.dart';

/// Rule-based Routine Creator (FR-RT-05): goal, level, equipment, time and
/// target muscles; no network.
Future<void> showRoutineCreator(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => const _CreatorSheet(),
  );
}

class _CreatorSheet extends ConsumerStatefulWidget {
  const _CreatorSheet();

  @override
  ConsumerState<_CreatorSheet> createState() => _CreatorSheetState();
}

class _CreatorSheetState extends ConsumerState<_CreatorSheet> {
  late Goal _goal = ref.read(appProvider).profile.goal;
  int _level = 3;
  final Set<String> _equipment = {'dumbbells'};
  double _minutes = 30;
  final Set<String> _targets = {};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, sc) => ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
        const Text('Routine Creator', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const Text('Built on your phone from simple training rules.', style: TextStyle(color: FF.muted)),
        const SizedBox(height: 16),
        const Text('Goal'),
        Wrap(spacing: 8, children: [
          for (final g in Goal.values) ChoiceChip(label: Text(g.label), selected: _goal == g, onSelected: (_) => setState(() => _goal = g)),
        ]),
        const SizedBox(height: 12),
        Text('Max level: $_level'),
        Slider(value: _level.toDouble(), min: 1, max: 5, divisions: 4, onChanged: (v) => setState(() => _level = v.round())),
        const Text('Equipment you have'),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in ExerciseCatalog.equipmentTypes.where((e) => e != 'bodyweight'))
            FilterChip(
              label: Text(e),
              selected: _equipment.contains(e),
              onSelected: (v) => setState(() => v ? _equipment.add(e) : _equipment.remove(e)),
            ),
        ]),
        const SizedBox(height: 12),
        Text('Time available: ${_minutes.round()} min'),
        Slider(value: _minutes, min: 10, max: 60, divisions: 10, onChanged: (v) => setState(() => _minutes = v)),
        const Text('Target muscles (optional)'),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final m in MuscleIds.all)
            FilterChip(
              label: Text(MuscleIds.label(m)),
              selected: _targets.contains(m),
              onSelected: (v) => setState(() => v ? _targets.add(m) : _targets.remove(m)),
            ),
        ]),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () {
            final app = ref.read(appProvider);
            final r = RoutineGenerator.generate(
              catalog: app.catalog,
              goal: _goal,
              maxLevel: _level,
              equipment: _equipment,
              minutes: _minutes.round(),
              targetMuscles: _targets,
              name: _targets.isEmpty ? 'Generated ${_goal.label}' : 'Generated ${_targets.map(MuscleIds.label).take(2).join(' & ')}',
            );
            if (r.items.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No exercises fit. Try more equipment or a higher level.')));
              return;
            }
            app.saveRoutine(r);
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(MaterialPageRoute(builder: (_) => RoutineDetailScreen(routine: r)));
          },
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Create routine'),
        ),
      ]),
    );
  }
}
