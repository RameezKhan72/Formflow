import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/feedback.dart';
import '../../domain/insights.dart';
import '../../domain/profile.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../premium/premium_screen.dart';
import 'body_scan_screen.dart';
import 'test_lab_screen.dart';

void showProfileSheet(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
}

/// Profile and settings (PRD 3.2a "Settings").
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final p = app.profile;
    final s = app.settings;
    void apply(AppSettings n) => app.updateSettings(n);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile and settings')),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(backgroundColor: FF.accentSoft, child: Text(p.name.isEmpty ? '?' : p.name[0])),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(p.guest ? 'Guest (data on this phone)' : (p.email.isEmpty ? 'Account' : p.email)),
        ),
        ListTile(
          key: const Key('settings_premium'),
          leading: const Icon(Icons.workspace_premium, color: Color(0xFFFFC94D)),
          title: Text(app.isPremium ? 'FormFlow Premium (active)' : 'Go Premium'),
          subtitle: Text(app.entitlements.owner ? 'Owner access' : (app.isPremium ? 'All exercises, no ads' : 'Unlock all exercises and remove ads')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => PremiumScreen.open(context),
        ),
        _header('Training'),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Goal'),
          trailing: DropdownButton<Goal>(
            value: p.goal,
            underline: const SizedBox(),
            onChanged: (g) => app.updateProfile(p.copyWith(goal: g)),
            items: Goal.values.map((g) => DropdownMenuItem(value: g, child: Text(g.label))).toList(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.event_repeat),
          title: const Text('Weekly target'),
          trailing: DropdownButton<int>(
            value: p.weeklyTarget,
            underline: const SizedBox(),
            onChanged: (v) => app.updateProfile(p.copyWith(weeklyTarget: v)),
            items: List.generate(7, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} per week'))),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.straighten),
          title: const Text('Use pounds (lb)'),
          value: p.useLb,
          onChanged: (v) => app.updateProfile(p.copyWith(useLb: v)),
        ),
        _header('Voice and feedback'),
        SwitchListTile(
          secondary: const Icon(Icons.record_voice_over_outlined),
          title: const Text('Voice coaching'),
          value: s.voice,
          onChanged: (v) => apply(s.copyWith(voice: v)),
        ),
        ListTile(
          leading: const Icon(Icons.volume_up_outlined),
          title: const Text('Volume'),
          subtitle: Slider(value: s.volume, onChanged: (v) => apply(s.copyWith(volume: v))),
        ),
        ListTile(
          leading: const Icon(Icons.pin_outlined),
          title: const Text('Speak rep numbers'),
          trailing: DropdownButton<RepSpeech>(
            value: s.repSpeech,
            underline: const SizedBox(),
            onChanged: (v) => apply(s.copyWith(repSpeech: v)),
            items: const [
              DropdownMenuItem(value: RepSpeech.every, child: Text('Every rep')),
              DropdownMenuItem(value: RepSpeech.everyFifth, child: Text('Every 5th')),
              DropdownMenuItem(value: RepSpeech.off, child: Text('Off')),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.graphic_eq),
          title: const Text('Voice style'),
          trailing: DropdownButton<String>(
            value: s.voiceStyle,
            underline: const SizedBox(),
            onChanged: (v) => apply(s.copyWith(voiceStyle: v)),
            items: const [
              DropdownMenuItem(value: 'coach', child: Text('Coach')),
              DropdownMenuItem(value: 'calm', child: Text('Calm')),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.vibration),
          title: const Text('Haptics'),
          value: s.haptics,
          onChanged: (v) => apply(s.copyWith(haptics: v)),
        ),
        const ListTile(leading: Icon(Icons.language), title: Text('Language'), trailing: Text('English')),
        _header('Camera and performance'),
        SwitchListTile(
          secondary: const Icon(Icons.cameraswitch_outlined),
          title: const Text('Use front camera'),
          value: s.frontCamera,
          onChanged: (v) => apply(s.copyWith(frontCamera: v)),
        ),
        ListTile(
          leading: const Icon(Icons.speed),
          title: const Text('Performance mode'),
          subtitle: Text('Detected: ${app.data.benchmarkTier?.label ?? 'not checked'}'
              '${app.data.benchmarkMs == null ? '' : ' (${app.data.benchmarkMs!.toStringAsFixed(2)} ms/frame)'}'),
          trailing: DropdownButton<String>(
            value: s.performance,
            underline: const SizedBox(),
            onChanged: (v) => apply(s.copyWith(performance: v)),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Auto')),
              DropdownMenuItem(value: 'lite', child: Text('Lite')),
              DropdownMenuItem(value: 'standard', child: Text('Standard')),
              DropdownMenuItem(value: 'high', child: Text('High')),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.animation),
          title: const Text('Reduce motion'),
          subtitle: const Text('Static demonstration poses'),
          value: s.reduceMotion,
          onChanged: (v) => apply(s.copyWith(reduceMotion: v)),
        ),
        ListTile(
          leading: const Icon(Icons.accessibility_new),
          title: const Text('Body Profile scan'),
          subtitle: Text(app.data.bodyProfile == null ? 'Not calibrated' : 'Quality ${app.data.bodyProfile!.quality}/100'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BodyScanScreen())),
        ),
        _header('Developer'),
        SwitchListTile(
          key: const Key('tester_mode'),
          secondary: const Icon(Icons.science_outlined),
          title: const Text('Tester mode'),
          subtitle: const Text('Shows Right / Wrong buttons after each rep'),
          value: s.testerMode,
          onChanged: (v) => apply(s.copyWith(testerMode: v)),
        ),
        if (s.testerMode)
          ListTile(
            key: const Key('open_lab'),
            leading: const Icon(Icons.analytics_outlined),
            title: const Text('Accuracy Test Lab'),
            subtitle: Text('${app.data.labLabels.length} labelled reps'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TestLabScreen())),
          ),
        ListTile(
          leading: const Icon(Icons.dataset_outlined),
          title: const Text('Load sample history'),
          subtitle: const Text('Three weeks of example workouts to explore Progress'),
          onTap: () {
            app.loadSampleData();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sample history loaded')));
          },
        ),
        _header('Data and account'),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Export my data (CSV)'),
          onTap: () {
            final b = StringBuffer('date,routine,exercise,sets,attempts,clean_reps,avg_form\n');
            for (final w in app.data.history) {
              for (final e in w.exercises) {
                b.writeln('${w.startedAt.toIso8601String()},${w.routineName},${e.exerciseId},${e.sets},${e.attempts},${e.cleanReps},${e.avgForm.toStringAsFixed(1)}');
              }
            }
            SharePlus.instance.share(ShareParams(text: b.toString(), subject: 'FormFlow history'));
          },
        ),
        ListTile(
          leading: const Icon(Icons.history_toggle_off),
          title: const Text('Clear workout history'),
          onTap: () => app.clearHistory(),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Log out'),
          onTap: () {
            app.logOut();
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: FF.bad),
          title: const Text('Delete account and data', style: TextStyle(color: FF.bad)),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Delete everything?'),
                content: const Text('This removes your profile, history, routines and Lab data from this phone. It cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: FF.bad), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                ],
              ),
            );
            if (ok == true) {
              await app.deleteAccount();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: const Text('Owner access'),
          subtitle: Text(app.entitlements.owner ? 'Active on this phone' : 'Enter your owner code'),
          onTap: () => _ownerCode(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About and credits'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'FormFlow',
            applicationVersion: '2.0.0',
            applicationIcon: const AppLogoMark(size: 48),
            children: const [
              Text('Anatomy figures and 3D exercise demonstrations are rendered from the Z-Anatomy 3D atlas '
                  '(github.com/LluisV/Z-Anatomy) by Lluís Vinent Juanico, licensed CC BY-SA 4.0. '
                  'The adapted images are shared under the same licence.'),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'FormFlow is general fitness guidance, not medical advice, and does not replace a doctor or certified trainer. '
            'Stop if you feel pain, dizziness or chest discomfort. Camera frames are processed on this phone and never stored or uploaded.',
            style: TextStyle(color: FF.muted, fontSize: 12),
          ),
        ),
      ]),
    );
  }

  Future<void> _ownerCode(BuildContext context, WidgetRef ref) async {
    final app = ref.read(appProvider);
    if (app.entitlements.owner) {
      final off = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Owner access'),
          content: const Text('Owner access is active. Turn it off on this phone?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Turn off')),
          ],
        ),
      );
      if (off == true) app.ownerLock();
      return;
    }
    final code = await showDialog<String>(context: context, builder: (c) => const _OwnerCodeDialog());
    if (code == null || !context.mounted) return;
    final ok = app.ownerUnlock(code);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Owner access on: every exercise unlocked, no ads' : 'That code is not correct')));
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(t.toUpperCase(), style: const TextStyle(color: FF.accent, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
      );
}

/// Owner code prompt; owns its text controller so it is disposed only after
/// the dialog has fully closed.
class _OwnerCodeDialog extends StatefulWidget {
  const _OwnerCodeDialog();

  @override
  State<_OwnerCodeDialog> createState() => _OwnerCodeDialogState();
}

class _OwnerCodeDialogState extends State<_OwnerCodeDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Owner access'),
        content: TextField(
          key: const Key('owner_code_field'),
          controller: _ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Owner code'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('owner_code_ok'),
            onPressed: () => Navigator.pop(context, _ctrl.text),
            child: const Text('Unlock'),
          ),
        ],
      );
}
