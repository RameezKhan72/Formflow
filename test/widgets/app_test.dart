import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/data/app_store.dart';
import 'package:formflow/domain/insights.dart';
import 'package:formflow/domain/profile.dart';
import 'package:formflow/domain/sample_data.dart';
import 'package:formflow/features/exercises/exercise_detail_screen.dart';
import 'package:formflow/features/settings/profile_sheet.dart';
import 'package:formflow/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

AppData signedIn({Goal goal = Goal.buildMuscle}) => AppData(
      onboarded: true,
      signedIn: true,
      ageConfirmed: true,
      profile: UserProfile(name: 'Rameez', age: 21, weightKg: 70, heightCm: 175, goal: goal, activityFactor: 1.55),
      benchmarkMs: 1.2,
      benchmarkTier: DeviceTier.standard,
      history: SampleData.history(loadCatalog(), DateTime.now()),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('signed-in user lands on the Workout tab and can visit every tab', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final app = await t.runAsync(() => buildApp(seed: signedIn(), useStore: false, splash: false));
    await t.pumpWidget(app!);
    await settle(t);
    expect(find.byKey(const Key('start_workout')), findsOneWidget);
    expect(find.textContaining('Your next workout'), findsWidgets);

    for (final tab in ['tab_routines', 'tab_exercises', 'tab_nutrition', 'tab_progress', 'tab_workout']) {
      await t.tap(find.byKey(Key(tab)));
      await settle(t, 400);
      expect(t.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('nutrition shows the TC-29 calorie target for cutting', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final app = await t.runAsync(() => buildApp(seed: signedIn(goal: Goal.cutting), useStore: false, splash: false));
    await t.pumpWidget(app!);
    await settle(t);
    await t.tap(find.byKey(const Key('tab_nutrition')));
    await settle(t, 800);
    final kcal = t.widget<Text>(find.byKey(const Key('kcal_target')));
    expect(int.parse(kcal.data!), closeTo(2232, 1));
  });

  testWidgets('declining the age gate blocks onboarding (TC-28)', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final app = await t.runAsync(() => buildApp(seed: const AppData(), useStore: false, splash: false));
    await t.pumpWidget(app!);
    await settle(t);
    expect(find.text('Your pocket form coach'), findsOneWidget);
    await t.tap(find.text('Skip'));
    await settle(t);
    await t.tap(find.byKey(const Key('age_no')));
    await settle(t, 300);
    expect(find.textContaining('designed for adults'), findsOneWidget);
    final btn = t.widget<FilledButton>(find.byKey(const Key('onboarding_continue')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('sign-up rejects an invalid email with a message (FR-AU-03)', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final app = await t.runAsync(() => buildApp(seed: const AppData(onboarded: true, ageConfirmed: true), useStore: false, splash: false));
    await t.pumpWidget(app!);
    await settle(t);
    await t.enterText(find.byKey(const Key('auth_name')), 'Rameez');
    await t.enterText(find.byKey(const Key('auth_email')), 'not-an-email');
    await t.enterText(find.byKey(const Key('auth_password')), '123456');
    await t.tap(find.byKey(const Key('auth_submit')));
    await settle(t);
    expect(find.textContaining("doesn't look right"), findsOneWidget);
  });

  testWidgets('exercise library: filter bar on top, muscle sections, filters (doc items 5, 7, 8)', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final app = await t.runAsync(() => buildApp(seed: signedIn(), useStore: false, splash: false));
    await t.pumpWidget(app!);
    await settle(t);
    await t.tap(find.byKey(const Key('tab_exercises')));
    await settle(t, 400);
    for (final k in ['filter_equipment', 'filter_muscle', 'filter_type']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.byKey(const Key('section_chest')), findsOneWidget);
    expect(find.byKey(const Key('premium_banner')), findsOneWidget);
    // equipment filter -> dumbbell exercises only
    await t.tap(find.byKey(const Key('filter_equipment')));
    await settle(t, 400);
    await t.tap(find.byKey(const Key('pick_dumbbells')));
    await settle(t, 400);
    expect(find.byKey(const Key('library_results')), findsOneWidget);
    expect(find.byKey(const Key('ex_dumbbell_floor_press')), findsOneWidget);
    expect(find.byKey(const Key('ex_push_up')), findsNothing);
    await t.tap(find.byKey(const Key('clear_filters')));
    await settle(t, 300);
    expect(find.byKey(const Key('library_sections')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('home muscle tile opens that library section', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final app = await t.runAsync(() => buildApp(seed: signedIn(), useStore: false, splash: false));
    await t.pumpWidget(app!);
    await settle(t);
    await t.tap(find.byKey(const Key('muscle_tile_glutes')));
    await settle(t, 400);
    expect(find.byKey(const Key('library_results')), findsOneWidget);
    expect(find.byKey(const Key('ex_hip_thrust')), findsOneWidget);
    expect(find.byKey(const Key('ex_squat')), findsNothing);
  });

  testWidgets('premium exercise is locked until a rewarded ad unlocks it (doc item 11)', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final app = await t.runAsync(() => buildApp(seed: signedIn(), useStore: false, splash: false));
    await t.pumpWidget(app!);
    await settle(t);
    await t.tap(find.byKey(const Key('tab_exercises')));
    await settle(t, 400);
    await t.enterText(find.byKey(const Key('exercise_search')), 'V-up');
    await settle(t, 300);
    await t.tap(find.byKey(const Key('ex_v_up')));
    await settle(t, 600);
    expect(find.byKey(const Key('locked_card')), findsOneWidget);
    final detailList = find.descendant(of: find.byType(ExerciseDetailScreen), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(find.byKey(const Key('common_mistakes')), 300, scrollable: detailList);
    expect(find.byKey(const Key('common_mistakes')), findsOneWidget);
    expect(find.byKey(const Key('start_camera')), findsNothing);
    await t.scrollUntilVisible(find.byKey(const Key('unlock_exercise')), 300, scrollable: detailList);
    await t.tap(find.byKey(const Key('unlock_exercise')));
    await settle(t, 600);
    expect(find.text('FormFlow Premium'), findsWidgets);
    await t.tap(find.byKey(const Key('watch_ad_unlock')));
    await settle(t, 600);
    // back on the detail screen, now unlocked
    expect(find.byKey(const Key('locked_card')), findsNothing);
    await t.scrollUntilVisible(find.byKey(const Key('start_camera')), 300,
        scrollable: find.descendant(of: find.byType(ExerciseDetailScreen), matching: find.byType(Scrollable)).first);
    expect(find.byKey(const Key('start_camera')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('owner code gives full access and hides ads', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final app = await t.runAsync(() => buildApp(seed: signedIn(), useStore: false, splash: false));
    await t.pumpWidget(app!);
    await settle(t);
    expect(find.byKey(const Key('premium_button')), findsOneWidget);
    await t.tap(find.byKey(const Key('avatar')));
    await settle(t, 600);
    await t.scrollUntilVisible(find.text('Owner access'), 300,
        scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    await t.tap(find.text('Owner access'));
    await settle(t, 400);
    await t.enterText(find.byKey(const Key('owner_code_field')), 'formflow-owner-2026');
    await t.tap(find.byKey(const Key('owner_code_ok')));
    await settle(t, 600);
    expect(find.textContaining('Owner access on'), findsOneWidget);
    await t.pageBack();
    await settle(t, 600);
    expect(find.byKey(const Key('premium_button')), findsNothing);
    await t.tap(find.byKey(const Key('tab_exercises')));
    await settle(t, 400);
    expect(find.byKey(const Key('premium_banner')), findsNothing);
    expect(find.byKey(const Key('ad_slot')), findsNothing);
  });
}
