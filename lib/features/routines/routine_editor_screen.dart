import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/routine.dart';
import '../../state/app_state.dart';
import '../../widgets/mannequin.dart';

/// Create and edit routines (FR-RT-04).
class RoutineEditorScreen extends ConsumerStatefulWidget {
  final Routine? initial;
  const RoutineEditorScreen({super.key, this.initial});

  @override
  ConsumerState<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  late final _name = TextEditingController(text: widget.initial?.name ?? 'My Routine');
  late final List<RoutineItem> _items = [...?widget.initial?.items];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final cat = ref.read(appProvider).catalog;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (c, sc) => ListView(
          controller: sc,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Add exercise', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            for (final e in cat.exercises)
              ListTile(
                leading: ExerciseThumb(def: e, size: 44),
                title: Text(e.name),
                subtitle: Text(e.group),
                onTap: () => Navigator.pop(c, e.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _items.add(RoutineItem.defaults(cat.byId(picked)!)));
  }

  void _save() {
    if (_name.text.trim().isEmpty || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a name and at least one exercise')));
      return;
    }
    final app = ref.read(appProvider);
    final id = widget.initial?.id ?? 'user_${DateTime.now().microsecondsSinceEpoch}';
    app.saveRoutine(Routine(id: id, name: _name.text.trim(), source: 'user', items: _items));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cat = ref.watch(appProvider).catalog;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New routine' : 'Edit routine'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add exercise')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Routine name')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('~${RoutineMath.estimatedMinutes(_items, cat)} min · drag to reorder', style: const TextStyle(color: FF.muted)),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
            itemCount: _items.length,
            onReorder: (a, b) => setState(() {
              if (b > a) b--;
              _items.insert(b, _items.removeAt(a));
            }),
            itemBuilder: (context, i) {
              final it = _items[i];
              final e = cat.byId(it.exerciseId)!;
              return Card(
                key: ValueKey('${it.exerciseId}_$i'),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    ExerciseThumb(def: e, size: 48),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                    _stepper('sets', it.sets, (v) => setState(() => _items[i] = it.copyWith(sets: v))),
                    e.isTimed
                        ? _stepper('sec', it.seconds, (v) => setState(() => _items[i] = it.copyWith(seconds: v)), step: 5)
                        : _stepper('reps', it.reps, (v) => setState(() => _items[i] = it.copyWith(reps: v))),
                    IconButton(onPressed: () => setState(() => _items.removeAt(i)), icon: const Icon(Icons.delete_outline)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _stepper(String label, int v, ValueChanged<int> on, {int step = 1}) => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          InkWell(onTap: v - step >= 1 ? () => on(v - step) : null, child: const Icon(Icons.remove, size: 20)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('$v', style: const TextStyle(fontWeight: FontWeight.w700))),
          InkWell(onTap: () => on(v + step), child: const Icon(Icons.add, size: 20)),
        ]),
        Text(label, style: const TextStyle(color: FF.muted, fontSize: 11)),
      ]);
}
