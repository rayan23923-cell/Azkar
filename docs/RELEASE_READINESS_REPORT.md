# Release readiness report (Phase 21)

**Branch:** `feature/v1-release`. **Head:** see the release PR. **CI:** run 37794194252 on
`47942ea`, green.

## Executive Summary

**PROJECT STATUS: BLOCKED.** The engineering work is complete and green. Release is blocked
only by decisions and actions outside the code:

- rights;
- content review;
- app identity and signing;
- device testing.

The app is a complete, offline Arabic app:

- the Quran (114 surahs, 6236 verses, Tanzil Uthmani, Amiri Quran font);
- Hisn Al-Muslim (133 sections, 302 items);
- adhkar and duas (68 items);
- search across all of them;
- favorites, resume, daily progress and reminders.

CI shows:

- 312 package tests passing;
- the content checks passing;
- Debug, Release and IPA builds succeeding.

No content text was changed, no unlicensed audio is bundled, and no rights clearance is
claimed.

## Implemented Features

| Area | Features |
|---|---|
| Home | Today's adhkar by time of day, resume, Favorites, today's progress, global search |
| Quran | Surah and juz index, bookmarks, search (Uthmani-aware), reader with basmala, ayah markers, juz and page, go to ayah, previous and next surah, copy, share, share image, text size, resume, daily completion |
| Hisn Al-Muslim | Index, reader with counter, resume, search with 6 ranks and filters, copy, share, share image, haptics, daily completion, audio and PiP ready (no recordings) |
| Adhkar and duas | Collections, counter reader with per-collection resume, search, favorites, copy, share, share image, completion |
| Global search | Every section, deterministic ranking, source filter, safe typo suggestion |
| Settings | Reminders, appearance, haptics, text sizes, audio and PiP status, reset, clear favorites, About (sources, licences, privacy) |
| Platform | Tabs (the PiP test tab is Debug only), deep links from reminders, dark mode, RTL, Dynamic Type, VoiceOver |

## Test Results

- 312 Swift tests in 45 classes, 0 failures.
- Python manifest tests: 20 and 24, OK.
- `build_content.py --check`: content up to date.
- Builds PASS:
  - Debug device;
  - Debug simulator;
  - production IPA;
  - Release (with bundle checks);
  - fixture IPA.
- Manual and device testing: NOT TESTED (see `phases/PHASE_18_TEST_MATRIX.md`).

## Content Integrity

| Content | Count |
|---|---|
| Quran surahs / verses | 114 / 6236 |
| Hisn canonical chapters / book items | 132 / 267 |
| Hisn presentation sections / display items | 133 / 302 |
| Adhkar | 51 |
| Duas | 17 |

- Tanzil upstream hashes are pinned and every verse is compared.
- All content is rebuilt and compared in CI.
- File hashes are in `phases/PHASE_15_CONTENT_INTEGRITY.md`.

**PASS.**

## Audio Status

- Player, session, interruption and route handling are done for Hisn, and as a shared queue
  for the Quran and adhkar.
- Both packs (`hisn_audio.json`, `content_audio.json`) are `PENDING_RIGHTS_AND_ASSETS` with 0
  recordings.
- No audio controls show in production.

**BLOCKED_BY_RIGHTS.**

## PiP Status

- The proven sample-buffer path is unchanged, now driven through a small playback-control
  protocol.
- PiP is ready for Hisn (tested) and for any queue (tested).
- It is available only while a recording plays, so it is inactive in this build.
- Device validation: NOT PERFORMED.

## Accessibility

- Arabic VoiceOver labels, values, hints and actions throughout, tested in the packages.
- Dynamic Type, including the Quran font and the adhkar text.
- Reduce Motion respected; RTL; dark mode.
- A device VoiceOver pass: NOT TESTED.

## Performance

- Indexes are built once, off the main thread, and shared.
- The full test suite runs in 8.7 s on CI, including several full-Quran index builds.
- The Release app is 7.1 MB.
- Device launch time and memory: NOT MEASURED.

## Offline Capability

- No networking code.
- All content and the font are bundled.
- All state is local and versioned, with recovery from bad data.
- The only outbound actions are the tanzil.net link (required attribution, user-tapped) and
  system Settings.

**PASS.**

## Rights Status

- Quran text (Tanzil): the requirements are implemented (verbatim text, credit, link, notice
  shown).
- Hisn Al-Muslim: **PENDING_PRE_RELEASE_REVIEW** (MIT transcription; no grant from the rights
  holder).
- Adhkar and duas: PENDING_PRE_RELEASE_REVIEW; non-Quranic items await scholarly review.
- Font: OFL, licence shipped.
- Audio: none.

See `RIGHTS_AND_ATTRIBUTION.md`.

## Privacy

- No data collected, no tracking, no network.
- Notifications are the only permission, asked on use.
- Privacy manifest (UserDefaults `CA92.1`) and export compliance key are present.

**PASS.**

## App Store Readiness

The project side is in place:

- Release build;
- icon;
- display name «أذكار»;
- version 1.0;
- privacy manifest;
- About page.

The owner still has to provide the identity, signing and App Store Connect metadata. See
`APP_STORE_READINESS.md`.

## Known Limitations

- No UI test target.
- Device, iPad, VoiceOver and largest-text checks not done by hand.
- The reader is a verse list, not a page-faithful mushaf layout.
- Some mushaf spellings (for example «الصلوٰة») match only their Uthmani form in search.
- Hisn search: ة/ه folded; ؤ/ئ not folded; the highlight marks whole words.
- The app icon is provisional.
- PRs #1–#14 (earlier phases) are still open. This branch contains all of them, so merging
  the release PR supersedes them.

## Remaining Release Blockers

1. **Hisn Al-Muslim rights decision.** Alternatively, release without the Hisn tab.
2. **Scholarly content review:**
   - non-Quranic adhkar and duas (`CONTENT_REVIEW_REQUIRED`);
   - Hisn pending items: 12 P0 corrections, 1 decision, 7 deferred editorial decisions;
   - the item-by-item comparison with the canonical edition.
3. **App identity and signing.** The bundle identifier is still `com.example.IslamicPiPPOC`,
   and there is no team or signing (owner).
4. **Background audio mode with no audio.** Ship licensed recordings, or remove
   `UIBackgroundModes: audio` before submission (App Review 2.5.4).
5. **Device testing** of a signed build on iPhone (and iPad, or make it iPhone-only).
6. **App Store Connect:** privacy policy URL, support URL, screenshots, description, privacy
   answers.

## Final Recommendation

Merge the release PR into `main`. It carries every phase, all green.

Then, in order:

1. settle the Hisn rights;
2. complete the content review;
3. set the bundle identifier and signing;
4. decide on the background audio mode;
5. run the device checklist;
6. submit.

No further engineering is needed for a no-audio 1.0, unless review findings require content
corrections. Those go through the existing corrections pipeline.
