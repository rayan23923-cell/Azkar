# Phase 18: Test matrix

**Source:** CI run 37794194252, commit `47942ea`.

**Package tests:** 312 Swift tests in 45 classes, 0 failures (8.65 s). There are also 20 Python
tests for the corrections manifest and 24 for the editorial review.

## Automated

| Area | Tests (classes) | Result |
|---|---|---|
| Content integrity: Tanzil fidelity, repositories, invalid content | TanzilFidelity 2, QuranRepository 9, DhikrRepository 5, DuaRepository 4, InvalidContent 5, HisnInvalidContent 3 | PASS |
| Hisn content: canonical counts, editorial, repository | HisnCanonical 12, HisnEditorialReview 4, HisnRepository 16 | PASS |
| `build_content.py --check` and the Python manifests | CI step | PASS |
| Audio packs intact (`check_audio_packs.py`) | CI step | PASS (release status: BLOCKED, reported) |
| Session cursor and states | SessionCursor 11, Session 3, StateType 1 | PASS |
| Hisn reader, persistence, resume, daily progress | HisnReader 15, HisnReaderController 5, HisnPersistence 10, HisnResume 6, HisnDailyProgress 4 | PASS |
| Hisn search | HisnSearch 28 | PASS |
| Hisn actions, share card, accessibility | HisnItemActions 11, HisnShareCardRenderer 7, HisnIndexAccessibility 5 | PASS |
| Hisn audio: manifest, report, state machine, player, reader audio | 17, 2, 8, 17, 7 | PASS |
| Hisn PiP: coordinator, validation | 18, 6 | PASS |
| Shared kit: normalizer, refs, daily progress, reminders | 1, 1, 7, 8 | PASS |
| Quran: library, position, controller, search, typography, share card | 6, 3, 4, 7, 4, 3 | PASS |
| Adhkar and duas: library, reader, search | 2, 6, 3 | PASS |
| Global search | 7 | PASS |
| Shared audio queue, queue PiP, content pack | 6, 1, 2 | PASS |

## Builds

| Build | Result |
|---|---|
| Debug, device | PASS |
| Debug, simulator | PASS |
| Production IPA (no fixture code or test audio) | PASS |
| Release, device, unsigned, with bundle checks | PASS |
| Fixture IPA (device testing only, not for release) | PASS |

## Manual and device

| Check | Result |
|---|---|
| Physical device run (iPhone) | NOT TESTED: BLOCKED (no device or signing in this environment) |
| iPad layout | NOT TESTED |
| VoiceOver pass on device | NOT TESTED |
| Largest accessibility text sizes, by eye | NOT TESTED |
| Hisn PiP on device (Phase 3C validation, fixture IPA) | NOT PERFORMED |
| Reminder delivery at the set time on device | NOT TESTED |
| Quran mark rendering reviewed by a qualified reader | NOT TESTED |
| Production audio playback | BLOCKED (no licensed recordings) |
| UI tests | KNOWN LIMITATION (no UI test target) |

## Device checklist for the owner (signed build)

1. Launch and every tab.
2. Quran:
   - open a surah;
   - scroll, then leave and return (resume);
   - search «الرحمن»;
   - bookmark, copy, share and share image.
3. Hisn:
   - read and count a chapter to completion;
   - check the next-section button;
   - search an item and open it.
4. Adhkar: morning collection through the counter to completion; the Home mark.
5. Global search, including a misspelling such as «الرخيم».
6. Settings:
   - appearance, sizes, haptics;
   - reminders (permission prompt, a test time);
   - reset;
   - About.
7. VoiceOver across the above, and the largest text size.
8. The fixture IPA only: Hisn audio and PiP (Phase 3C list).
