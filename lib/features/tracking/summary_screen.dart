import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../domain/exercise.dart';
import '../../domain/history.dart';
import '../../services/ads_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/mannequin.dart';

/// Captures a RepaintBoundary as PNG and opens the share sheet (FR-PG-05).
Future<void> shareBoundary(GlobalKey key, String text) async {
  try {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    await SharePlus.instance.share(ShareParams(
      text: text,
      files: [XFile.fromData(bytes.buffer.asUint8List(), mimeType: 'image/png', name: 'formflow.png')],
    ));
  } catch (_) {
    // sharing is optional; never crash
  }
}

/// Post-workout summary (FR-PG-04).
class SummaryScreen extends ConsumerWidget {
  final WorkoutSession session;

  /// True right after a workout: free users may see an interstitial ad
  /// (every [AdConfig.interstitialEvery] workouts, never during training).
  final bool justFinished;
  const SummaryScreen({super.key, required this.session, this.justFinished = false});

  static final _adShownFor = <String>{};

  static String? fixNextTime(WorkoutSession s, ExerciseCatalog cat) {
    final counts = <String, int>{};
    for (final e in s.exercises) {
      for (final r in e.reps) {
        for (final i in r.issues) {
          counts[i] = (counts[i] ?? 0) + 1;
        }
      }
    }
    if (counts.isEmpty) return null;
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key.split(':');
    final template = cat.cues[top.first] ?? top.first;
    final parts = template.split('|');
    if (top.length > 1) return parts.first.replaceAll('{side}', top[1]);
    return parts.length > 1 ? parts[1] : parts.first.replaceAll('{side} ', '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(appProvider).catalog;
    if (justFinished && _adShownFor.add(session.startedAt.toIso8601String())) {
      final app = ref.read(appProvider);
      if (app.showAds && app.data.history.length % AdConfig.interstitialEvery == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(adsProvider).showInterstitial());
      }
    }
    final key = GlobalKey();
    final tip = fixNextTime(session, cat);
    final mins = session.duration.inMinutes;
    final secs = session.duration.inSeconds % 60;
    return Scaffold(
      appBar: AppBar(title: const Text('Workout summary'), automaticallyImplyLeading: false, actions: [
        IconButton(
          tooltip: 'Share',
          onPressed: () => shareBoundary(key, 'My FormFlow workout: ${session.cleanReps} clean reps, ${session.avgForm.round()}% form'),
          icon: const Icon(Icons.ios_share),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        RepaintBoundary(
          key: key,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FF.radius),
              gradient: const LinearGradient(colors: [Color(0xFF2B2470), Color(0xFF141933)]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.emoji_events, color: FF.warn, size: 30),
                const SizedBox(width: 8),
                Expanded(child: Text(session.routineName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _stat('Clean reps', '${session.cleanReps}', Icons.check_circle, FF.good),
                _stat('Attempts', '${session.attempts}', Icons.repeat, FF.accent),
                _stat('Avg form', '${session.avgForm.round()}%', FF.scoreIcon(session.avgForm), FF.scoreColor(session.avgForm)),
                _stat('Duration', '${mins}m ${secs}s', Icons.timer_outlined, FF.text),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (tip != null)
          Card(
            color: const Color(0xFF3A1E2A),
            child: ListTile(
              leading: const Icon(Icons.tips_and_updates, color: FF.warn),
              title: const Text('Fix next time', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tip),
            ),
          ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Exercises',
          icon: Icons.fitness_center,
          child: Column(
            children: session.exercises.map((e) {
              final def = cat.byId(e.exerciseId);
              final best = e.bestPeak ?? (e.reps.isEmpty ? null : e.reps.map((r) => r.peak).reduce((a, b) => a < b ? a : b));
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: def == null ? null : ExerciseThumb(def: def, size: 48),
                title: Text(def?.name ?? e.exerciseId),
                subtitle: Text(def != null && def.isTimed
                    ? '${e.seconds}s held · ${e.sets} sets'
                    : '${e.cleanReps}/${e.attempts} clean · best depth ${best == null ? '--' : '${best.round()}°'}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(FF.scoreIcon(e.avgForm), color: FF.scoreColor(e.avgForm), size: 18),
                  const SizedBox(width: 4),
                  Text('${e.avgForm.round()}%', style: TextStyle(color: FF.scoreColor(e.avgForm), fontWeight: FontWeight.w700)),
                ]),
              );
            }).toList(),
          ),
        ),
        const AdBanner(AdPlacement.summary, padding: EdgeInsets.only(top: 16)),
        const SizedBox(height: 20),
        FilledButton(key: const Key('summary_done'), onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ]),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) => Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: FF.tabular)),
            Text(label, style: const TextStyle(color: FF.muted, fontSize: 12)),
          ]),
        ]),
      );
}
