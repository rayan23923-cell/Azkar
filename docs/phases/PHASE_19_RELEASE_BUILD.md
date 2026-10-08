# Phase 19: Production build

**Source:** CI step «Release build (unsigned) and bundle checks», run 37794194252, commit
`47942ea`.

## Build

```
xcodebuild build -project IslamicPiPPOC.xcodeproj -scheme IslamicPiPPOC \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

Result: `** BUILD SUCCEEDED **`. The only remaining build-tool notice is the AppIntents metadata
processor saying it skipped (the app has no App Intents).

Two warnings from the previous run were fixed:

- a deprecated `onChange` call;
- a missing iPad upside-down orientation.

## Bundle checks (all pass)

- `Info.plist`:
  - display name «أذكار», version 1.0 (1), iOS 17.0;
  - `ITSAppUsesNonExemptEncryption` false;
  - `CFBundleIconName` AppIcon;
  - `UIBackgroundModes` audio;
  - no usage-description keys.
- `PrivacyInfo.xcprivacy` is present and lints OK.
- `Assets.car` is present (icon and accent colour).
- No fixture code and no test audio.
- Bundled resources:
  - `Content/adhkar.json`, `content_audio.json`, `duas.json`, `hisn_audio.json`, `hisn.json`,
    `quran.json`;
  - `QuranText.bundle/AmiriQuran-Regular.ttf` (and the OFL text).
- Size: 7.1 MB uncompressed. The unsigned Debug IPA is 2.4 MB.

## Not done (owner)

Signing, the real bundle identifier, and an archive or upload. The project's bundle identifier
and signing settings were not changed. CI substitutes a test identifier in its own checkout
only.
