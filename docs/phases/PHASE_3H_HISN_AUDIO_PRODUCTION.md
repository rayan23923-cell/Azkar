# Phase 3H: Hisn audio production layer

## Already in place (Phases 3B and 3C), checked

- **Per-item recordings.** Keyed by `HisnItem.id`, in `hisn_audio.json`. Each entry has:
  - provenance: source name, URL, reciter, narration style, retrieval date, licence text,
    rights status;
  - format;
  - measured duration;
  - byte count;
  - SHA-256.
- **Validation.** `BundledHisnAudioRepository` checks the whole pack on first use. Any of these
  refuses the whole pack, so a broken pack never plays half-checked:
  - unknown item;
  - duplicate;
  - non-plain file name;
  - wrong extension;
  - size or checksum mismatch;
  - missing file;
  - test asset in the app.
- **Offline playback.** Bundled files only.
- **Interruption and headphones.** An interruption pauses and stays paused. Losing the
  headphones pauses.
- **Media services reset.** It unloads the recording.
- **Background audio.** `UIBackgroundModes = audio`, with the single session owner
  `AudioSessionCoordinator`.

## Added

- **`HisnAudioPackReport`.** For each display item it says whether there is a recording, and
  it lists what blocks release. Blockers:
  - the pack status is not `READY`;
  - no recordings;
  - a non-production asset;
  - rights still `PENDING_PRE_RELEASE_REVIEW`;
  - no reciter;
  - no measured duration.
- **`BundledHisnAudioRepository.manifest()`.** Returns the validated manifest for the report.
- **`tools/content/check_audio_packs.py`.** Runs in CI. For every bundled `*_audio.json` it
  checks:
  - names and extensions;
  - size and SHA-256;
  - PRODUCTION usage only;
  - one recording per item;
  - no unlisted audio files.

  It prints the release status as a report, not a failure.

## Status

- The pack is `PENDING_RIGHTS_AND_ASSETS` with 0 recordings.
- The preferred source is KFGQPC, Maher Al-Muaiqly, Hafs. Nothing was downloaded or bundled:
  the source's site is unreachable from the build environment (Phase 3 research) and its terms
  are not verified.
- No unlicensed audio is in the bundle. CI checks the production app for test audio.
- Release: BLOCKED for audio until licensed files are added and the rights decision is
  recorded. Hisn reading works fully without audio; the audio and PiP controls simply do not
  appear.
