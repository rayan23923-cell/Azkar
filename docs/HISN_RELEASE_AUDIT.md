# Hisn Al-Muslim release audit (Phase 3L)

Status of everything Hisn as of the `feature/v1-release` branch.

## Verdict

**The feature is complete; the content and rights are not cleared for release.** The reader is
ready to ship from an engineering point of view. Publishing the Hisn text needs the
pre-release rights review and the open content decisions below.

## Features

| Area | Status | Evidence |
|---|---|---|
| Index (133 sections), resume, today's marks | Done | HisnReading tests; 3D, 3G |
| Reader: counter, repetitions, next / previous, completion, «الباب التالي» | Done | `HisnReaderControllerTests`, `HisnReaderTests` |
| Persistence (`hisn.reader.position.v1`) with recovery | Done | `HisnPersistenceTests`, `HisnResumeTests` |
| Search: 6 ranks, filters, highlight, navigation | Done | `HisnSearchTests` (28) |
| Copy, share text, share image | Done | `HisnItemActionsTests`, `HisnShareCardRendererTests` |
| Haptics (setting respected) | Done | 3E |
| Daily progress (chapter completed today) | Done | `HisnDailyProgressTests` |
| Reminders (morning / evening) | Done | `ReminderTests`; 3J |
| Accessibility (Arabic labels, values, hints, Dynamic Type, RTL) | Done | `HisnIndexAccessibilityTests`; 3K |
| Wording («باب» throughout) | Done | 3K |
| Audio player, session, interruption, route | Done, no content | `HisnAudioPlayerTests`, `HisnAudioPlaybackTests` |
| PiP (sample-buffer path) | Done, no content | `HisnPiPCoordinatorTests`, `HisnPiPValidationTests` |
| Global search reaches Hisn items | Done | `GlobalSearchTests` |

## Content

- 132 canonical chapters and 267 book items; 133 presentation sections and 302 display items.
  These are checked by `build_content.py --check` and the tests.
- Corrections manifest: 82 entries.
  - 36 accepted, 43 observation-only, 2 rejected, 1 pending decision.
  - Of the P0 entries, 26 are accepted and **12 are pending**.
- Editorial review: 15 decisions.
  - 7 DEFER, 3 KEEP_METADATA, 3 KEEP_NIL, 2 KEEP_SOURCE.
  - 0 changes applied; **0 of 15 independently reviewed**.
- Every item is `CONTENT_REVIEW_REQUIRED`.
- The canonical edition (the author's PDF) is recorded but **NOT_YET_COMPARED** item by item.

## Audio

`hisn_audio.json` is `PENDING_RIGHTS_AND_ASSETS` with 0 recordings.
`HisnAudioPackReport` / `check_audio_packs.py` print: release BLOCKED (status not READY;
no recordings). So production builds show no audio row and no PiP control.

## Rights

`PENDING_PRE_RELEASE_REVIEW`.

- The text comes from the asellam/HisnElMuslim repository (MIT).
- That licence covers the transcription, not the book; the book's rights holder has not
  granted anything on file.
- No clearance is claimed.

## Release blockers (Hisn)

1. A rights decision for the Hisn Al-Muslim text, from the rights holder or counsel.
2. Scholarly review of the content:
   - the 12 pending P0 corrections and the 1 pending decision;
   - the 7 deferred editorial decisions;
   - the item-by-item comparison with the canonical edition.
3. If audio is wanted: licensed recordings with a READY manifest. Otherwise ship without
   audio. The reader works without it.

## Not verified

Physical device testing and the Phase 3C device validation of PiP: NOT PERFORMED.
