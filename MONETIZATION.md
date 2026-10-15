# Premium, ads and owner access

FormFlow 2.0 is free with ads. 21 exercises are free; 35 "PRO" exercises need
**FormFlow Premium** (one purchase, removes all ads) or a **rewarded ad**
(watch one short ad, that exercise is unlocked for 24 hours).

## Where ads appear (free users only)

| Placement | Type | File |
|---|---|---|
| Exercise library (between sections / after 6 results) | Banner 320x50 | `lib/features/exercises/exercises_tab.dart` |
| Exercise detail (above the Start button) | Banner | `lib/features/exercises/exercise_detail_screen.dart` |
| Nutrition tab | Banner | `lib/features/nutrition/nutrition_tab.dart` |
| Progress tab (above Finished workouts) | Banner | `lib/features/progress/progress_tab.dart` |
| Workout summary | Banner + interstitial every 2nd finished workout | `lib/features/tracking/summary_screen.dart` |
| Unlock a PRO exercise | Rewarded ad | `lib/features/premium/premium_screen.dart` |

Ads never show on the camera / tracking screen. Premium and owner access hide
every ad slot. Until an ad loads the slot shows a small "Ad" placeholder.

## 1. AdMob (ads)

1. Create an AdMob account at admob.google.com and add two apps (Android and iOS).
2. Create ad units: **Banner**, **Rewarded**, **Interstitial** (for each platform).
3. Put your **app ids** in:
   - `android/app/src/main/AndroidManifest.xml` → `com.google.android.gms.ads.APPLICATION_ID`
   - `ios/Runner/Info.plist` → `GADApplicationIdentifier`
4. Pass your **ad unit ids** when you build (no code change needed):

```bash
flutter build appbundle --release \
  --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-XXXX/BBBB \
  --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-XXXX/RRRR \
  --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-XXXX/IIII \
  --dart-define=OWNER_CODE=your-private-code
```

iOS uses `ADMOB_BANNER_IOS`, `ADMOB_REWARDED_IOS`, `ADMOB_INTERSTITIAL_IOS`.
The defaults in `lib/services/ads_service.dart` are Google's public **test**
ids, so development builds are safe. Never click your own live ads.

The app asks for ad consent with Google's UMP form (required in the EEA/UK)
before loading ads. Create the consent message in AdMob → Privacy & messaging.

## 2. FormFlow Premium (in-app purchase)

1. Google Play Console → your app → Monetize → Products → **In-app products**
   → create `formflow_premium` (non-consumable, one-time price you choose).
   (App Store Connect: create a Non-Consumable with the same id.)
2. Upload a build to an internal testing track first; purchases only work
   for apps installed from Play.
3. The id can be changed with `--dart-define=PREMIUM_PRODUCT_ID=...`.

"Restore purchases" is on the Premium screen. Purchase handling is in
`lib/services/purchase_service.dart`. For a subscription instead of a
one-time purchase, create a subscription with the same id; the code works
unchanged, but add server-side receipt checks before scaling up.

## 3. Owner access (only you)

Settings → **Owner access** → enter your owner code → every exercise is
unlocked and no ads are shown on that phone. Set your private code at build
time with `--dart-define=OWNER_CODE=...` (the default is
`FORMFLOW-OWNER-2026`; change it before release). Only a hash is compared.

## 4. Store declarations

- Google Play: Policy → App content → **Ads: Yes**.
- Data safety: the camera is processed on the device and never uploaded;
  AdMob collects device / advertising ids (declare "Advertising or marketing").
- The app has an 18+ gate, so set the target audience to adults.
