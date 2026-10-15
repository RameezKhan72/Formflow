import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entitlements.dart';
import '../domain/exercise.dart';
import '../domain/feedback.dart';
import '../domain/history.dart';
import '../domain/insights.dart';
import '../domain/profile.dart';
import '../domain/routine.dart';

class AppSettings {
  final bool voice;
  final double volume;
  final RepSpeech repSpeech;
  final bool haptics;
  final bool frontCamera;
  final String performance; // auto | lite | standard | high
  final bool reduceMotion;
  final bool testerMode;
  final String voiceStyle; // coach | calm
  final bool reminders;

  const AppSettings({
    this.voice = true,
    this.volume = 1.0,
    this.repSpeech = RepSpeech.everyFifth,
    this.haptics = true,
    this.frontCamera = true,
    this.performance = 'auto',
    this.reduceMotion = false,
    this.testerMode = false,
    this.voiceStyle = 'coach',
    this.reminders = false,
  });

  AppSettings copyWith({
    bool? voice,
    double? volume,
    RepSpeech? repSpeech,
    bool? haptics,
    bool? frontCamera,
    String? performance,
    bool? reduceMotion,
    bool? testerMode,
    String? voiceStyle,
    bool? reminders,
  }) =>
      AppSettings(
        voice: voice ?? this.voice,
        volume: volume ?? this.volume,
        repSpeech: repSpeech ?? this.repSpeech,
        haptics: haptics ?? this.haptics,
        frontCamera: frontCamera ?? this.frontCamera,
        performance: performance ?? this.performance,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        testerMode: testerMode ?? this.testerMode,
        voiceStyle: voiceStyle ?? this.voiceStyle,
        reminders: reminders ?? this.reminders,
      );

  Map<String, dynamic> toJson() => {
        'voice': voice,
        'volume': volume,
        'repSpeech': repSpeech.name,
        'haptics': haptics,
        'frontCamera': frontCamera,
        'performance': performance,
        'reduceMotion': reduceMotion,
        'testerMode': testerMode,
        'voiceStyle': voiceStyle,
        'reminders': reminders,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        voice: (j['voice'] as bool?) ?? true,
        volume: (j['volume'] as num?)?.toDouble() ?? 1,
        repSpeech: RepSpeech.values.firstWhere((r) => r.name == j['repSpeech'], orElse: () => RepSpeech.everyFifth),
        haptics: (j['haptics'] as bool?) ?? true,
        frontCamera: (j['frontCamera'] as bool?) ?? true,
        performance: (j['performance'] as String?) ?? 'auto',
        reduceMotion: (j['reduceMotion'] as bool?) ?? false,
        testerMode: (j['testerMode'] as bool?) ?? false,
        voiceStyle: (j['voiceStyle'] as String?) ?? 'coach',
        reminders: (j['reminders'] as bool?) ?? false,
      );
}

/// Snapshot of everything stored on the device. Offline-first: the local
/// store is the source of truth (FR-CL-01).
class AppData {
  final bool onboarded;
  final bool signedIn;
  final bool ageConfirmed;
  final bool readinessFlag;
  final UserProfile profile;
  final AppSettings settings;
  final List<Routine> routines;
  final String activeRoutineId;
  final List<WorkoutSession> history;
  final Set<String> favourites;
  final Set<String> savedPresets;
  final List<LabLabel> labLabels;
  final BodyProfileResult? bodyProfile;
  final DeviceTier? benchmarkTier;
  final double? benchmarkMs;
  final Map<String, dynamic>? resumeState;
  final Entitlements entitlements;

  const AppData({
    this.onboarded = false,
    this.signedIn = false,
    this.ageConfirmed = false,
    this.readinessFlag = false,
    this.profile = const UserProfile(),
    this.settings = const AppSettings(),
    this.routines = const [],
    this.activeRoutineId = 'weekly',
    this.history = const [],
    this.favourites = const {},
    this.savedPresets = const {},
    this.labLabels = const [],
    this.bodyProfile,
    this.benchmarkTier,
    this.benchmarkMs,
    this.resumeState,
    this.entitlements = const Entitlements(),
  });

  AppData copyWith({
    bool? onboarded,
    bool? signedIn,
    bool? ageConfirmed,
    bool? readinessFlag,
    UserProfile? profile,
    AppSettings? settings,
    List<Routine>? routines,
    String? activeRoutineId,
    List<WorkoutSession>? history,
    Set<String>? favourites,
    Set<String>? savedPresets,
    List<LabLabel>? labLabels,
    BodyProfileResult? bodyProfile,
    bool clearBodyProfile = false,
    DeviceTier? benchmarkTier,
    double? benchmarkMs,
    Map<String, dynamic>? resumeState,
    bool clearResume = false,
    Entitlements? entitlements,
  }) =>
      AppData(
        onboarded: onboarded ?? this.onboarded,
        signedIn: signedIn ?? this.signedIn,
        ageConfirmed: ageConfirmed ?? this.ageConfirmed,
        readinessFlag: readinessFlag ?? this.readinessFlag,
        profile: profile ?? this.profile,
        settings: settings ?? this.settings,
        routines: routines ?? this.routines,
        activeRoutineId: activeRoutineId ?? this.activeRoutineId,
        history: history ?? this.history,
        favourites: favourites ?? this.favourites,
        savedPresets: savedPresets ?? this.savedPresets,
        labLabels: labLabels ?? this.labLabels,
        bodyProfile: clearBodyProfile ? null : (bodyProfile ?? this.bodyProfile),
        benchmarkTier: benchmarkTier ?? this.benchmarkTier,
        benchmarkMs: benchmarkMs ?? this.benchmarkMs,
        resumeState: clearResume ? null : (resumeState ?? this.resumeState),
        entitlements: entitlements ?? this.entitlements,
      );

