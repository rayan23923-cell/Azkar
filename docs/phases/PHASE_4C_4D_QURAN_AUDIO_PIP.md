# Phase 4C–4D: Quran audio and Quran PiP

## Rights gate

No Quran recording has licence terms on file. Per the release rules, no audio ships.

The shared pack `content_audio.json` (Quran, adhkar and duas) exists and is checked like the
Hisn pack:

- status `PENDING_RIGHTS_AND_ASSETS`;
- no assets.

`tools/content/check_audio_packs.py` reports it as BLOCKED for release; the CI step still
passes, because rights are a pre-release gate rather than a build failure.

## What is built (target `ContentAudio`)

- **`ContentAudioPack`** — the repository for the shared pack.
  - Item ids are content references («quran:2:255»).
  - It runs every Hisn pack rule: plain file names, format, size, SHA-256, production-only
    assets, one recording per reference, and references that must exist.
  - `releaseBlockers` lists why the pack cannot ship.
- **`AudioQueueController`** — plays verses (or adhkar) in order on top of the proven
  `HisnAudioPlayer`, so the session, interruption and route rules are the same as Hisn.
  - Next and previous; previous first goes back to the start of the current verse.
  - Continuous play skips items with no recording and stops at the end.
  - A snapshot can be saved and restored against current content.
- **`QueuePiPCoordinator`** — Quran PiP on the same `HisnPiPSurface` protocol as Hisn PiP:
  - the queue supplies the title and verse text;
  - the player is the playback controller;
  - the surface draws.
  - Skip buttons seek inside the current recording.
  - PiP is offered only while a recording is loaded, and it stops instead of pretending when
    the next verse has none.

## Hisn PiP is unchanged

The app's `SampleBufferPiPSurface` now holds its controller as `PiPPlaybackControlling`, a
two-method protocol that `HisnPiPCoordinator` implements. The surface still uses:

- AVPictureInPictureController with a ContentSource;
- AVSampleBufferDisplayLayer;
- CMSampleBuffer, CVPixelBuffer and CMTimebase;
- the sample-buffer playback delegate.

All of it is unchanged, and the Hisn PiP tests pass unchanged.

## App

With an empty pack there is nothing to play. The Quran reader shows no audio or PiP control,
and Settings says recitations are not available in this release. Turning audio on later
needs:

- licensed files and a READY manifest;
- the play and PiP controls in the reader, built on the tested queue and coordinator.

## Tests

`ContentAudioTests`, all with fakes:

- continuous play and skipping;
- non-continuous play;
- next and previous while playing;
- interruptions and route loss pause and never auto-resume;
- snapshot and restore, including dropped content;
- the empty queue;
- queue PiP content, controls, clamped seeking, stop when audio is lost, and close;
- the bundled pack is empty and pending;
- unknown references are refused.

## Gate

BLOCKED_BY_RIGHTS for audio content. The architecture is PASS (tested).
