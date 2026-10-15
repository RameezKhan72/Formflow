import 'exercise.dart';

/// What the user may use (doc item 11): free exercises for everyone, all
/// exercises with FormFlow Premium (purchase) or the owner code, and a
/// single premium exercise for [rewardUnlock] after watching a rewarded ad.
/// Premium users see no ads.
class Entitlements {
  /// How long one rewarded ad unlocks a premium exercise.
  static const rewardUnlock = Duration(hours: 24);

  final bool premium;
  final bool owner;
  final Map<String, DateTime> unlocked;

  const Entitlements({this.premium = false, this.owner = false, this.unlocked = const {}});

  bool get isPremium => premium || owner;

  /// Ads are only shown to free users.
  bool get showAds => !isPremium;

  bool isUnlocked(String id, DateTime now) {
    final until = unlocked[id];
    return until != null && until.isAfter(now);
  }

  bool canUse(ExerciseDef e, DateTime now) => !e.premium || isPremium || isUnlocked(e.id, now);

  /// Time left on an ad unlock, or null.
  Duration? remaining(String id, DateTime now) {
    final until = unlocked[id];
    if (until == null || !until.isAfter(now)) return null;
    return until.difference(now);
  }

  Entitlements unlock(String id, DateTime now) {
    final m = <String, DateTime>{
      for (final e in unlocked.entries)
        if (e.value.isAfter(now)) e.key: e.value,
    };
    m[id] = now.add(rewardUnlock);
    return Entitlements(premium: premium, owner: owner, unlocked: m);
  }

  Entitlements copyWith({bool? premium, bool? owner}) =>
      Entitlements(premium: premium ?? this.premium, owner: owner ?? this.owner, unlocked: unlocked);

  Map<String, dynamic> toJson() => {
        'premium': premium,
        'owner': owner,
        'unlocked': unlocked.map((k, v) => MapEntry(k, v.toIso8601String())),
      };

  factory Entitlements.fromJson(Map<String, dynamic> j) {
    final u = <String, DateTime>{};
    final raw = j['unlocked'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final d = v is String ? DateTime.tryParse(v) : null;
        if (k is String && d != null) u[k] = d;
      });
    }
    return Entitlements(
      premium: (j['premium'] as bool?) ?? false,
      owner: (j['owner'] as bool?) ?? false,
      unlocked: u,
    );
  }
}

/// Owner access ("only I have access to everything"): the owner types a
/// private code in Settings > About. The code is set at build time with
/// `--dart-define=OWNER_CODE=...`; only a hash is compared at runtime.
class OwnerCode {
  static const _configured = String.fromEnvironment('OWNER_CODE', defaultValue: 'FORMFLOW-OWNER-2026');

  /// 32-bit FNV-1a of the normalised code.
  static int hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.trim().toUpperCase().codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static bool check(String input, {String? expected}) => input.trim().isNotEmpty && hash(input) == hash(expected ?? _configured);
}
