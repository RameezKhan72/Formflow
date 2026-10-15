import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/theme.dart';
import '../state/app_state.dart';

/// AdMob configuration (doc item 11: "set ad place").
///
/// The defaults are Google's public TEST ids, so the app is safe to run
/// before you have an AdMob account. For the Play Store build, pass your own
/// ids, for example:
///
///   flutter build appbundle \
///     --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-xxx/yyy \
///     --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-xxx/zzz \
///     --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-xxx/www
///
/// and put your AdMob *app* id in android/app/src/main/AndroidManifest.xml
/// (com.google.android.gms.ads.APPLICATION_ID) and ios/Runner/Info.plist
/// (GADApplicationIdentifier). See MONETIZATION.md.
class AdConfig {
  static const _bannerAndroid =
      String.fromEnvironment('ADMOB_BANNER_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/6300978111');
  static const _bannerIos = String.fromEnvironment('ADMOB_BANNER_IOS', defaultValue: 'ca-app-pub-3940256099942544/2934735716');
  static const _rewardedAndroid =
      String.fromEnvironment('ADMOB_REWARDED_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/5224354917');
  static const _rewardedIos =
      String.fromEnvironment('ADMOB_REWARDED_IOS', defaultValue: 'ca-app-pub-3940256099942544/1712485313');
  static const _interAndroid =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/1033173712');
  static const _interIos =
      String.fromEnvironment('ADMOB_INTERSTITIAL_IOS', defaultValue: 'ca-app-pub-3940256099942544/4411468910');

  static bool get _ios => !kIsWeb && Platform.isIOS;
  static String get banner => _ios ? _bannerIos : _bannerAndroid;
  static String get rewarded => _ios ? _rewardedIos : _rewardedAndroid;
  static String get interstitial => _ios ? _interIos : _interAndroid;

  /// Show at most one interstitial per this many finished workouts.
  static const interstitialEvery = 2;
}

/// Where a banner sits; used for analytics-free placement and tests.
enum AdPlacement { library, detail, nutrition, progress, summary }

/// Ads used by the app. [NoAdsService] is used in tests and when the ad SDK
/// is not available; [AdMobService] on phones.
abstract class AdsService {
  Future<void> init();

  /// True when real ads can be requested.
  bool get live;

  /// Shows a rewarded ad; completes with true when the user earned it.
  Future<bool> showRewarded();

  /// Shows an interstitial if one is ready (never blocks the flow).
  Future<void> showInterstitial();

  Widget buildBanner(AdPlacement placement);
}

/// No network ads: reserves the slot with a neutral placeholder so layouts
/// keep their final shape, and grants rewards immediately (tests, demos).
class NoAdsService implements AdsService {
  final bool grantRewards;
  const NoAdsService({this.grantRewards = true});

  @override
  Future<void> init() async {}

  @override
  bool get live => false;

  @override
  Future<bool> showRewarded() async => grantRewards;

  @override
  Future<void> showInterstitial() async {}

  @override
  Widget buildBanner(AdPlacement placement) => const AdPlaceholder();
}

class AdMobService implements AdsService {
  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  bool _ready = false;

  @override
  bool get live => _ready;

  /// Google UMP consent (required for users in the EEA/UK) before ads.
  Future<void> _gatherConsent() {
    final done = Completer<void>();
    void finish([Object? _]) {
      if (!done.isCompleted) done.complete();
    }

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired(finish),
        finish,
      );
    } catch (_) {
      finish();
    }
    return done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  }

  @override
  Future<void> init() async {
    try {
      await _gatherConsent();
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      _ready = true;
      _loadRewarded();
      _loadInterstitial();
    } catch (_) {
      _ready = false; // no ads rather than a crash
    }
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: AdConfig.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdConfig.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  @override
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (!_ready || ad == null) {
      _loadRewarded();
      return false;
    }
    _rewarded = null;
    final done = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return done.future;
  }

  @override
  Future<void> showInterstitial() async {
    final ad = _interstitial;
    if (!_ready || ad == null) {
      _loadInterstitial();
      return;
    }
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _loadInterstitial();
      },
    );
    await ad.show();
  }

  @override
  Widget buildBanner(AdPlacement placement) => _ready ? _AdMobBanner(key: ValueKey(placement)) : const AdPlaceholder();
}

class _AdMobBanner extends StatefulWidget {
  const _AdMobBanner({super.key});

  @override
  State<_AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<_AdMobBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: AdConfig.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const AdPlaceholder();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}

/// Reserved 320x50 ad space ("Ad" label) shown until a banner loads.
class AdPlaceholder extends StatelessWidget {
  const AdPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ad_slot'),
      height: 50,
      width: 320,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: FF.surface2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FF.outline),
      ),
      child: const Text('Ad', style: TextStyle(color: FF.muted, fontSize: 11, letterSpacing: 1.2)),
    );
  }
}

/// Overridden in main() with [AdMobService]; tests keep the placeholder.
final adsProvider = Provider<AdsService>((ref) => const NoAdsService());

/// Banner slot that disappears for Premium users.
class AdBanner extends ConsumerWidget {
  final AdPlacement placement;
  final EdgeInsets padding;
  const AdBanner(this.placement, {super.key, this.padding = const EdgeInsets.symmetric(vertical: 8)});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    if (!app.showAds) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Center(child: ref.watch(adsProvider).buildBanner(placement)),
    );
  }
}
