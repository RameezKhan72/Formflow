import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../domain/exercise.dart';
import 'common.dart';
import 'mannequin.dart';
import 'muscle_map.dart';

/// Exercise row: thumbnail, level bars, tip and instruction icons, name,
/// subtitle and an optional trailing widget.
class ExerciseRow extends StatelessWidget {
  final ExerciseDef def;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showBadge;
  final bool locked;
  const ExerciseRow(
      {super.key, required this.def, required this.subtitle, this.trailing, this.onTap, this.showBadge = false, this.locked = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          ExerciseThumb(def: def, size: 76, locked: locked),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                LevelBars(def.level),
                const SizedBox(width: 10),
                Tooltip(
                  message: def.tips.isEmpty ? 'Tip' : def.tips.first,
                  child: const Icon(Icons.lightbulb_outline, size: 18, color: FF.accent),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.checklist, size: 18, color: FF.accent),
                if (showBadge && def.premium) ...[const SizedBox(width: 8), PremiumTag(unlocked: !locked)],
              ]),
              const SizedBox(height: 4),
              Text(def.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(color: FF.muted)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

/// Muscle chip with a percentage label, as in the workout list.
class MusclePercent extends StatelessWidget {
  final String muscle;
  final double percent;
  const MusclePercent({super.key, required this.muscle, required this.percent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Column(children: [
        Text(MuscleIds.label(muscle),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        MuscleChip(muscle: muscle, size: 48),
        Text('${percent.round()}%', style: const TextStyle(color: FF.accent, fontSize: 13, fontFeatures: FF.tabular)),
      ]),
    );
  }
}
