import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/exercise_3d.dart';
import '../../widgets/muscle_map.dart';

/// Value slides, 18+ gate, readiness questions and privacy note
/// (FR-AU-01, FR-AU-10).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const questions = [
    'Has a doctor said you have a heart condition?',
    'Do you feel chest pain during physical activity?',
    'Do you lose balance from dizziness?',
    'Do you have a bone or joint problem made worse by exercise?',
    'Are you taking medicine for blood pressure or a heart condition?',
  ];

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;
  bool? _adult;
  final _answers = List<bool?>.filled(OnboardingScreen.questions.length, null);

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 3) {
      _pc.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = ref.watch(catalogProvider);
    final squat = cat.byId('squat')!;
    final slides = [
      _Slide(
        title: 'Your pocket form coach',
        body: 'FormFlow watches you through the camera, counts clean reps and tells you which body part to fix.',
        art: MuscleMap(back: false, colors: const {'quads': FF.muscle, 'glutes': FF.muscle, 'abs': FF.muscle, 'chest': FF.muscle}),
      ),
      _Slide(
        title: '20 guided exercises',
        body: 'Every exercise has a realistic 3D demonstration with the worked muscles highlighted in red.',
        art: Exercise3DView(def: squat),
      ),
      _Slide(
        title: 'Private by design',
        body: 'Pose detection runs on your phone. Camera frames are never stored or uploaded, and everything works offline.',
        art: const Icon(Icons.shield_moon_outlined, size: 140, color: FF.accent),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(children: [
              const FormFlowLogo(),
              const Spacer(),
              if (_page < 3) TextButton(onPressed: () => _pc.jumpToPage(3), child: const Text('Skip')),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pc,
              onPageChanged: (i) => setState(() => _page = i),
              children: [...slides, _readiness()],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              4,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                width: i == _page ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _page ? FF.accent : FF.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: _page < 3
                  ? FilledButton(key: const Key('onboarding_next'), onPressed: _next, child: const Text('Next'))
                  : FilledButton(
                      key: const Key('onboarding_continue'),
                      onPressed: _adult == true && !_answers.contains(null) ? _finish : null,
                      child: const Text('Continue'),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  void _finish() {
    final flag = _answers.any((a) => a == true);
    if (flag) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Talk to a doctor first'),
          content: const Text(
              'You answered "yes" to at least one readiness question. Please check with a doctor before starting a new exercise programme. You can still explore the app.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                ref.read(appProvider).completeOnboarding(readinessFlag: true);
              },
              child: const Text('I understand'),
            ),
          ],
        ),
      );
      return;
    }
    ref.read(appProvider).completeOnboarding(readinessFlag: false);
  }

  Widget _readiness() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Before you start', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Are you 18 or older?',
          icon: Icons.verified_user_outlined,
          child: Row(children: [
            Expanded(
              child: ChoiceChip(
                key: const Key('age_yes'),
                label: const Text('Yes, I am 18+'),
                selected: _adult == true,
                onSelected: (_) => setState(() => _adult = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                key: const Key('age_no'),
                label: const Text('No'),
                selected: _adult == false,
                onSelected: (_) => setState(() => _adult = false),
              ),
            ),
          ]),
        ),
        if (_adult == false)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('FormFlow is designed for adults aged 18 and over, so tracking and nutrition are not available.',
                style: TextStyle(color: FF.bad)),
          ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Readiness questions',
          icon: Icons.favorite_border,
          child: Column(
            children: List.generate(OnboardingScreen.questions.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(child: Text(OnboardingScreen.questions[i])),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    key: Key('q$i'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('No')),
                      ButtonSegment(value: true, label: Text('Yes')),
                    ],
                    emptySelectionAllowed: true,
                    selected: _answers[i] == null ? <bool>{} : {_answers[i]!},
                    onSelectionChanged: (s) => setState(() => _answers[i] = s.isEmpty ? null : s.first),
                  ),
                ]),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'FormFlow gives general fitness guidance, not medical advice. Stop if you feel pain, dizziness or chest discomfort. '
          'The camera is used only while you train, and only after you allow it.',
          style: TextStyle(color: FF.muted, fontSize: 13),
        ),
      ],
    );
  }
}

class _Slide extends StatelessWidget {
  final String title;
  final String body;
  final Widget art;
  const _Slide({required this.title, required this.body, required this.art});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Expanded(child: Center(child: SizedBox(width: 260, height: 300, child: art))),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(body, textAlign: TextAlign.center, style: const TextStyle(color: FF.muted, fontSize: 16)),
      ]),
    );
  }
}