  DeviceTier get tier {
    switch (settings.performance) {
      case 'lite':
        return DeviceTier.lite;
      case 'standard':
        return DeviceTier.standard;
      case 'high':
        return DeviceTier.high;
      default:
        return benchmarkTier ?? DeviceTier.standard;
    }
  }
}

/// SharedPreferences-backed persistence. Every read is defensive so that
/// malformed data is ignored rather than fatal (NFR-RL-02).
class AppStore {
  static const _k = 'formflow.v1.';
  final SharedPreferences prefs;
  AppStore(this.prefs);

  static Future<AppStore> open() async => AppStore(await SharedPreferences.getInstance());

  dynamic _json(String key) {
    try {
      final s = prefs.getString('$_k$key');
      return s == null ? null : jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> _put(String key, Object? value) async {
    try {
      if (value == null) {
        await prefs.remove('$_k$key');
      } else {
        await prefs.setString('$_k$key', jsonEncode(value));
      }
    } catch (_) {
      // Storage failures never crash the app (NFR-RL-01).
    }
  }

  AppData load() {
    final flags = (_json('flags') as Map<String, dynamic>?) ?? const {};
    final profileJ = _json('profile');
    final settingsJ = _json('settings');
    final bp = _json('bodyProfile') as Map<String, dynamic>?;
    return AppData(
      onboarded: (flags['onboarded'] as bool?) ?? false,
      signedIn: (flags['signedIn'] as bool?) ?? false,
      ageConfirmed: (flags['ageConfirmed'] as bool?) ?? false,
      readinessFlag: (flags['readinessFlag'] as bool?) ?? false,
      activeRoutineId: (flags['activeRoutineId'] as String?) ?? 'weekly',
      benchmarkTier: DeviceTier.values.where((t) => t.name == flags['tier']).firstOrNull,
      benchmarkMs: (flags['benchMs'] as num?)?.toDouble(),
      profile: profileJ is Map<String, dynamic> ? UserProfile.fromJson(profileJ) : const UserProfile(),
      settings: settingsJ is Map<String, dynamic> ? AppSettings.fromJson(settingsJ) : const AppSettings(),
      routines: ((_json('routines') as List?) ?? const []).map(Routine.tryParse).whereType<Routine>().toList(),
      history: ((_json('history') as List?) ?? const []).map(WorkoutSession.tryParse).whereType<WorkoutSession>().toList(),
      favourites: ((_json('favourites') as List?) ?? const []).whereType<String>().toSet(),
      savedPresets: ((_json('savedPresets') as List?) ?? const []).whereType<String>().toSet(),
      labLabels: ((_json('lab') as List?) ?? const []).map(LabLabel.tryParse).whereType<LabLabel>().toList(),
      bodyProfile: bp == null
          ? null
          : BodyProfileResult(
              ((bp['ratios'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
              (bp['symmetry'] as num?)?.toDouble() ?? 0,
              (bp['quality'] as num?)?.toInt() ?? 0,
              const [],
            ),
      resumeState: _json('resume') as Map<String, dynamic>?,
      entitlements: _json('entitlements') is Map<String, dynamic>
          ? Entitlements.fromJson(_json('entitlements') as Map<String, dynamic>)
          : const Entitlements(),
    );
  }

  Future<void> save(AppData d) async {
    await _put('flags', {
      'onboarded': d.onboarded,
      'signedIn': d.signedIn,
      'ageConfirmed': d.ageConfirmed,
      'readinessFlag': d.readinessFlag,
      'activeRoutineId': d.activeRoutineId,
      'tier': d.benchmarkTier?.name,
      'benchMs': d.benchmarkMs,
    });
    await _put('profile', d.profile.toJson());
    await _put('settings', d.settings.toJson());
    await _put('routines', d.routines.map((r) => r.toJson()).toList());
    await _put('history', d.history.map((s) => s.toJson()).toList());
    await _put('favourites', d.favourites.toList());
    await _put('savedPresets', d.savedPresets.toList());
    await _put('lab', d.labLabels.map((l) => l.toJson()).toList());
    await _put('bodyProfile', d.bodyProfile?.toJson());
    await _put('resume', d.resumeState);
    await _put('entitlements', d.entitlements.toJson());
  }

  Future<void> clearAll() async {
    for (final k in prefs.getKeys().where((k) => k.startsWith(_k)).toList()) {
      await prefs.remove(k);
    }
  }
}

class ExerciseRepository {
  static Future<ExerciseCatalog> load([AssetBundle? bundle]) async {
    final s = await (bundle ?? rootBundle).loadString('assets/data/exercises.json');
    return ExerciseCatalog.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }
}
