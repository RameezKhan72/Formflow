import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/demo_motion.dart';
import '../../domain/exercise.dart';
import '../../domain/insights.dart';
import '../../domain/profile.dart';
import '../../domain/rules.dart';
import '../../domain/tracking_session.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Runs the real engine on synthetic frames and returns ms per frame.
/// Used as a quick device-tier benchmark (PRD 9.1).
double runBenchmark(ExerciseCatalog cat, {int frames = 240}) {
  final def = cat.byId('squat') ?? cat.exercises.first;
  final s = TrackingSession(def, cues: CueBook(cat.cues), voice: false);
  final motion = DemoMotion(def);
  final sw = Stopwatch()..start();
  for (var i = 0; i < frames; i++) {
    final t = i / 15.0;
    s.process(motion.pose(t), t);
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000 / frames;
}

/// Profile setup (FR-PR-02..04) followed by the device check.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late UserProfile _p = ref.read(appProvider).profile;
  late final _name = TextEditingController(text: _p.name == 'Guest' ? '' : _p.name);
  late final _age = TextEditingController(text: '${_p.age}');
  late final _height = TextEditingController(text: _p.heightCm.round().toString());
  late final _weight = TextEditingController(text: _p.weightKg.toStringAsFixed(0));
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    final age = int.tryParse(_age.text.trim());
    final h = double.tryParse(_height.text.trim());
    final w = double.tryParse(_weight.text.trim());
    final err = Validators.name(_name.text) ??
        Validators.age(age) ??
        Validators.range(h, 120, 230, 'height in cm') ??
        Validators.range(w, 30, 250, 'weight in kg');
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final app = ref.read(appProvider);
    app.updateProfile(_p.copyWith(name: _name.text.trim(), age: age, heightCm: h, weightKg: w));
    setState(() => _checking = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final ms = runBenchmark(app.catalog);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    app.setBenchmark(ms);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 64, height: 64, child: CircularProgressIndicator(strokeWidth: 6)),
            SizedBox(height: 20),
            Text('Checking your phone', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('Picking the best performance profile', style: TextStyle(color: FF.muted)),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(key: const Key('setup_name'), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          const Text('Sex', style: TextStyle(color: FF.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final s in Sex.values)
              ChoiceChip(
                label: Text(s == Sex.male ? 'Male' : 'Female'),
                selected: _p.sex == s,
                onSelected: (_) => setState(() => _p = _p.copyWith(sex: s)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _num(_age, 'Age', 'setup_age')),
            const SizedBox(width: 8),
            Expanded(child: _num(_height, 'Height (cm)', 'setup_height')),
            const SizedBox(width: 8),
            Expanded(child: _num(_weight, 'Weight (kg)', 'setup_weight')),
          ]),
          const SizedBox(height: 16),
          const Text('Goal', style: TextStyle(color: FF.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in Goal.values)
              ChoiceChip(label: Text(g.label), selected: _p.goal == g, onSelected: (_) => setState(() => _p = _p.copyWith(goal: g))),
          ]),
          const SizedBox(height: 16),
          Text('Workouts per week: ${_p.weeklyTarget}', style: const TextStyle(color: FF.muted)),
          Slider(
            value: _p.weeklyTarget.toDouble(),
            min: 1,
            max: 7,
            divisions: 6,
            label: '${_p.weeklyTarget}',
            onChanged: (v) => setState(() => _p = _p.copyWith(weeklyTarget: v.round())),
          ),
          const Text('Workout time', style: TextStyle(color: FF.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final slot in const [('Morning', 6 * 60), ('Afternoon', 16 * 60), ('Evening', 18 * 60)])
              ChoiceChip(
                label: Text('${slot.$1} ${DayPlan.clock(slot.$2)}'),
                selected: _p.slotMinutes == slot.$2,
                onSelected: (_) => setState(() => _p = _p.copyWith(slotMinutes: slot.$2)),
              ),
            ActionChip(
              label: const Text('Custom'),
              avatar: const Icon(Icons.schedule, size: 18),
              onPressed: () async {
                final t = await showTimePicker(
                    context: context, initialTime: TimeOfDay(hour: _p.slotMinutes ~/ 60, minute: _p.slotMinutes % 60));
                if (t != null) setState(() => _p = _p.copyWith(slotMinutes: t.hour * 60 + t.minute));
              },
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: FF.bad)),
          ],
          const SizedBox(height: 24),
          FilledButton(key: const Key('setup_done'), onPressed: _done, child: const Text('Finish setup')),
          const SizedBox(height: 8),
          const SectionCard(
            child: Text('Your body data is used only for nutrition targets and stays on this phone.',
                style: TextStyle(color: FF.muted, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _num(TextEditingController c, String label, String key) => TextField(
        key: Key(key),
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );
}
