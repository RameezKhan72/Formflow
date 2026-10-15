# Publishing FormFlow (Google Play and App Store)

## Before the first upload

1. **App id** — `android/app/build.gradle.kts` → `applicationId` (now
   `com.formflow.formflow`). Choose your own, e.g. `com.yourname.formflow`;
   it can never change after the first upload. For iOS set the same bundle id
   in Xcode (Runner → Signing & Capabilities).
2. **Logo** — see "Your own logo" in README.md.
3. **AdMob and Premium** — follow MONETIZATION.md (replace the test ids).
4. **Owner code** — build with `--dart-define=OWNER_CODE=your-secret`.

## Android signing (one time)

```bash
keytool -genkey -v -keystore android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Create `android/key.properties` (never commit it; it is in .gitignore):

```
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
```

Without this file release builds are signed with the debug key (fine for
testing, rejected by Play).

## Build

```bash
flutter pub get
flutter build appbundle --release --dart-define=OWNER_CODE=... --dart-define=ADMOB_...   # Play Store (.aab)
flutter build apk --release --split-per-abi                                                # installable APKs
```

Or on GitHub: Actions → **Build release (manual)** → Run workflow. To sign
there, add repository secrets `KEYSTORE_BASE64` (`base64 -w0 upload-keystore.jks`)
and `KEY_PROPERTIES` (the text of key.properties).

## iOS

Needs a Mac with Xcode 15+ and CocoaPods.

```bash
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release --dart-define=OWNER_CODE=...
```

The Podfile already sets iOS 15.5 (required by ML Kit). Info.plist already has
the camera text, AdMob id (test) and SKAdNetwork id.

## Play Console checklist

- Store listing: name "FormFlow", short and full description, 512 px icon
  (`assets/branding/logo_1024.png` resized), feature graphic 1024x500,
  at least 2 phone screenshots.
- Privacy policy URL (required: camera + ads). State that camera frames are
  processed on the phone and never stored or uploaded.
- App content: Ads = Yes, target audience 18+, health/fitness category,
  Data safety (advertising id via AdMob; no camera data collected).
- Content rating questionnaire.
- Upload the .aab to Internal testing first, test Premium purchase and ads,
  then promote to Production.
- Credit for the 3D anatomy (CC BY-SA 4.0) is in Settings → About and in ASSETS.md.
