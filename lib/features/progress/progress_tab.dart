import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../services/ads_service.dart';
import '../../domain/exercise.dart';
import '../../domain/history.dart';
import '../../domain/insights.dart';
import '../../domain/profile.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/muscle_map.dart';
import '../routines/routine_detail_screen.dart';
import '../settings/profile_sheet.dart';
import '../tracking/summary_screen.dart';

/// Recovery colour: red under 60 %, orange 60-89 %, green when recovered.
Color recoveryColor(double v) =>
    v >= 90 ? FF.good : (v >= 60 ? const Color(0xFFFF9F43) : const Color(0xFFFF3B30));

/// Progress (FR-PG-01..05): profile card, calendar and streak, form chart,
/// finished workouts and the Recover body figure.
class ProgressTab extends ConsumerStatefulWidget {
  const ProgressTab({super.key});

  @override
  ConsumerState<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends ConsumerState<ProgressTab> {
  bool _back = false;
  String? _selected;
  final _shareKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final cat = app.catalog;
    final p = app.profile;
    final now = appClock();
    final hist = [...app.data.history]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final doneDays = ProgressStats.completedWeekdays(hist, now);
    final streak = ProgressStats.streakWeeks(hist, now, p.weeklyTarget);
    final thisWeek = ProgressStats.workoutsThisWeek(hist, now);
    final weekStart = startOfWeek(now);
    final recovery = RecoveryModel.estimate(hist, cat, now);
    final chart = hist.take(10).toList().reversed.map((s) => (label: '${s.startedAt.day}/${s.startedAt.month}', score: s.avgForm)).toList();
    final female = p.sex == Sex.female;
    final visible = MuscleIds.all.where((m) => MuscleIds.back.contains(m) == _back || m == 'shoulders' || m == 'forearms').toList();

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      SectionCard(
        title: 'Profile',
        icon: Icons.tune,
        trailing: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
          onPressed: () => showProfileSheet(context),
          icon: const Icon(Icons.settings, size: 18),
          label: const Text('Settings'),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.person_outline, color: FF.accent, size: 30),
            const SizedBox(width: 6),
            Text('${p.name}, ${p.age}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _profileStat(Icons.flag_outlined, p.goal.label, 'Goal'),
            _profileStat(Icons.monitor_weight_outlined, p.weightLabel, 'Weight'),
            _profileStat(Icons.event_repeat, '${p.weeklyTarget} per week', 'How often'),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      CoachStrip(insights: Coach.insights(sessions: hist, profile: p, catalog: cat, now: now)),
      const SizedBox(height: 12),
      RepaintBoundary(
        key: _shareKey,
        child: SectionCard(
          title: 'Workout calendar',
          icon: Icons.event_available,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.local_fire_department, color: Color(0xFFFF7A3D), size: 20),
            Text('Streak: $streak ${streak == 1 ? 'week' : 'weeks'}',
                style: const TextStyle(color: Color(0xFFFF7A3D), fontWeight: FontWeight.w700)),
            IconButton(
              tooltip: 'Share progress',
              onPressed: () => shareBoundary(_shareKey, 'My FormFlow week: $thisWeek of ${p.weeklyTarget} workouts, $streak week streak'),
              icon: const Icon(Icons.ios_share, size: 20, color: FF.accent),
            ),
          ]),
          child: Row(children: [
            ...List.generate(7, (i) {
              final d = weekStart.add(Duration(days: i));
              final done = doneDays.contains(i);
              final isToday = d.day == now.day && d.month == now.month;
              return Expanded(
                child: Column(children: [
                  Text(const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][i], style: const TextStyle(color: FF.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? FF.good.withValues(alpha: 0.2) : Colors.transparent,
                      border: Border.all(color: isToday ? FF.accent : (done ? FF.good : Colors.transparent), width: 2),
                    ),
                    child: done
                        ? const Icon(Icons.check, color: FF.good, size: 18)
                        : Text('${d.day}', style: TextStyle(fontWeight: FontWeight.w700, color: d.isAfter(now) ? FF.muted : FF.text)),
                  ),
                ]),
              );
            }),
            Column(children: [
              const Text('Target', style: TextStyle(color: FF.muted, fontSize: 12)),
              const SizedBox(height: 4),
              ProgressRing(
                value: thisWeek / p.weeklyTarget,
                size: 40,
                stroke: 4,
                color: FF.good,
                child: Text('$thisWeek/${p.weeklyTarget}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: FF.good)),
              ),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Form score',
        icon: Icons.bar_chart,
        trailing: const Text('last 10', style: TextStyle(color: FF.muted)),
        child: FormScoreChart(points: chart),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Recover',
        icon: Icons.healing_outlined,
        trailing: const Text('estimate', style: TextStyle(color: FF.muted, fontStyle: FontStyle.italic)),
        child: Column(children: [
          SizedBox(
            height: 470,
            child: Row(children: [
              Expanded(
                flex: 5,
                child: Stack(children: [
                  Positioned.fill(
                    child: MuscleMap(
                      key: const Key('recover_map'),
                      back: _back,
                      female: female,
                      colors: {for (final e in recovery.entries) if (e.value < 90) e.key: recoveryColor(e.value)},
                      selected: _selected,
                      onTapMuscle: (m) => setState(() => _selected = m),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: IconButton.filledTonal(
                      key: const Key('rotate_body'),
                      tooltip: 'Rotate',
                      onPressed: () => setState(() => _back = !_back),
                      icon: const Icon(Icons.threesixty),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: ListView(
                  children: visible.map((m) {
                    final v = recovery[m] ?? 100;
                    final sel = _selected == m;
                    return InkWell(
                      onTap: () => setState(() => _selected = m),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: sel ? FF.accentSoft : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          MuscleChip(muscle: m, size: 46, female: female, color: recoveryColor(v)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(MuscleIds.label(m), style: const TextStyle(fontSize: 13)),
                              Text('${v.round()}%',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: recoveryColor(v))),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _legend(const Color(0xFFFF3B30), 'Under 60%'),
            _legend(const Color(0xFFFF9F43), '60-89%'),
            _legend(const Color(0xFFB9BCC8), 'Recovered'),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('fresh_workout'),
              onPressed: () {
                final r = RecoveryModel.freshRoutine(recovery, cat);
                if (r.items.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Most muscles are still recovering. Rest or stretch today.')));
                  return;
                }
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoutineDetailScreen(routine: r)));
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Fresh Muscle Workout'),
            ),
          ),
        ]),
      ),
      const AdBanner(AdPlacement.progress, padding: EdgeInsets.only(top: 12)),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Finished workouts',
        icon: Icons.checklist_rtl,
        child: hist.isEmpty
            ? const EmptyIllustration(text: 'Your finished workouts will appear here')
            : Column(
                children: hist.take(8).map((s) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: FF.scoreColor(s.avgForm).withValues(alpha: 0.2),
                      child: Icon(FF.scoreIcon(s.avgForm), color: FF.scoreColor(s.avgForm)),
                    ),
                    title: Text(s.routineName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${_date(s.startedAt)} · ${s.cleanReps} clean reps · ${s.duration.inMinutes} min'),
                    trailing: Text('${s.avgForm.round()}%', style: TextStyle(color: FF.scoreColor(s.avgForm), fontWeight: FontWeight.w800)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _HistorySummary(session: s))),
                  );
                }).toList(),
              ),
      ),
    ]);
  }

  static String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  Widget _legend(Color c, String t) => Expanded(
        child: Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Flexible(child: Text(t, style: const TextStyle(fontSize: 11, color: FF.muted))),
        ]),
      );

  Widget _profileStat(IconData icon, String value, String label) => Flexible(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: FF.text, size: 22),
          const SizedBox(width: 6),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(label, style: const TextStyle(color: FF.muted, fontSize: 12)),
            ]),
          ),
        ]),
      );
}

class _HistorySummary extends StatelessWidget {
  final WorkoutSession session;
  const _HistorySummary({required this.session});

  @override
  Widget build(BuildContext context) => SummaryScreen(session: session);
}
