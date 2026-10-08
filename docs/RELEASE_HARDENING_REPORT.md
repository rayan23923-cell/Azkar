# Release hardening report

**Branch:** `feature/v1-release` (PR #15 → `main`). **Scope:** hardening only; no new features.

## Build

| Field | Value |
|---|---|
| Version (`MARKETING_VERSION`) | 1.0 (unchanged) |
| Build number (`CURRENT_PROJECT_VERSION`) | 1. Valid for a first upload; raise it for each later upload. |
| Configuration | Release (App Store), unsigned in CI |
| Bundle identifier | `com.example.IslamicPiPPOC`, a placeholder. **EXTERNAL_BLOCKER: production Bundle ID required.** Not invented here. |
| Deployment target | iOS 17.0; iPhone and iPad |
| Signing | None (`DEVELOPMENT_TEAM` empty). **EXTERNAL_BLOCKER: Apple Developer signing credentials required.** |
| Entitlements, capabilities, URL schemes | None |
| Info.plist (Release) | No background modes, no usage descriptions; `ITSAppUsesNonExemptEncryption` NO; display name «أذكار» |
| Asset catalog | `AppIcon` (1024 px, opaque RGB, no alpha) and `AccentColor` (light and dark) |
| Launch | Generated launch screen |
| CI artifacts | Release build, Release archive (`.xcarchive`), unsigned Release IPA from the archive, Debug IPA, fixture IPA (testing only) |

## Changes made in hardening

1. **Background audio removed from Release (Option B).**
   - **Why:** no production recording ships, so `UIBackgroundModes: audio` had no use in
     Release and risked rejection under App Review 2.5.4.
   - **How:** `Info.plist`, used by Release, is now empty. `Info-Debug.plist`, used by Debug,
     keeps `audio` for the PiP test screen and the fixture IPA used in device testing.
   - **PiP is not broken:** Release offers PiP only with a loaded recording, so with no
     recordings it is never offered. The coordinator reports «not possible» rather than
     failing.
   - When licensed audio ships, put `audio` back in `Info.plist`; nothing else changes.
   - CI fails if a Release build has a background mode.
2. **The PiP test screen and its engine are Debug-only.**
   - `PiPEngine` and `ContentView` (the original proof of concept, with its synthetic chime
     and its own audio session handling) are wrapped in `#if DEBUG`.
   - The App no longer creates the engine in Release.
   - The Release app therefore has no test screen, no synthetic audio and no second
     audio-session owner. CI fails if `PiPEngine` is found in the Release app.
   - `AzkarFrameRenderer`, which the Hisn PiP surface uses, stays.
3. **CI archives Release** and packages an unsigned IPA from the archive.
4. **Documents added:**
   - `CONTENT_REVIEW_GATE.md`;
   - `PHYSICAL_DEVICE_RELEASE_CHECKLIST.md`;
   - `APP_STORE_METADATA.md`, with the screenshot checklist;
   - this report.
   `RIGHTS_AND_ATTRIBUTION.md` and `RELEASE_READINESS_REPORT.md` were updated.

## Tests

CI run 37801563594 on `14ae1c4` is green in every step:

- **Tests:**
  - 312 Swift tests in 45 classes: 312 passed, 0 failed. No test changed since the last
    counted run.
  - Python content tests, the content `--check`, the fixture check and the audio-pack check.
- **Debug:** device and simulator builds, and the unsigned IPA.
- **Release:** the build passes its bundle checks:
  - no `UIBackgroundModes`;
  - no `PiPEngine`;
  - no fixture or test audio;
  - privacy manifest lint.
- **Release archive:** `ARCHIVE SUCCEEDED`, and an unsigned IPA is packaged from it.
- **Fixture IPA:** for device testing only.
- **Validators:** the content, privacy-manifest, audio-pack and production-purity checks pass.
- **Not done:** signed archive and upload validation. This needs signing credentials (external).

The tests cover:

- content;
- search;
- audio;
- PiP;
- persistence;
- accessibility strings.

## Content

| Section | State |
|---|---|
| Quran | 114 / 6236, Tanzil hashes pinned, verse-by-verse fidelity test |
| Hisn | 132 / 267 canonical; 133 / 302 presentation; all `CONTENT_REVIEW_REQUIRED` |
| Adhkar | 51 (18 Quranic) |
| Dua | 17 (10 Quranic) |

No text or review status changed. See `CONTENT_REVIEW_GATE.md`.

## PiP

Audit only, no redesign. The proven path is intact:

- `SampleBufferPiPSurface`;
- `AVPictureInPictureController` with a sample-buffer `ContentSource`;
- `AVSampleBufferDisplayLayer`;
- a `CMSampleBuffer` / `CVPixelBuffer` frame pipeline;
- a host-clock `CMTimebase`;
- the sample-buffer playback delegate, which forwards to `PiPPlaybackControlling`.

The coordinators (Hisn, and the queue for the Quran and adhkar) are unit tested. In production:

- no test-only flag (fixture code compiles only with `HISN_AUDIO_FIXTURE`; CI checks);
- no synthetic audio;
- no POC name visible;
- no test screen.

PiP needs a real recording, so it is inactive in Release. Device validation: NOT PERFORMED.

## Audio

- Both packs are `PENDING_RIGHTS_AND_ASSETS` with 0 recordings.
- The player and queue are tested.
- There are no audio controls in Release.

**BLOCKED_BY_RIGHTS.**

## Accessibility

Reviewed in code:

- Arabic labels, values, hints and actions on every control and row;
- the counter speaks its remaining count;
- Dynamic Type (`relativeTo` for the Quran font, `@ScaledMetric` for adhkar);
- Reduce Motion;
- RTL;
- system colours;
- touch targets: the counter is at least 88 pt tall, menus at least 44 pt.

No issue found needing a change. Device VoiceOver pass: NOT TESTED.

## Privacy

- **Permissions:** notifications only, requested on use. There are no microphone, location,
  contacts or photos usage keys. Share-to-Photos goes through the system share sheet, which
  needs no key.
- **Tracking:** no tracking, analytics, ads, network or logging.
- **Storage:** UserDefaults only, declared in `PrivacyInfo.xcprivacy` with reason `CA92.1`,
  which CI lints.
- **EXTERNAL_BLOCKER:** a Privacy Policy URL is required for App Store Connect.

## Security

The working tree and the full git history were scanned for:

- API keys and tokens;
- passwords;
- private keys and certificates;
- provisioning profiles;
- `.p12` / `.mobileprovision` / `.pem` / `.env` files.

**Nothing found.** There are no entitlements. Audio and content files are validated by name
and SHA-256.

## Offline

Every core function is offline: the Quran, Hisn, adhkar, duas, search, progress, favorites,
counters and reminders. There is no networking code. The only links are tanzil.net (attribution)
and system Settings.

## Production UX

Searched production code for:

- PiP Test, POC, TEST_ONLY, DEBUG, synthetic, fixture;
- Experimental, Internal;
- `print(`, `NSLog`, `fatalError`, `preconditionFailure`;
- TODO, FIXME.

Results:

- **None is user-visible in Release.**
- TEST_ONLY and fixture appear only as the audio validator's refusal of test assets, and in
  the `HISN_AUDIO_FIXTURE`-gated device-test code.
- No `print`, `NSLog`, `fatalError` or `TODO` in production code.

Five tabs are present, each with loading, error (with retry), empty and «no results» states,
and with copy and save feedback (spoken notice).

## App Store metadata

Draft in `APP_STORE_METADATA.md`. Nothing was entered in App Store Connect.

## Physical device

**NOT_TESTED.** The checklist is in `PHYSICAL_DEVICE_RELEASE_CHECKLIST.md`.

## External blockers

1. Production Bundle ID.
2. Apple Developer signing: team, certificates, profiles, App Store Connect access.
3. Privacy Policy URL and Support URL.
4. A rights decision for Hisn Al-Muslim (and final attribution wording).
5. Scholarly review: 302 Hisn items, 7 DEFER decisions, 12 open P0 findings, 33 adhkar and 7
   duas.
6. Physical device testing on a signed build.
7. Licensed audio, for any future audio version (not needed for a no-audio 1.0).

## Optional polish

- A final app icon design (the current one is valid but provisional).
- iPad layout review, or iPhone-only.
- A page-faithful mushaf layout (not planned for 1.0).
