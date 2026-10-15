import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../domain/insights.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Accuracy Test Lab (FR-TL-01..08): overall and per-exercise accuracy,
/// confusion matrix, precision / recall / F1, CSV export, clear data.
class TestLabScreen extends ConsumerWidget {
  const TestLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final labels = app.data.labLabels;
    final all = LabMetrics.of(labels);
    final byEx = <String, List<LabLabel>>{};
    for (final l in labels) {
      byEx.putIfAbsent(l.exerciseId, () => []).add(l);
    }
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
    return Scaffold(
      appBar: AppBar(title: const Text('Accuracy Test Lab'), actions: [
        IconButton(
          tooltip: 'Export CSV',
          onPressed: labels.isEmpty ? null : () => SharePlus.instance.share(ShareParams(text: LabMetrics.csv(labels), subject: 'FormFlow lab labels')),
          icon: const Icon(Icons.ios_share),
        ),
        IconButton(
          tooltip: 'Clear data',
          onPressed: labels.isEmpty ? null : () => app.clearLab(),
          icon: const Icon(Icons.delete_outline),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
          title: 'Overall',
          icon: Icons.analytics_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ProgressRing(
                value: all.accuracy,
                size: 92,
                stroke: 9,
                color: all.accuracy >= 0.85 ? FF.good : FF.warn,
                child: Text(pct(all.accuracy), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${all.n} labelled reps', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Precision ${pct(all.precision)}'),
                  Text('Recall (bad reps) ${pct(all.recall)}'),
                  Text('F1 ${all.f1.toStringAsFixed(3)}'),
                  Text('False alarms ${pct(all.falseAlarmRate)}'),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('Confusion matrix (positive = bad form)', style: TextStyle(color: FF.muted)),
            const SizedBox(height: 8),
            Table(
              border: TableBorder.all(color: FF.outline, borderRadius: BorderRadius.circular(8)),
              children: [
                _row(['', 'Truly bad', 'Truly good'], header: true),
                _row(['App: bad', '${all.tp} TP', '${all.fp} FP']),
                _row(['App: good', '${all.fn} FN', '${all.tn} TN']),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Targets: agreement 85%+, bad-rep recall 80%+, false alarms 15% or less.',
                style: TextStyle(color: FF.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Per exercise',
          icon: Icons.list,
          child: labels.isEmpty
              ? const Text('No labels yet. Turn on Tester mode and tap Right or Wrong after each rep.',
                  style: TextStyle(color: FF.muted))
              : Column(
                  children: byEx.entries.map((e) {
                    final m = LabMetrics.of(e.value);
                    final name = app.catalog.byId(e.key)?.name ?? e.key;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(name),
                      subtitle: Text('n=${m.n} · P ${pct(m.precision)} · R ${pct(m.recall)} · F1 ${m.f1.toStringAsFixed(2)}'),
                      trailing: Text(pct(m.accuracy),
                          style: TextStyle(fontWeight: FontWeight.w800, color: m.accuracy >= 0.85 ? FF.good : FF.warn)),
                    );
                  }).toList(),
                ),
        ),
      ]),
    );
  }

  TableRow _row(List<String> cells, {bool header = false}) => TableRow(
        decoration: header ? const BoxDecoration(color: FF.surface2) : null,
        children: cells
            .map((c) => Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(c, textAlign: TextAlign.center, style: TextStyle(fontWeight: header ? FontWeight.w700 : FontWeight.w500)),
                ))
            .toList(),
      );
}
