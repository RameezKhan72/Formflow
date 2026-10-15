import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/exercise.dart';
import '../../services/ads_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/exercise_row.dart';
import '../../widgets/mannequin.dart';
import '../premium/premium_screen.dart';
import 'exercise_detail_screen.dart';

/// Body-part section requested from elsewhere (e.g. the home screen).
final libraryGroupProvider = StateProvider<String?>((ref) => null);

/// Exercise library (FR-EX-03, doc items 5, 7, 8): a filter bar on top
/// (equipment, muscle, type), then one section per body part. Premium
/// exercises carry a lock until unlocked.
class ExercisesTab extends ConsumerStatefulWidget {
  const ExercisesTab({super.key});

  @override
  ConsumerState<ExercisesTab> createState() => _ExercisesTabState();
}

class _ExercisesTabState extends ConsumerState<ExercisesTab> {
  final _search = TextEditingController();
  String _q = '';
  String? _type;
  String? _equipment;
  String? _muscle;
  String? _group;
  bool _favOnly = false;

  bool get _filtering =>
      _q.isNotEmpty || _type != null || _equipment != null || _muscle != null || _group != null || _favOnly;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ExerciseDef> _filter(ExerciseCatalog cat, Set<String> favs) {
    final q = _q.toLowerCase().trim();
    return cat.exercises.where((e) {
      if (q.isNotEmpty &&
          !e.name.toLowerCase().contains(q) &&
          !e.muscles.keys.any((m) => MuscleIds.label(m).toLowerCase().contains(q)) &&
          !e.groupLabel.toLowerCase().contains(q)) {
        return false;
      }
      if (_type != null && e.type != _type) return false;
      if (_equipment != null && !e.equipment.contains(_equipment)) return false;
      if (_muscle != null && (e.normalisedMuscles[_muscle] ?? 0) < 0.15) return false;
      if (_group != null && e.group != _group) return false;
      if (_favOnly && !favs.contains(e.id)) return false;
      return true;
    }).toList();
  }

