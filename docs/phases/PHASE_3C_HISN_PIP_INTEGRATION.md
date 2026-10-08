# Phase 3C: Hisn audio and PiP integration

Branch `feature/v1-phase-3c-hisn-pip`, based on Phase 3B (`feature/v1-phase-3b-hisn-audio`,
`0a1339c`). Phase 3C connects the Phase 3B audio player to Picture in Picture on the
device-proven sample-buffer path. It adds no content, no production audio, no rights changes
and no reader redesign.

**Status of real-device verification: not performed in this phase.** This session has no
physical iPhone. Every "device" line below is either the owner's earlier run of the POC
(Phase 1) or marked *not tested*. A fixture IPA for the device run is produced by CI
(section 12) and the checklist in section 14 is what remains.

## 1. Baseline PiP audit

The full audit, written before any change, is `docs/phases/PHASE_3C_PIP_AUDIT.md`. In short:

| Baseline | Result |
|---|---|
| Build | PASS (CI run 37756031749 on the 3B head) |
| Tests | PASS, 150 Swift tests (PiPEngine itself has no unit tests) |
| Real device | not re-run here; owner's run (iPhone12,5, iOS 26.6.2): PiP, automatic PiP, background frames, chime all PASS |

The baseline was not broken, so the phase went ahead. PiPEngine (the POC test screen) is kept
as it was; its only change is that it activates the audio session through the single owner.

## 2. Architecture

```
Hisn Reader
    │
    ├── HisnSession
    │
    └── HisnAudioPlayer
             │
             ├── HisnAudioSessionCoordinator   (named AudioSessionCoordinator: app-wide)
             │
             └── AudioRepository
                    │
                    ▼
              local audio

HisnPiPCoordinator
    │
    ├── PiP playback delegate                  (SampleBufferPiPSurface → coordinator)
    │
    └── HisnPiPContentRenderer                 (HisnPiPFrameRenderer)
              │
              ▼
      AVSampleBufferDisplayLayer
              │
              ▼
   AVPictureInPictureController
```

| Concern | Owner | Where |
|---|---|---|
| Navigation, repetition | `HisnReader` / `HisnSession` (via `HisnReaderController`) | HisnReading, Phase 3A |
| Playback | `HisnAudioPlayer` | HisnReading, Phase 3B |
| Audio session | `AudioSessionCoordinator.shared` | HisnAudioPlayback |
| PiP lifecycle and control semantics | `HisnPiPCoordinator` | HisnReading (no AVKit) |
| AVKit objects, delegates, frame heartbeat | `SampleBufferPiPSurface` | app, `IslamicPiPPOC/Hisn/PiP` |
| Frame drawing | `HisnPiPFrameRenderer` | app |
| One reader screen's objects | `HisnReaderScreenModel` (`@StateObject` of `HisnReaderView`) | app |

Data flow: the reader and the player publish their state. `HisnPiPCoordinator` subscribes
(reader, player state, availability, duration) and asks the surface to redraw; the surface
pulls a `HisnPiPContent` (chapter title, unchanged item text, playback state, current time,
duration) from the coordinator for each frame. System PiP buttons go the other way: the
surface's delegate calls the coordinator, which calls the player. Nothing flows from PiP into
the reader: PiP never navigates and never counts.

SwiftUI owns no playback or PiP state: the views observe the controller, the player and the
coordinator, and send user intents.

## 3. Audio-session ownership

`AudioSessionCoordinator` (renamed from the 3B `HisnAudioSessionCoordinator`) is the only
code that calls `setCategory` / `setActive`. Policy: `.playback`, mode `.moviePlayback`, no
options (the configuration the owner proved on a device with the POC), set only when it
differs, activated when playback or PiP preparation starts, never deactivated. PiPEngine's
`prepare()` now calls `AudioSessionCoordinator.shared.activateForPlayback()` instead of its
inline configuration. Tests check that no other app or package file configures the session.

The 3B mode `.spokenAudio` became `.moviePlayback` so both features share one proven
configuration; this does not change playback behaviour of the Hisn player.

## 4. PiP ownership

- One `SampleBufferPiPSurface` per open reader screen, with one display layer, one host-clock
  timebase and one `AVPictureInPictureController`, created once (when the inline preview first
  appears) and strongly retained.
