import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/exercise.dart';
import '../../domain/insights.dart';
import '../../domain/routine.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/exercise_row.dart';
import '../../widgets/exercise_3d.dart';
import '../../widgets/mannequin.dart';
import '../../services/ads_service.dart';
import '../premium/premium_screen.dart';

/// Exercise detail (FR-EX-04): 3D demonstration, muscles worked, setup
/// tips, common mistakes with fixes, camera placement, Start / Demo.
/// Premium exercises show an unlock card until unlocked (doc item 11).
class ExerciseDetailScreen extends ConsumerWidget {
  final ExerciseDef def;
  const ExerciseDetailScreen({super.key, required this.def});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final animate = app.data.tier.animatedDemos && !app.settings.reduceMotion;
    final share = RoutineMath.exerciseShare(def);
    final single = Routine(id: 'single_${def.id}', name: def.name, items: [RoutineItem.defaults(def)]);
    final locked = !app.canUse(def);
    final left = app.entitlements.remaining(def.id, appClock());
    return Scaffold(
      appBar: AppBar(title: Text(def.name), actions: [
        IconButton(
          tooltip: 'Favourite',
          onPressed: () => app.toggleFavourite(def.id),
          icon: Icon(app.data.favourites.contains(def.id) ? Icons.star : Icons.star_border, color: FF.warn),
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _DemoPanel(def: def, animate: animate, prefer3d: true),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _Fact(icon: Icons.signal_cellular_alt, text: 'Level ${def.level}'),
            _Fact(icon: Icons.category_outlined, text: ExerciseCatalog.typeLabel(def.type)),
            _Fact(icon: Icons.fitness_center, text: def.equipment.map(ExerciseCatalog.equipmentLabel).join(', ')),
            _Fact(icon: Icons.repeat, text: def.targetLabel),
            if (def.premium) PremiumTag(unlocked: !locked),
          ]),
          if (left != null && !app.isPremium) ...[
            const SizedBox(height: 8),
            Text('Unlocked for ${left.inHours}h ${left.inMinutes % 60}m more', style: const TextStyle(color: FF.good, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          if (locked) ...[
            _LockedCard(def: def),
            const SizedBox(height: 12),
          ],
          SectionCard(
            title: 'Muscles worked',
            icon: Icons.accessibility_new,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: share.map((m) => MusclePercent(muscle: m.key, percent: m.value)).toList()),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'How to do it',
            icon: Icons.lightbulb_outline,
            child: Column(
              children: [
                for (var i = 0; i < def.tips.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: FF.accentSoft,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: FF.accent)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(def.tips[i]))),
                    ]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            key: const Key('common_mistakes'),
            title: 'Common mistakes',
            icon: Icons.report_gmailerrorred,
            child: Column(
              children: def.mistakeFixes
                  .map((m) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: FF.surface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.close_rounded, color: FF.bad, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(m.mistake, style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (m.fix.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Icon(Icons.check_rounded, color: FF.good, size: 16),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(m.fix, style: const TextStyle(color: FF.muted, fontSize: 13))),
                                ]),
                              ],
                            ]),
                          ),
                        ]),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Camera placement',
            icon: Icons.videocam_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 110,
                width: double.infinity,
                child: CustomPaint(
                    painter: _CameraDiagram(front: def.views.first == CameraView.front, metres: def.cameraDistance)),
              ),
              const SizedBox(height: 8),
              Text(def.cameraTip, style: const TextStyle(color: FF.muted)),
            ]),
          ),
          const AdBanner(AdPlacement.detail, padding: EdgeInsets.only(top: 12)),
          const SizedBox(height: 16),
          if (locked)
            FilledButton.icon(
              key: const Key('unlock_exercise'),
              onPressed: () => PremiumScreen.open(context, exercise: def),
              icon: const Icon(Icons.lock_open),
              label: const Text('Unlock this exercise'),
            )
          else ...[
            FilledButton.icon(
              key: const Key('start_camera'),
              onPressed: () => startWorkout(context, ref, single),
              icon: const Icon(Icons.videocam),
              label: const Text('Start with camera'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('start_demo'),
              onPressed: () => startWorkout(context, ref, single, demo: true),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Demo mode (no camera)'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Fact({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: FF.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: FF.outline)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: FF.accent),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _LockedCard extends StatelessWidget {
  final ExerciseDef def;
  const _LockedCard({required this.def});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('locked_card'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FF.radius),
          border: Border.all(color: const Color(0xFFFFC94D).withValues(alpha: 0.6)),
          color: const Color(0xFFFFC94D).withValues(alpha: 0.08),
        ),
        child: const Row(children: [
          Icon(Icons.lock, color: Color(0xFFFFC94D)),
          SizedBox(width: 10),
          Expanded(
            child: Text('Pro exercise. Go Premium, or watch a short ad to try it free for 24 hours.',
                style: TextStyle(fontSize: 13)),
          ),
        ]),
      );
}

