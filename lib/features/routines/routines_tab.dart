import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/exercise.dart';
import '../../domain/routine.dart';
import '../../state/app_state.dart';
import '../../widgets/mannequin.dart';
import '../../widgets/muscle_map.dart';
import '../premium/premium_screen.dart';
import 'routine_creator.dart';
import 'routine_detail_screen.dart';
import 'routine_editor_screen.dart';

/// Routines: My Routines and Explore with Target / Equipment / Level
/// filters (FR-RT-01, FR-RT-06).
class RoutinesTab extends ConsumerStatefulWidget {
  const RoutinesTab({super.key});

  @override
  ConsumerState<RoutinesTab> createState() => _RoutinesTabState();
}

class _RoutinesTabState extends ConsumerState<RoutinesTab> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String? _target;
  String? _equipment;
  int? _level;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final cat = app.catalog;
    final explore = RoutinePresets.all(cat).where((r) {
      if (_target != null && !RoutineMath.muscles(r.items, cat).contains(_target)) return false;
      if (_equipment != null && !RoutineMath.equipment(r.items, cat).contains(_equipment)) return false;
      if (_level != null && RoutineMath.level(r.items, cat) != _level) return false;
      return true;
    }).toList();
    return Column(children: [
      TabBar(
        controller: _tabs,
        indicatorColor: FF.accent,
        labelColor: FF.accent,
        unselectedLabelColor: FF.muted,
        tabs: const [Tab(key: Key('my_routines'), text: 'My Routines'), Tab(key: Key('explore'), text: 'Explore')],
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RoutineEditorScreen())),
                    icon: const Icon(Icons.add),
                    label: const Text('New Routine'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('routine_creator'),
                    onPressed: () => showRoutineCreator(context, ref),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Routine Creator'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              if (app.myRoutines.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No routines yet. Create one or save a routine from Explore.',
                      textAlign: TextAlign.center, style: TextStyle(color: FF.muted)),
                ),
              ...app.myRoutines.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: RoutineCard(routine: r, mine: true),
                  )),
            ],
          ),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                _filter('Target', Icons.accessibility_new, _target != null, () async {
                  final v = await _choose<String>('Target', MuscleIds.all.map((m) => (m, MuscleIds.label(m))).toList());
                  if (v != null) setState(() => _target = v.$1);
                }),
                _filter('Equipment', Icons.fitness_center, _equipment != null, () async {
                  final v = await _choose<String>(
                      'Equipment', ExerciseCatalog.equipmentTypes.map((e) => (e, e[0].toUpperCase() + e.substring(1))).toList());
                  if (v != null) setState(() => _equipment = v.$1);
                }),
                _filter('Level', Icons.signal_cellular_alt, _level != null, () async {
                  final v = await _choose<int>('Level', List.generate(5, (i) => (i + 1, 'Level ${i + 1}')));
                  if (v != null) setState(() => _level = v.$1);
                }),
              ]),
              const SizedBox(height: 14),
              if (explore.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No routines match these filters', textAlign: TextAlign.center, style: TextStyle(color: FF.muted)),
                ),
              ...explore.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: RoutineCard(routine: r, mine: false),
                  )),
            ],
          ),
        ]),
      ),
    ]);
  }

  Widget _filter(String label, IconData icon, bool active, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: active ? FF.accentSoft : FF.surface, padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
          ),
        ),
      );

  /// Returns (value,) or (null,) for "Any"; null when dismissed.
  Future<(T?,)?> _choose<T>(String title, List<(T, String)> options) async {
    final r = await showModalBottomSheet<(T?,)>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          ListTile(title: const Text('Any'), onTap: () => Navigator.pop(c, (null,))),
          for (final o in options) ListTile(title: Text(o.$2), onTap: () => Navigator.pop(c, (o.$1,))),
        ]),
      ),
    );
    return r;
  }
}

/// Routine card: name, Start, overflow menu, muscle chips and a strip of
/// exercise thumbnails.
class RoutineCard extends ConsumerWidget {
  final Routine routine;
  final bool mine;
  const RoutineCard({super.key, required this.routine, required this.mine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final cat = app.catalog;
    final muscles = RoutineMath.distribution(routine.items, cat).take(5).toList();
    final saved = app.data.savedPresets.contains(routine.id);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(FF.radius),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoutineDetailScreen(routine: routine))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.arrow_forward, color: FF.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(routine.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              if (mine)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), side: const BorderSide(color: FF.accent)),
                  onPressed: () => startWorkout(context, ref, routine),
                  icon: const Icon(Icons.directions_run, size: 18),
                  label: const Text('Start'),
                )
              else
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                  onPressed: () => app.togglePresetSaved(routine),
                  icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, size: 18),
                  label: Text(saved ? 'Saved' : 'Save'),
                ),
              if (mine)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoutineEditorScreen(initial: routine)));
                    } else if (v == 'duplicate') {
                      app.duplicateRoutine(routine);
                    } else if (v == 'delete') {
                      app.deleteRoutine(routine.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.timer_outlined, size: 16, color: FF.muted),
              const SizedBox(width: 4),
              Text('~${RoutineMath.estimatedMinutes(routine.items, cat)} min · ${routine.items.length} exercises',
                  style: const TextStyle(color: FF.muted, fontSize: 13)),
            ]),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: muscles
                    .map((m) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Column(children: [
                            Text(MuscleIds.label(m.key), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            MuscleChip(muscle: m.key, size: 60),
                          ]),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: routine.items
                    .map((it) => cat.byId(it.exerciseId))
                    .whereType<ExerciseDef>()
                    .map((e) => Padding(padding: const EdgeInsets.only(right: 8), child: ExerciseThumb(def: e, size: 64)))
                    .toList(),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