- `HisnPiPCoordinator` decides when PiP may start and stop. It reads the controller; the
  controller does not know about PiP. PiPEngine knows nothing about Hisn.
- References: coordinator → surface strong; surface → coordinator weak; surface closures
  capture the coordinator weakly; timers and KVO capture the surface weakly. A test checks
  the coordinator is released.
- Closing the reader stops PiP, stops the heartbeat, then stops the recording and saves the
  place (`HisnReaderScreenModel.close()`).

## 5. Renderer

`HisnPiPFrameRenderer` draws a 1280×720 BGRA frame (the size the POC proved), then the
existing `AzkarFrameRenderer.makeSampleBuffer` wraps it (display immediately). The frame has:

- top: «حصن المسلم · chapter title», one line;
- middle: the dhikr's bundled `arabicText`, right to left, centred, bold;
- bottom: a progress bar filling from the right, the playback state («يُشغَّل»,
  «متوقف مؤقتًا», «انتهى التسجيل», «جاهز»), elapsed / total time, and «n/m» when paged.

Dark green background with white text in both light and dark appearance. No references are
shown. Long text: the largest of 84 / 72 / 62 / 54 / 46 pt that fits is used; text that does
not fit at 46 pt is split by `HisnPiPPaginator` into pages that are exact, contiguous slices
broken after spaces (joined, they equal the text; tested on the longest item, 1864
characters), shown in turn every 8 s. Text is never edited or silently cut. The layout is
cached per item.

