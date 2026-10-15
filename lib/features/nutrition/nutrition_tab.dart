import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../services/ads_service.dart';
import '../../domain/insights.dart';
import '../../domain/nutrition.dart';
import '../../domain/profile.dart';
import '../../domain/routine.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Nutrition, vitamins and time plans (FR-NU, FR-VT, FR-TP).
class NutritionTab extends ConsumerWidget {
  const NutritionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final p = app.profile;
    if (!app.data.ageConfirmed) {
      return const Center(child: Text('Nutrition guidance is for adults aged 18+.'));
    }
    final plan = Nutrition.plan(p);
    final style = Nutrition.trainingStyle(p.goal);
    final meals = Nutrition.mealPlan(p);
    final today = appClock().weekday % 7;
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final kcalTotal = plan.proteinG * 4 + plan.fatG * 9 + plan.carbsG * 4;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Wrap(spacing: 8, children: [
        for (final g in Goal.values)
          ChoiceChip(
            label: Text(g.label),
            selected: p.goal == g,
            onSelected: (_) => app.updateProfile(p.copyWith(goal: g)),
          ),
      ]),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Body data',
        icon: Icons.monitor_weight_outlined,
        trailing: TextButton(onPressed: () => _editBody(context, ref), child: const Text('Edit')),
        child: Wrap(spacing: 18, runSpacing: 8, children: [
          _kv('Sex', p.sex == Sex.male ? 'Male' : 'Female'),
          _kv('Age', '${p.age}'),
          _kv('Height', '${p.heightCm.round()} cm'),
          _kv('Weight', p.weightLabel),
          _kv('Activity', Nutrition.activityFactors[p.activityFactor] ?? p.activityFactor.toString()),
          _kv('BMI', plan.bmi.toStringAsFixed(1)),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Daily calories',
        icon: Icons.local_fire_department_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${plan.target.round()}',
                key: const Key('kcal_target'),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, fontFeatures: FF.tabular)),
            const Padding(padding: EdgeInsets.only(bottom: 8, left: 6), child: Text('kcal / day', style: TextStyle(color: FF.muted))),
          ]),
          Text('BMR ${plan.bmr.round()} · maintenance ${plan.maintenance.round()} kcal', style: const TextStyle(color: FF.muted)),
          if (plan.floorApplied)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Raised to the minimum daily floor for safety.', style: TextStyle(color: FF.warn)),
            ),
          if (plan.deficitBlocked)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Your BMI is below 18.5, so we show maintenance instead of a deficit.', style: TextStyle(color: FF.warn)),
            ),
          const SizedBox(height: 14),
          _macro('Protein', plan.proteinG, plan.proteinG * 4 / kcalTotal, const Color(0xFF5B8CFF)),
          _macro('Carbs', plan.carbsG, plan.carbsG * 4 / kcalTotal, FF.warn),
          _macro('Fat', plan.fatG, plan.fatG * 9 / kcalTotal, const Color(0xFFE66BD5)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.water_drop_outlined, color: Color(0xFF4FC3F7)),
            const SizedBox(width: 6),
            Text('Water ${plan.waterL.toStringAsFixed(2)} L / day'),
          ]),
        ]),
      ),
      const AdBanner(AdPlacement.nutrition),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Training style',
        icon: Icons.fitness_center,
        child: Row(children: [
          Expanded(child: _kv('Sets', style.sets)),
          Expanded(child: _kv('Reps', style.reps)),
          Expanded(child: _kv('Rest', style.rest)),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Meal plan',
        icon: Icons.restaurant_menu,
        child: Column(
          children: meals
              .map((m) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(DayPlan.clock(m.minutes), style: const TextStyle(color: FF.accent, fontFeatures: FF.tabular)),
                    title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(m.foods),
                    trailing: Text('${m.kcal} kcal', style: const TextStyle(color: FF.muted)),
                  ))
              .toList(),
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Daily timeline',
        icon: Icons.schedule,
        trailing: TextButton(
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: p.slotMinutes ~/ 60, minute: p.slotMinutes % 60));
            if (t != null) app.updateProfile(p.copyWith(slotMinutes: t.hour * 60 + t.minute));
          },
          child: const Text('Change time'),
        ),
        child: Column(
          children: DayPlan.timeline(p.slotMinutes)
              .map((e) => Row(children: [
                    SizedBox(
                        width: 82,
                        child: Text(DayPlan.clock(e.minutes), style: const TextStyle(color: FF.accent, fontFeatures: FF.tabular))),
                    Container(width: 2, height: 40, color: FF.outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(e.detail, style: const TextStyle(color: FF.muted, fontSize: 12)),
                      ]),
                    ),
                  ]))
              .toList(),
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Weekly schedule',
        icon: Icons.calendar_month,
        child: Column(
          children: List.generate(7, (i) {
            final isToday = i == today;
            final rid = RoutinePresets.weekly[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isToday ? FF.accentSoft : FF.surface2,
                borderRadius: BorderRadius.circular(12),
                border: isToday ? Border.all(color: FF.accent) : null,
              ),
              child: Row(children: [
                SizedBox(width: 44, child: Text(days[i], style: TextStyle(fontWeight: isToday ? FontWeight.w800 : FontWeight.w500))),
                Icon(rid == null ? Icons.self_improvement : Icons.fitness_center, size: 18, color: rid == null ? FF.muted : FF.accent),
                const SizedBox(width: 8),
                Expanded(child: Text(RoutinePresets.weeklyLabels[i])),
                if (isToday) const Text('Today', style: TextStyle(color: FF.accent, fontWeight: FontWeight.w700)),
              ]),
            );
          }),
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Vitamins and minerals',
        icon: Icons.medication_liquid_outlined,
        child: Column(children: [
          ...Nutrition.vitamins(p.sex, p.age).map((v) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 100, child: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                  SizedBox(width: 92, child: Text(v.amount, style: const TextStyle(color: FF.accent))),
                  Expanded(child: Text(v.sources, style: const TextStyle(color: FF.muted, fontSize: 13))),
                ]),
              )),
          const SizedBox(height: 8),
          const Text(Nutrition.disclaimer, style: TextStyle(color: FF.warn, fontSize: 12)),
        ]),
      ),
    ]);
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(color: FF.muted, fontSize: 12)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);

  Widget _macro(String label, double grams, double share, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${grams.round()} g', style: const TextStyle(fontFeatures: FF.tabular)),
          ]),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: share.clamp(0, 1).toDouble()),
            duration: const Duration(milliseconds: 600),
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: v, minHeight: 10, color: c, backgroundColor: FF.outline),
            ),
          ),
        ]),
      );

  void _editBody(BuildContext context, WidgetRef ref) {
    final app = ref.read(appProvider);
    var p = app.profile;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Body data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final s in Sex.values)
                ChoiceChip(label: Text(s.name), selected: p.sex == s, onSelected: (_) => setLocal(() => p = p.copyWith(sex: s))),
            ]),
            Text('Age ${p.age}'),
            Slider(value: p.age.toDouble(), min: 18, max: 80, divisions: 62, onChanged: (v) => setLocal(() => p = p.copyWith(age: v.round()))),
            Text('Height ${p.heightCm.round()} cm'),
            Slider(value: p.heightCm.clamp(140, 210).toDouble(), min: 140, max: 210, onChanged: (v) => setLocal(() => p = p.copyWith(heightCm: v.roundToDouble()))),
            Text('Weight ${p.weightKg.toStringAsFixed(1)} kg'),
            Slider(value: p.weightKg.clamp(40, 150).toDouble(), min: 40, max: 150, onChanged: (v) => setLocal(() => p = p.copyWith(weightKg: (v * 2).round() / 2))),
            const Text('Activity'),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in Nutrition.activityFactors.entries)
                ChoiceChip(label: Text(e.value), selected: p.activityFactor == e.key, onSelected: (_) => setLocal(() => p = p.copyWith(activityFactor: e.key))),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  app.updateProfile(p);
                  Navigator.pop(c);
                },
                child: const Text('Save'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
