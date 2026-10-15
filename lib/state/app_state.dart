import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../domain/entitlements.dart';
import '../domain/exercise.dart';
import '../domain/history.dart';
import '../domain/insights.dart';
import '../domain/profile.dart';
import '../domain/routine.dart';
import '../domain/rules.dart';
import '../domain/sample_data.dart';

/// Overridden at start-up with the loaded catalog.
final catalogProvider = Provider<ExerciseCatalog>((ref) => throw UnimplementedError('catalog not loaded'));

/// Overridden at start-up with the controller.
final appProvider = ChangeNotifierProvider<AppController>((ref) => throw UnimplementedError('app not loaded'));

final cueBookProvider = Provider<CueBook>((ref) => CueBook(ref.watch(catalogProvider).cues));

/// Clock that tests and screenshots can freeze.
DateTime Function() appClock = DateTime.now;

class AppController extends ChangeNotifier {
  final AppStore? store;
  final ExerciseCatalog catalog;
  AppData _data;

  AppController(this._data, this.catalog, {this.store});

  AppData get data => _data;
  UserProfile get profile => _data.profile;
  AppSettings get settings => _data.settings;

  void _set(AppData d) {
    _data = d;
    notifyListeners();
    store?.save(d);
  }

  // ---- onboarding / account (FR-AU) ----
  void completeOnboarding({required bool readinessFlag}) =>
      _set(_data.copyWith(onboarded: true, ageConfirmed: true, readinessFlag: readinessFlag));

  void signIn({required String name, required String email, required bool guest}) {
    _set(_data.copyWith(
      signedIn: true,
      profile: _data.profile.copyWith(name: name, email: email, guest: guest),
    ));
  }

  void updateProfile(UserProfile p) => _set(_data.copyWith(profile: p));
  void updateSettings(AppSettings s) => _set(_data.copyWith(settings: s));
  void setBenchmark(double ms) =>
      _set(_data.copyWith(benchmarkMs: ms, benchmarkTier: DeviceTierX.fromBenchmark(ms)));

  void logOut() => _set(_data.copyWith(signedIn: false));

  /// In-app account and data deletion (FR-AU-09, FR-CL-05).
  Future<void> deleteAccount() async {
    await store?.clearAll();
    _data = const AppData();
    notifyListeners();
  }

  // ---- routines (FR-RT-04) ----
  List<Routine> get myRoutines => _data.routines;

  Routine? routineById(String id) {
    for (final r in [..._data.routines, ...RoutinePresets.all(catalog)]) {
      if (r.id == id) return r;
    }
    return null;
  }

  void saveRoutine(Routine r) {
    final list = [..._data.routines];
    final i = list.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      list[i] = r;
    } else {
      list.add(r);
    }
    _set(_data.copyWith(routines: list));
  }

  void deleteRoutine(String id) => _set(_data.copyWith(routines: _data.routines.where((r) => r.id != id).toList()));

  Routine duplicateRoutine(Routine r) {
    final copy = r.copyWith(id: 'user_${DateTime.now().microsecondsSinceEpoch}', name: '${r.name} (copy)', source: 'user');
    saveRoutine(copy);
    return copy;
  }

  void togglePresetSaved(Routine preset) {
    final s = {..._data.savedPresets};
    if (!s.remove(preset.id)) {
      s.add(preset.id);
      if (!_data.routines.any((r) => r.id == preset.id)) {
        _data = _data.copyWith(routines: [..._data.routines, preset]);
      }
    } else {
      _data = _data.copyWith(routines: _data.routines.where((r) => r.id != preset.id).toList());
    }
    _set(_data.copyWith(savedPresets: s));
  }

  void setActivePlan(String id) => _set(_data.copyWith(activeRoutineId: id));

  /// Today's routine from the active plan (weekly schedule by default).
  Routine? todaysRoutine(DateTime now) {
    if (_data.activeRoutineId != 'weekly') return routineById(_data.activeRoutineId);
    final id = RoutinePresets.weekly[now.weekday % 7];
    return id == null ? null : routineById(id);
  }

  Routine nextRoutine(DateTime now) {
    for (var i = 0; i < 7; i++) {
      final r = todaysRoutine(now.add(Duration(days: i)));
      if (r != null) return r;
    }
    return RoutinePresets.all(catalog).first;
  }

  // ---- favourites ----
  void toggleFavourite(String exerciseId) {
    final f = {..._data.favourites};
    if (!f.remove(exerciseId)) f.add(exerciseId);
    _set(_data.copyWith(favourites: f));
  }

  // ---- history (FR-PG-01) ----
  void addSession(WorkoutSession s) => _set(_data.copyWith(history: [..._data.history, s], clearResume: true));

  void saveResume(Map<String, dynamic>? state) =>
      _set(state == null ? _data.copyWith(clearResume: true) : _data.copyWith(resumeState: state));

  // ---- lab (FR-TL) ----
  void addLabel(LabLabel l) => _set(_data.copyWith(labLabels: [..._data.labLabels, l]));
  void clearLab() => _set(_data.copyWith(labLabels: const []));

  // ---- body profile (FR-CB-05) ----
  void saveBodyProfile(BodyProfileResult r) => _set(_data.copyWith(bodyProfile: r));
  void deleteBodyProfile() => _set(_data.copyWith(clearBodyProfile: true));

  // ---- premium and ads (doc item 11) ----
  Entitlements get entitlements => _data.entitlements;
  bool get isPremium => _data.entitlements.isPremium;
  bool get showAds => _data.entitlements.showAds;

  bool canUse(ExerciseDef e) => _data.entitlements.canUse(e, appClock());

  /// Exercises of a routine that are still locked for this user.
  List<ExerciseDef> lockedIn(Iterable<String> exerciseIds) => [
        for (final id in exerciseIds)
          if (catalog.byId(id) case final e? when !canUse(e)) e,
      ];

  /// Rewarded ad watched: unlock one premium exercise for 24 hours.
  void unlockWithReward(String exerciseId) =>
      _set(_data.copyWith(entitlements: _data.entitlements.unlock(exerciseId, appClock())));

  void setPremium(bool on) => _set(_data.copyWith(entitlements: _data.entitlements.copyWith(premium: on)));

  /// Owner access: returns true when the code matches.
  bool ownerUnlock(String code) {
    if (!OwnerCode.check(code)) return false;
    _set(_data.copyWith(entitlements: _data.entitlements.copyWith(owner: true)));
    return true;
  }

  void ownerLock() => _set(_data.copyWith(entitlements: _data.entitlements.copyWith(owner: false)));

  // ---- sample data ----
  void loadSampleData() {
    final now = appClock();
    _set(_data.copyWith(
      history: SampleData.history(catalog, now),
      labLabels: SampleData.labLabels(now),
    ));
  }

  void clearHistory() => _set(_data.copyWith(history: const []));
}