Visual quality at real PiP sizes (392×220 seen on the owner's device) is **not verified**.

## 6. Playback delegate

| Callback | Hisn behaviour |
|---|---|
| `setPlaying(true)` | resume if paused, otherwise play (from the start if finished) |
| `setPlaying(false)` | pause |
| `timeRangeForPlayback` | 0 … recording duration |
| `isPlaybackPaused` | true unless the player is playing |
| `skipByInterval` | seek by the interval inside the recording, clamped; never next/previous |
| `didTransitionToRenderSize` | ignored |
| `shouldProhibitBackgroundAudioPlayback` | false |
| restore UI | completes `true` (the reader is still underneath) |

AVKit may ask `timeRange` and `isPlaybackPaused` off the main thread; they read a locked
snapshot updated with every frame. All other callbacks hop to the main actor.

## 7. Timing

The audio player's `currentTime` is the only clock for position. On each frame the surface
sets the timebase to that time with rate 1 while playing and 0 otherwise, and stamps the
sample with it, so the system's PiP progress follows the audio. Frames are drawn by a 0.5 s
`Timer` (main run loop, `.common`) that runs only while the inline preview is on screen or
PiP is starting/active, plus an immediate redraw on every state change and control. There is
no other loop.

## 8. Seek

PiP skip buttons: `audio.seek(to: currentTime + interval)`; the player clamps to
0…duration. The in-app slider (3B) is unchanged. Seeking never changes the dhikr or the
count.

## 9. Lifecycle

- Start: manual, from «عرض عائم» under the audio controls. Refused (with an Arabic message)
  when PiP is unsupported, not yet possible, or the item has no recording.
- will/did start/stop only change the coordinator's status and the heartbeat. They do not
  touch the reader, the player, the session or the count.
- Failed to start: status back to inactive, message «تعذر بدء العرض العائم، والتسجيل مستمر»;
  audio keeps playing.
- Navigating to an item without a recording, or completing the chapter, stops PiP (PiP never
  shows an item it cannot play).
- Recording finished in PiP: the state shows «انتهى التسجيل», PiP stays, nothing advances.
- Leaving the reader: PiP stops, audio stops, place saved.

## 10. Background behaviour

`UIBackgroundModes = audio` (unchanged) keeps the player and the frame heartbeat running in
the background, as on the POC device run. Interruptions and route changes use the 3B rules
(pause, no automatic resume). Lock screen, other apps in front and long sessions with Hisn
PiP are **not tested on a device**.

## 11. Automatic PiP policy

Hisn: `canStartPictureInPictureAutomaticallyFromInline = false`. PiP starts only from the
button. The POC test screen keeps its own toggle (default on), unchanged, and its engine is a
separate controller, so it cannot start Hisn PiP. Automatic PiP for Hisn is not enabled and
was not tested.

## 12. Test fixture

Two TEST_ONLY files, generated by `tools/content/make_hisn_audio_fixture.py` (checked in CI
with `--check`):

| File | Use |
|---|---|
| `test-silence-1s.wav` (16044 B) | unit tests (3B) |
| `test-tone-30s.wav` (480044 B, sha256 `9a3efed7…0d22`) | device testing: a soft 660 Hz beep each second, a longer one every 10 s, so seek and pause are audible |

`Fixtures/hisn_audio.device-test.json` maps the tone to `hisn-001-01` (short text) and
`hisn-001-04` (1864 characters, for paging), `usage: TEST_ONLY`, no reciter, rights pending.
It is a synthetic tone, not a recitation.

Injection: CI builds a second IPA, `IslamicPiPPOC-hisn-audio-fixture.ipa` (artifact name ends
in `NOT-FOR-RELEASE`), with `SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG HISN_AUDIO_FIXTURE'`
and the two files copied into `HisnAudioFixture/` in the app. Only under that flag does the
composition root (`HisnLibraryModel.load`) use a repository that allows TEST_ONLY assets,
the reader shows «نسخة اختبار: الصوت نغمة اختبار صناعية وليس تلاوة», and the PiP header
starts with «نغمة اختبار». The production IPA is checked in CI to contain neither the files
nor the fixture code, and a test checks the app sources never allow `.testOnly` outside the
flag.

## 13. Production empty-audio behaviour

`hisn_audio.json` still has no assets. Every item is "no recording", so the reader shows no
audio controls and no PiP row, and the coordinator refuses to start (tested with the real
bundled manifest). The reader is the Phase 3A reader.

## 14. Real-device results

Not performed in this phase (no device in this session). Checklist for the owner, with the
fixture IPA, chapter 1 (items 1 and 4 have the tone):

| Test | Steps | Result |
|---|---|---|
| A normal audio | play, pause, resume, seek, stop | not tested |
| B PiP | playing → «عرض عائم» → other app → PiP stays, audio continues → return | not tested |
| C PiP controls | play, pause, skip back, skip forward (beeps move, dhikr does not change) | not tested |
| D lifecycle | PiP → foreground → close PiP → continue in reader | not tested |
| E interruption | call / Siri / alarm while playing in PiP: pauses, stays paused | not tested |
| F route | speaker, headphones / Bluetooth; unplug pauses | not tested |
| G no asset | production IPA: no audio or PiP row anywhere | not tested |
| Visual | Arabic RTL, wrapping, legibility at small size, paging on item 4, progress, state | not tested |
| Background | locked screen, another app in front, while PiP is active | not tested |
| Automatic PiP | off for Hisn: leaving the app does not start Hisn PiP | not tested |
| POC regression | test screen: prepare, PiP, auto PiP, chime | not tested |

## 15. Regression results

- Swift tests: CI on this branch (see the PR); new tests cover the coordinator (availability,
  manual start, failures, lifecycle, heartbeat, controls, seek clamping, no repetition, no
  automatic next, release), the paginator, the device manifest, and source checks for the
  existing PiP path, the single session owner and the fixture flag.
- Content checks (`build_content --check`, corrections, editorial review) run unchanged in CI.
  No content file changed; `hisn.json` is untouched.
- Existing PiP: the POC engine is unchanged apart from the session call; checked in source and
  by the device/simulator build. Not re-run on a device.

## 16. Limitations

- No real-device run of Hisn PiP, the fixture, background, lock screen, interruptions or
  routes. Phase 3C is not complete until that run.
- No production recordings; production audio playback is not validated.
- PiP legibility at small sizes and paging interval are untested choices.
- PiP closes when the item has no recording, including after «التالي» to such an item.
- The 0.5 s heartbeat redraws the full frame (same as the POC); its CPU and battery cost on a
  device is not measured.
- The POC's "renderer failed: Operation Interrupted" after foregrounding may also occur here;
  the surface flushes a failed renderer before the next frame, as the POC does.

## 17. Rights status

Unchanged: `PENDING_PRE_RELEASE_REVIEW`. No audio was downloaded, no rights or licence claims
were added, and the fixture files are generated synthetic tones marked TEST_ONLY.