  Future<void> _pick(String title, IconData icon, List<(String, String)> options, String? current, ValueChanged<String?> onPick) async {
    final r = await showModalBottomSheet<(bool, String?)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Icon(icon, color: FF.accent),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ]),
            ),
            ListTile(
              leading: Icon(current == null ? Icons.radio_button_checked : Icons.radio_button_off, color: FF.accent),
              title: const Text('All'),
              onTap: () => Navigator.pop(c, (true, null)),
            ),
            for (final o in options)
              ListTile(
                key: Key('pick_${o.$1}'),
                leading: Icon(o.$1 == current ? Icons.radio_button_checked : Icons.radio_button_off, color: FF.accent),
                title: Text(o.$2),
                onTap: () => Navigator.pop(c, (true, o.$1)),
              ),
          ]),
        ),
      ),
    );
    if (r != null && r.$1) setState(() => onPick(r.$2));
  }

  void _clear() => setState(() {
        _q = '';
        _search.clear();
        _type = null;
        _equipment = null;
        _muscle = null;
        _group = null;
        _favOnly = false;
      });

  void _open(ExerciseDef e) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExerciseDetailScreen(def: e)));

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(libraryGroupProvider, (prev, next) {
      if (next == null) return;
      setState(() {
        _clear();
        _group = next;
      });
      Future.microtask(() => ref.read(libraryGroupProvider.notifier).state = null);
    });
    final app = ref.watch(appProvider);
    final cat = app.catalog;
    final favs = app.data.favourites;
    final list = _filter(cat, favs);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              key: const Key('exercise_search'),
              controller: _search,
              onChanged: (v) => setState(() => _q = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search ${cat.exercises.length} exercises',
                prefixIcon: const Icon(Icons.search),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _q = '';
                          _search.clear();
                        })),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            key: const Key('fav_filter'),
            tooltip: 'Favourites',
            onPressed: () => setState(() => _favOnly = !_favOnly),
            icon: Icon(_favOnly ? Icons.star : Icons.star_border, color: _favOnly ? FF.warn : FF.muted),
          ),
        ]),
      ),
      // Filter bar on top of the library (doc item 7).
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          FilterPill(
            key: const Key('filter_equipment'),
            label: 'Equipment',
            value: _equipment == null ? null : ExerciseCatalog.equipmentLabel(_equipment!),
            icon: Icons.fitness_center,
            onTap: () => _pick('Equipment', Icons.fitness_center,
                ExerciseCatalog.equipmentTypes.map((e) => (e, ExerciseCatalog.equipmentLabel(e))).toList(), _equipment, (v) => _equipment = v),
          ),
          FilterPill(
            key: const Key('filter_muscle'),
            label: 'Muscle',
            value: _muscle == null ? null : MuscleIds.label(_muscle!),
            icon: Icons.accessibility_new,
            onTap: () => _pick('Muscle', Icons.accessibility_new, MuscleIds.all.map((m) => (m, MuscleIds.label(m))).toList(),
                _muscle, (v) => _muscle = v),
          ),
          FilterPill(
            key: const Key('filter_type'),
            label: 'Type',
            value: _type == null ? null : ExerciseCatalog.typeLabel(_type!),
            icon: Icons.category_outlined,
            onTap: () => _pick('Type', Icons.category_outlined,
                ExerciseCatalog.types.map((t) => (t, ExerciseCatalog.typeLabel(t))).toList(), _type, (v) => _type = v),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _filtering
            ? _results(list, app)
            : ListView(
                key: const Key('library_sections'),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (!app.isPremium)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: PremiumBanner(
                        lockedCount: cat.exercises.where((e) => !app.canUse(e)).length,
                        onTap: () => PremiumScreen.open(context),
                      ),
                    ),
                  for (final g in ExerciseCatalog.groups)
                    if (cat.inGroup(g).isNotEmpty) ...[
                      SectionHeader(
                        key: Key('section_$g'),
                        title: ExerciseCatalog.groupLabel(g),
                        count: cat.inGroup(g).length,
                        onSeeAll: () => setState(() => _group = g),
                      ),
                      SizedBox(
                        height: 200,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: cat.inGroup(g).length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (context, i) {
                            final e = cat.inGroup(g)[i];
                            return ExerciseCard(key: Key('card_${e.id}'), def: e, locked: !app.canUse(e), onTap: () => _open(e));
                          },
                        ),
                      ),
                      if (g == 'arms') const AdBanner(AdPlacement.library),
                    ],
                ],
              ),
      ),
    ]);
  }

  Widget _results(List<ExerciseDef> list, AppController app) {
    final favs = app.data.favourites;
    final chips = <Widget>[
      if (_group != null) _chip(ExerciseCatalog.groupLabel(_group!), () => setState(() => _group = null)),
      if (_equipment != null) _chip(ExerciseCatalog.equipmentLabel(_equipment!), () => setState(() => _equipment = null)),
      if (_muscle != null) _chip(MuscleIds.label(_muscle!), () => setState(() => _muscle = null)),
      if (_type != null) _chip(ExerciseCatalog.typeLabel(_type!), () => setState(() => _type = null)),
      if (_favOnly) _chip('Favourites', () => setState(() => _favOnly = false)),
    ];
    return ListView(
      key: const Key('library_results'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(children: [
          Text('${list.length} exercise${list.length == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: FF.muted)),
          const Spacer(),
          TextButton(key: const Key('clear_filters'), onPressed: _clear, child: const Text('Clear all')),
        ]),
        if (chips.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: chips),
        const SizedBox(height: 6),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: Text('No exercises match these filters', style: TextStyle(color: FF.muted))),
          ),
        for (var i = 0; i < list.length; i++) ...[
          ExerciseRow(
            key: Key('ex_${list[i].id}'),
            def: list[i],
            showBadge: true,
            locked: !app.canUse(list[i]),
            subtitle: '${list[i].groupLabel} · ${MuscleIds.label(list[i].primaryMuscle)}',
            onTap: () => _open(list[i]),
            trailing: IconButton(
              tooltip: favs.contains(list[i].id) ? 'Remove favourite' : 'Add favourite',
              onPressed: () => app.toggleFavourite(list[i].id),
              icon: Icon(favs.contains(list[i].id) ? Icons.star : Icons.star_border,
                  color: favs.contains(list[i].id) ? FF.warn : FF.muted),
            ),
          ),
          if (i < list.length - 1) const Divider(height: 1),
          if (i == 5) const AdBanner(AdPlacement.library),
        ],
      ],
    );
  }

  Widget _chip(String label, VoidCallback onClear) => InputChip(
        label: Text(label),
        onDeleted: onClear,
        deleteIcon: const Icon(Icons.close, size: 16),
      );
}

/// One of the three big filter buttons on top of the library.
class FilterPill extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;
  const FilterPill({super.key, required this.label, required this.value, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = value != null;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: active ? FF.accentSoft : FF.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: active ? FF.accent : FF.outline),
              ),
              child: Row(children: [
                Icon(icon, size: 18, color: active ? FF.accent : FF.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: FF.muted)),
                      Text(value ?? 'All',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? FF.text : FF.text)),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more, size: 18, color: FF.muted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onSeeAll;
  const SectionHeader({super.key, required this.title, required this.count, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Row(children: [
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: FF.surface2, borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: const TextStyle(color: FF.muted, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const Spacer(),
        TextButton(onPressed: onSeeAll, child: const Text('See all')),
      ]),
    );
  }
}

/// Library card: 3D still, name, level and a lock for premium exercises.
class ExerciseCard extends StatelessWidget {
  final ExerciseDef def;
  final bool locked;
  final VoidCallback onTap;
  const ExerciseCard({super.key, required this.def, required this.locked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 138,
      child: Material(
        color: FF.surface,
        borderRadius: BorderRadius.circular(FF.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExerciseThumb(def: def, size: 138, locked: locked),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 0),
              child: Text(def.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 8, 0),
              child: Row(children: [
                LevelBars(def.level),
                const Spacer(),
                if (def.premium) PremiumTag(unlocked: !locked),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
