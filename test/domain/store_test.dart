import 'package:flutter_test/flutter_test.dart';
import 'package:formflow/data/app_store.dart';
import 'package:formflow/domain/feedback.dart';
import 'package:formflow/domain/insights.dart';
import 'package:formflow/domain/profile.dart';
import 'package:formflow/domain/routine.dart';
import 'package:formflow/domain/sample_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('everything round-trips through the local store (FR-CL-01)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.open();
    final cat = loadCatalog();
    final data = AppData(
      onboarded: true,
      signedIn: true,
      ageConfirmed: true,
      profile: const UserProfile(name: 'Rameez', goal: Goal.cutting, weeklyTarget: 4),
      settings: const AppSettings(voice: false, repSpeech: RepSpeech.every, testerMode: true),
      routines: [RoutinePresets.all(cat).first],
      history: SampleData.history(cat, DateTime(2026, 10, 10)),
      favourites: const {'squat', 'plank'},
      labLabels: [LabLabel('squat', true, true, DateTime(2026))],
      benchmarkTier: DeviceTier.standard,
      benchmarkMs: 1.5,
    );
    await store.save(data);
    final back = AppStore(await SharedPreferences.getInstance()).load();
    expect(back.onboarded, isTrue);
    expect(back.profile.name, 'Rameez');
    expect(back.profile.goal, Goal.cutting);
    expect(back.settings.voice, isFalse);
    expect(back.settings.repSpeech, RepSpeech.every);
    expect(back.routines.single.name, data.routines.single.name);
    expect(back.history.length, data.history.length);
    expect(back.favourites, {'squat', 'plank'});
    expect(back.labLabels, hasLength(1));
    expect(back.benchmarkTier, DeviceTier.standard);
    expect(back.tier, DeviceTier.standard);
  });

  test('corrupt stored values are ignored, not fatal (NFR-RL-02)', () async {
    SharedPreferences.setMockInitialValues({
      'formflow.v1.history': '{not json',
      'formflow.v1.profile': '"just a string"',
      'formflow.v1.routines': '[{"id": 1}]',
    });
    final store = await AppStore.open();
    final d = store.load();
    expect(d.history, isEmpty);
    expect(d.routines, isEmpty);
    expect(d.profile.name, 'Athlete');
  });

  test('clearAll deletes all app data (FR-AU-09)', () async {
    SharedPreferences.setMockInitialValues({'formflow.v1.flags': '{"onboarded": true}', 'other.key': 'x'});
    final store = await AppStore.open();
    await store.clearAll();
    expect(store.load().onboarded, isFalse);
    expect(store.prefs.getString('other.key'), 'x');
  });

  test('performance override beats the benchmark', () {
    const d = AppData(settings: AppSettings(performance: 'lite'), benchmarkTier: DeviceTier.high);
    expect(d.tier, DeviceTier.lite);
  });
}
