import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/core/theme.dart';
import 'package:formflow/domain/exercise.dart';
import 'package:formflow/widgets/common.dart';
import 'package:formflow/widgets/exercise_3d.dart';
import 'package:formflow/widgets/mannequin.dart';
import 'package:formflow/widgets/muscle_map.dart';

import '../helpers.dart';

Widget wrap(Widget w) => MaterialApp(theme: FF.theme(), home: Scaffold(body: Center(child: w)));

void main() {
  final cat = loadCatalog();

  testWidgets('LevelBars draws five bars and an accessible label', (t) async {
    await t.pumpWidget(wrap(const LevelBars(3)));
    expect(find.bySemanticsLabel('Level 3 of 5'), findsOneWidget);
  });

  testWidgets('StatusBadge shows Beta or Validated', (t) async {
    await t.pumpWidget(wrap(const Column(children: [StatusBadge(validated: false), StatusBadge(validated: true)])));
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Validated'), findsOneWidget);
  });

  testWidgets('every exercise thumbnail paints without errors', (t) async {
    await t.pumpWidget(wrap(Wrap(children: cat.exercises.map((e) => ExerciseThumb(def: e, size: 60)).toList())));
    expect(find.byType(ExerciseThumb), findsNWidgets(cat.exercises.length));
    expect(t.takeException(), isNull);
  });

  testWidgets('3D demonstration shows the rendered still while the video loads', (t) async {
    await t.pumpWidget(wrap(SizedBox(width: 200, height: 200, child: Exercise3DView(def: cat.byId('squat')!))));
    await t.pump(const Duration(milliseconds: 100));
    final img = t.widget<Image>(find.byType(Image));
    expect((img.image as AssetImage).assetName, 'assets/thumbs/squat.webp');
    expect(Exercise3DView.video('squat'), 'assets/exercise_video/squat.mp4');
    expect(t.takeException(), isNull);
  });

  testWidgets('premium tag and banner render', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(Column(children: [
      const PremiumTag(),
      PremiumBanner(lockedCount: 35, onTap: () => tapped = true),
    ])));
    expect(find.text('PRO'), findsOneWidget);
    expect(find.textContaining('35 pro exercises'), findsOneWidget);
    await t.tap(find.byKey(const Key('premium_banner')));
    expect(tapped, isTrue);
  });

  testWidgets('locked thumbnails show a lock badge', (t) async {
    await t.pumpWidget(wrap(ExerciseThumb(def: cat.byId('v_up')!, size: 80, locked: true)));
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('demonstration animates and respects reduced motion (FR-DM-07)', (t) async {
    final def = cat.byId('squat')!;
    await t.pumpWidget(wrap(SizedBox(width: 200, height: 200, child: ExerciseDemo(def: def))));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Start pose'), findsNothing);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: SizedBox(width: 200, height: 200, child: ExerciseDemo(def: def))),
      ),
    ));
    expect(find.text('Start pose'), findsOneWidget);
    await t.tap(find.text('Start pose'));
    await t.pump();
    expect(find.text('End pose'), findsOneWidget);
  });

  testWidgets('realistic muscle map loads, maps taps and renders chips', (t) async {
    final d = (await t.runAsync(() => BodyMapData.load()))!;
    await t.runAsync(() => d.ensureView('back'));
    for (final m in MuscleIds.all) {
      expect(d.hasMuscle('front', m) || d.hasMuscle('back', m), isTrue, reason: m);
    }
    // a point on the left pectoral is the chest in the ID map
    final chest = d.box('front', 'chest')!;
    expect(d.muscleAt('front', Offset(chest.left + chest.width * 0.25, chest.center.dy)), 'chest');
    final lats = d.box('back', 'lats')!;
    expect(d.muscleAt('back', Offset(lats.left + lats.width * 0.25, lats.center.dy)), 'lats');
    expect(d.muscleAt('front', const Offset(0.02, 0.02)), isNull);
    await t.pumpWidget(wrap(const SizedBox(width: 200, height: 400, child: MuscleMap(back: false, colors: {'chest': FF.muscle}))));
    await t.runAsync(() => d.ensureMask('front', 'chest'));
    await t.pump();
    expect(find.byType(CustomPaint), findsWidgets);
    await t.pumpWidget(wrap(const Row(children: [MuscleChip(muscle: 'quads'), MuscleChip(muscle: 'lats')])));
    expect(find.bySemanticsLabel('Quads muscle'), findsOneWidget);
  });

  testWidgets('form score chart pairs colour with icons (NFR accessibility)', (t) async {
    await t.pumpWidget(wrap(const SizedBox(
      width: 300,
      child: FormScoreChart(points: [(label: 'a', score: 90), (label: 'b', score: 60), (label: 'c', score: 30)]),
    )));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
  });
}
