# FormFlow

AI form coach for **Android and iOS**, built in Flutter: real-time exercise form correction with the camera, realistic 3D muscle demonstrations, 56 exercises in 8 muscle sections, nutrition and progress tracking. Version 2.0.

## What is new in 2.0

| Area | What changed |
|---|---|
| Exercises | 56 exercises (was 20) in 8 sections: Chest, Back, Shoulders, Arms, Abs & Core, Legs, Glutes, Cardio. 21 free, 35 PRO |
| Library | Filter bar on top (Equipment, Muscle, Type), one carousel per body part, search, favourites, "See all" per section |
| Common mistakes | Every exercise lists its common mistakes with how to fix each one |
| 3D demonstrations | Re-rendered for all 56 exercises: the figure stands on a lit floor with contact shadows, hands and feet are planted with IK, hanging moves use a pull-up frame. Small looping videos (~1.5 MB for all) |
| Pose estimation | Each exercise tracks only its target joints (e.g. curls: shoulder, elbow, wrist); face, hands and other limbs are ignored for side choice, framing and the skeleton overlay |
| Camera distance | Upper-body exercises work from about 1 m (head to hips in view); standing full-body ~1.5 m; floor exercises ~1.8 m. The setup check adapts to each exercise |
| Premium | FormFlow Premium (in-app purchase) unlocks everything and removes ads; a rewarded ad unlocks one PRO exercise for 24 h; owner code for you. See MONETIZATION.md |
| Ads | AdMob banner slots, rewarded and interstitial ads with Google consent (UMP); test ids by default |
| Look | New logo and icons, animated gym splash, simpler home with "Train by muscle" shortcuts, cleaner navigation |
| Platforms | Android + iOS (Podfile, Info.plist and icons included). See PLAYSTORE.md |

## Everything else (from 1.x)

| Area | Status |
|---|---|
| 5-tab app: Routines, Exercises, Home, Nutrition, Progress | Done |
| Onboarding, 18+ gate, readiness questions, sign up / guest | Done |
| Pose detection: Google ML Kit (33 landmarks, base model, offline) | Done |
| Engine: confidence gating, One Euro smoothing, rep state machine, rule persistence, view awareness, left/right naming, form scores, timed holds | Done |
| Voice + haptic feedback with cooldowns and the correction loop | Done |
| Guided workouts, rest timer, summary with "Fix next time", resume | Done |
| Routines, Routine Creator, Nutrition, Progress, Recover map, Coach, Accuracy Lab, Body scan, Settings | Done |

### Choices that differ from the PRD defaults (to keep the app light and buildable)
- **Storage:** a JSON store on `shared_preferences` instead of Drift (no code generation). Full history with per-rep records is kept.
- **Navigation:** Flutter `Navigator` + `IndexedStack` instead of go_router.
- **Charts:** a small custom painter instead of fl_chart.
- **Cloud:** Firebase is not wired in because it needs your Firebase project files. The auth screen validates input and never stores passwords.

## Run it

```bash
flutter pub get
flutter run                       # Android
cd ios && pod install && cd ..    # iOS, on a Mac, first time
flutter run -d iphone
```

## Your own logo

The logo is original artwork drawn by `tool/make_logo.py`. To use your own:

1. Make a square PNG, 1024x1024 (no text near the edges).
2. Save it as `assets/branding/logo_1024.png`.
3. Run `pip install pillow numpy && python3 tool/make_logo.py --from assets/branding/logo_1024.png`.
   This rewrites the in-app logo, all Android launcher icons (normal, round
   and adaptive) and the iOS AppIcon set.

Without Python: replace `assets/branding/logo.png` (in-app, 512 px) and the
`ic_launcher*.png` files in `android/app/src/main/res/mipmap-*` (48, 72, 96,
144, 192 px), and drop the 1024 px PNG on Xcode's AppIcon (Runner →
Assets.xcassets).

## Tests

```bash
flutter test                     # unit + widget + replay tests
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart   # screenshot tour on a device/emulator
```

Unit tests cover angle maths, smoothing, the rep state machine, rules and persistence, feedback cooldowns and the correction loop (TC-21, TC-22), replay of all 56 exercise demonstrations through the engine (correct reps counted clean, shallow reps flagged), timed holds, auto-pause (TC-32), fuzzing (TC-20), focus-landmark framing and side choice, premium / rewarded-ad / owner entitlements, nutrition (TC-29), vitamins, recovery, coach, lab metrics, routines, the guided workout and resume (TC-24), body scan, validators and the local store. Widget tests cover every tab, the library filters and sections, the premium lock and rewarded unlock, and owner access.

`python3 tool/sim_engine.py` replays the same checks in Python while you edit exercises. On GitHub, Actions → **Check** runs analyze + tests (no APK); **Build release (manual)** builds the .aab and APKs.

## Editing exercises
Edit `tool/build_exercises.py` and run `python3 tool/build_exercises.py` to regenerate `assets/data/exercises.json`, then `python3 tool/sim_engine.py` to check it. No Dart changes are needed to add an exercise (render its 3D video with the commands in ASSETS.md).

## Licences
See [ASSETS.md](ASSETS.md).
