# Phase 17: Privacy and security review

## Data

- No account, no network, no analytics, no tracking, no advertising identifier.
- Reading positions, progress, favorites and settings stay in UserDefaults on the device.
- Copy and share happen only when the user taps them, through the system pasteboard and share
  sheet.

## Permissions

| Permission | Why | When asked |
|---|---|---|
| Notifications | Optional daily morning and evening reminders | Only when the user turns a reminder on in Settings; never at launch |

No other permission is requested. The Release Info.plist has no `NS…UsageDescription` key
(checked in CI).

## Info.plist (Release, from CI)

| Key | Value | Note |
|---|---|---|
| `CFBundleDisplayName` | «أذكار» | Was «PiP Test» |
| `CFBundleShortVersionString` | 1.0 | |
| `CFBundleVersion` | 1 | |
| `ITSAppUsesNonExemptEncryption` | NO | |
| `MinimumOSVersion` | 17.0 | |
| `UIBackgroundModes` | audio | For Hisn and Quran playback and PiP. With no recordings in this build, the mode has no user-visible use. This is a release blocker: either ship licensed audio, or remove the mode before submission (see App Store readiness). |
| `NSAccentColorName` | AccentColor | |
| `CFBundleIcons` | AppIcon | |

The bundle identifier was not changed in the project (`com.example.IslamicPiPPOC`). CI
substitutes a test identifier only in its own checkout.

## Privacy manifest

`IslamicPiPPOC/PrivacyInfo.xcprivacy`:

- `NSPrivacyTracking` false;
- no tracking domains;
- no collected data types;
- one required-reason API, UserDefaults, with reason `CA92.1` (the app's own data).

CI lints it in the Release bundle.

## Code

- The audio and content files are validated:
  - plain file names only, inside their folder;
  - SHA-256 and size;
  - only production assets in the app.
- The fixture and test audio are compiled only with `HISN_AUDIO_FIXTURE`. CI fails if fixture
  code or test audio is found in the production or Release app.
- No secrets are in the repository. Signing is not configured: `DEVELOPMENT_TEAM` is empty and
  CI builds unsigned.

## Gate

PASS_WITH_KNOWN_LIMITATIONS (background audio mode; see readiness).
