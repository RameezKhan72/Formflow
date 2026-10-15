import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/data/app_store.dart';
import 'package:formflow/domain/insights.dart';
import 'package:formflow/domain/profile.dart';
import 'package:formflow/domain/routine.dart';
import 'package:formflow/domain/exercise.dart';
import 'package:formflow/domain/sample_data.dart';
import 'package:formflow/features/tracking/workout_run_screen.dart';
import 'package:formflow/main.dart';
import 'package:integration_test/integration_test.dart';

/// Drives the real app on an Android emulator and saves screenshots.
/// Run: flutter drive --driver=test_driver/integration_test.dart \
///        --target=integration_test/screenshots_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var converted = false;

  testWidgets('FormFlow screenshot tour', (t) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }

    Future<void> shot(String name) async {
      if (!converted && Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await t.pump();
      await binding.takeScreenshot(name);
      // ignore: avoid_print
      print('screenshot: $name');
    }

    Future<void> toRoot() async {
      final navs = find.byType(Navigator);
      if (navs.evaluate().isEmpty) return;
      t.state<NavigatorState>(navs.first).popUntil((r) => r.isFirst);
      await wait(500);
    }

    Future<void> step(String label, Future<void> Function() body) async {
      try {
        if (!label.startsWith('splash') && !label.startsWith('home')) await toRoot();
        await body();
      } catch (e, st) {
        // ignore: avoid_print
        print('STEP FAILED [$label]: $e\n$st');
      }
    }

    Future<void> tapKey(String key) async {
      await t.tap(find.byKey(Key(key)).first, warnIfMissed: false);
      await wait(700);
    }

    // ---------- first launch ----------
    await step('splash', () async {
      await t.pumpWidget(await buildApp(seed: const AppData(), splash: true));
      await wait(500);
      await shot('01_splash');
      await wait(1500);
      await shot('02_onboarding');
      await tapKey('onboarding_next');
      await wait(1200);
      await shot('03_onboarding_demo');
      await t.tap(find.text('Skip'));
      await wait(800);
      await tapKey('age_yes');
      for (var i = 0; i < 5; i++) {
        await t.tap(find.descendant(of: find.byKey(Key('q$i')), matching: find.text('No')));
        await wait(150);
      }
      await shot('04_readiness');
      await tapKey('onboarding_continue');
      await wait(800);
      await shot('05_sign_in');
    });

    // ---------- seeded, signed-in user ----------
    await step('home', () async {
      final seedApp = await buildApp(splash: false, seed: AppData(
        onboarded: true,
        signedIn: true,
        ageConfirmed: true,
        profile: const UserProfile(name: 'Rameez', age: 21, weightKg: 70, heightCm: 175, goal: Goal.buildMuscle, guest: false, email: 'rameez@example.com'),
        benchmarkMs: 1.1,
        benchmarkTier: DeviceTier.standard,
        history: SampleData.history(await buildCatalogForTest(), DateTime.now()),
        labLabels: SampleData.labLabels(DateTime.now()),
        settings: const AppSettings(voice: false, testerMode: true),
      ));
      await t.pumpWidget(const SizedBox());
      await wait(300);
      await t.pumpWidget(seedApp);
      await wait(1500);
    });
    await step('home shots', () async {
      await shot('06_workout_home');
      await t.tap(find.textContaining('workouts done this week').first);
      await wait(700);
      await shot('07_coach_expanded');
    });

    await step('routines', () async {
      await tapKey('tab_routines');
      await t.tap(find.byKey(const Key('explore')));
      await wait(900);
      // save three presets so My Routines is populated
      for (var i = 0; i < 3; i++) {
        final save = find.text('Save').hitTestable();
        if (save.evaluate().isNotEmpty) {
          await t.tap(save.first);
          await wait(400);
        }
      }
      await shot('09_routines_explore');
      await tapKey('tab_routines');
      await t.tap(find.text('My Routines'));
      await wait(900);
      await shot('08_my_routines');
    });

    await step('exercises', () async {
      await tapKey('tab_exercises');
      await wait(600);
      await shot('10_exercise_library');
      await t.tap(find.byKey(const Key('card_squat')));
      await wait(2200);
      await shot('11_exercise_detail');
      await t.drag(find.byType(ListView).first, const Offset(0, -700));
      await wait(800);
      await shot('12_exercise_detail_tips');
      await t.pageBack();
      await wait(600);
    });

    Future<void> demoRun(String exerciseId, String prefix, {required bool mistakeShot}) async {
      final cat = await buildCatalogForTest();
      final def = cat.byId(exerciseId)!;
      final routine = Routine(id: 'shot_$exerciseId', name: def.name, items: [RoutineItem.defaults(def)]);
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute(builder: (_) => WorkoutRunScreen(routine: routine, demo: true)));
      await wait(700);
      await shot('${prefix}_camera_setup');
      await wait(7000);
      await shot('${prefix}_tracking');
      if (mistakeShot) {
        await t.tap(find.byKey(const Key('demo_mistake')));
        await wait(5200);
        await shot('${prefix}_correction');
      }
    }

    await step('tracking squat', () async {
      await demoRun('squat', '13_squat', mistakeShot: true);
      await tapKey('end_set');
      await wait(1200);
      await shot('16_rest');
      await t.tap(find.byTooltip('End workout'));
      await wait(600);
      await t.tap(find.text('End'));
      await wait(1500);
      await shot('17_summary');
      await tapKey('summary_done');
      await wait(800);
    });

    await step('tracking lateral raise', () async {
      await demoRun('lateral_raise', '18_lateral_raise', mistakeShot: false);
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      nav.pop();
      await wait(800);
    });

    await step('tracking plank', () async {
      await demoRun('plank', '19_plank', mistakeShot: true);
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      nav.pop();
      await wait(800);
    });

    await step('nutrition', () async {
      await tapKey('tab_nutrition');
      await wait(900);
      await shot('20_nutrition');
      await t.drag(find.byType(ListView).first, const Offset(0, -900));
      await wait(700);
      await shot('21_nutrition_meals');
      await t.drag(find.byType(ListView).first, const Offset(0, -1500));
      await wait(700);
      await shot('22_vitamins');
    });

    await step('progress', () async {
      await tapKey('tab_progress');
      await wait(1200);
      await shot('23_progress');
      await t.drag(find.byType(ListView).first, const Offset(0, -620));
      await wait(900);
      await shot('24_recover_front');
      await t.tap(find.byKey(const Key('rotate_body')));
      await wait(800);
      await shot('25_recover_back');
      await t.drag(find.byType(ListView).first, const Offset(0, -700));
      await wait(700);
      await shot('26_finished_workouts');
    });

    await step('settings and lab', () async {
      await tapKey('avatar');
      await wait(700);
      await shot('27_settings');
      await t.scrollUntilVisible(find.byKey(const Key('open_lab')), 300, scrollable: find.byType(Scrollable).first);
      await wait(400);
      await t.tap(find.byKey(const Key('open_lab')));
      await wait(1000);
      await shot('28_accuracy_lab');
      await t.pageBack();
      await wait(500);
      await t.pageBack();
      await wait(500);
    });

    await step('routine creator', () async {
      await tapKey('tab_routines');
      await t.tap(find.byKey(const Key('my_routines')));
      await wait(500);
      await tapKey('routine_creator');
      await wait(900);
      await shot('29_routine_creator');
    });
  });
}

Future<ExerciseCatalog> buildCatalogForTest() => ExerciseRepository.load();