/// Demonstration panel with a 3D / 2D switch (FR-DM-05). 3D is the default
/// on Standard and High devices; Lite and reduced motion start in 2D.
class _DemoPanel extends StatefulWidget {
  final ExerciseDef def;
  final bool animate;
  final bool prefer3d;
  const _DemoPanel({required this.def, required this.animate, required this.prefer3d});

  @override
  State<_DemoPanel> createState() => _DemoPanelState();
}

class _DemoPanelState extends State<_DemoPanel> {
  late bool _show3d = widget.prefer3d;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FF.radius),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C2350), Color(0xFF0D1029)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(
          child: _show3d
              ? Exercise3DView(def: widget.def, animate: widget.animate)
              : Padding(padding: const EdgeInsets.fromLTRB(8, 44, 8, 8), child: ExerciseDemo(def: widget.def, animate: widget.animate)),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: SegmentedButton<bool>(
            key: const Key('demo_view_toggle'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: true, label: Text('3D'), icon: Icon(Icons.view_in_ar, size: 16)),
              ButtonSegment(value: false, label: Text('2D')),
            ],
            selected: {_show3d},
            onSelectionChanged: (s) => setState(() => _show3d = s.first),
          ),
        ),
      ]),
    );
  }
}

/// Simple diagram: phone and person, side or front, with the distance.
class _CameraDiagram extends CustomPainter {
  final bool front;
  final double metres;
  _CameraDiagram({required this.front, required this.metres});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 12;
    final line = Paint()
      ..color = FF.outline
      ..strokeWidth = 2;
    canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), line);
    // phone
    final phone = RRect.fromRectAndRadius(Rect.fromLTWH(24, y - 54, 22, 40), const Radius.circular(4));
    canvas.drawRRect(phone, Paint()..color = FF.accent);
    canvas.drawCircle(Offset(35, y - 46), 3, Paint()..color = Colors.white);
    // person
    final px = size.width - 70;
    final body = Paint()
      ..color = FF.bodyFill
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(px, y - 80), 9, Paint()..color = FF.bodyFill);
    canvas.drawLine(Offset(px, y - 70), Offset(px, y - 36), body);
    canvas.drawLine(Offset(px, y - 36), Offset(px - (front ? 8 : 0), y - 2), body);
    canvas.drawLine(Offset(px, y - 36), Offset(px + (front ? 8 : 4), y - 2), body);
    canvas.drawLine(Offset(px, y - 64), Offset(px - (front ? 16 : 0), y - 40), body);
    canvas.drawLine(Offset(px, y - 64), Offset(px + (front ? 16 : 10), y - 42), body);
    // distance arrow
    final arrow = Paint()
      ..color = FF.muted
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(56, y - 30), Offset(px - 24, y - 30), arrow);
    final tp = TextPainter(
      text: TextSpan(
          text: front ? 'about $_m, facing you' : 'about $_m, side-on', style: const TextStyle(color: FF.muted, fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((56 + px - 24) / 2 - tp.width / 2, y - 48));
  }

  String get _m => metres == metres.roundToDouble() ? '${metres.round()} m' : '${metres.toStringAsFixed(1)} m';

  @override
  bool shouldRepaint(covariant _CameraDiagram old) => old.front != front || old.metres != metres;
}
