# Phase 3C: audit of the existing PiP implementation

Written before any Phase 3C code change, on `feature/v1-phase-3c-hisn-pip` at `0a1339c`
(= Phase 3B head). Sources read: `IslamicPiPPOC/PiPEngine.swift` (369 lines),
`IslamicPiPPOC/AzkarFrameRenderer.swift` (107), `IslamicPiPPOC/ContentView.swift` (129),
`IslamicPiPPOC/IslamicPiPPOCApp.swift` (17), `Info.plist`, the Phase 3B audio targets, and the
Phase 1 audit (`PIP_V1_ARCHITECTURE_AUDIT.md` on `feature/v1-phase-1-audit`, PR #1), which
records the owner's device run.

## 1. Ownership today

| Concern | Owner | Detail |
|---|---|---|
| PiP controller | `PiPEngine` (`@StateObject` in `IslamicPiPPOCApp`, one per app) | `AVPictureInPictureController(contentSource:)`, created once in `prepare()`, strongly retained in `pipController` |
| Content source | `PiPEngine` | `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)` |
| Display layer | `PiPEngine.displayLayer` | one `AVSampleBufferDisplayLayer`, `.resizeAspect`, black background; hosted inline by `SampleBufferView` (a `UIViewRepresentable` in `ContentView.swift`) |
| Playback delegate | `PiPEngine` | `AVPictureInPictureSampleBufferPlaybackDelegate` (section 4) |
| Controller delegate | `PiPEngine` | will/did start, failed to start, did stop, restore UI (logs only; restore completes `true`) |
| Timing | `PiPEngine.timebase` | `CMTimebase` on `CMClockGetHostTimeClock()`, set as `displayLayer.controlTimebase`; rate 1 while "playing", 0 while paused; frame PTS = timebase time |
| Frame generation | `AzkarFrameRenderer` (stateless enum) | 1280×720 BGRA `CVPixelBuffer`, UIKit text drawing (RTL paragraph, system font 110 pt bold, footer 34 pt), then `CMSampleBuffer` with `kCMSampleAttachmentKey_DisplayImmediately` |
| Frame heartbeat | `PiPEngine.frameTimer` | `Timer` every 0.5 s on the main run loop (`.common`) re-enqueues the current frame; started in `prepare()`, never stopped |
| Content rotation | `PiPEngine.rotateTimer` | every 5 s while playing, cycles 4 hard-coded azkar |
| Audio | `PiPEngine.audioPlayer` | optional generated chime (`AVAudioPlayer`, looping 5 s WAV written to tmp) |
| Audio session | `PiPEngine.prepare()` **and** Phase 3B `HisnAudioSessionCoordinator` | PiPEngine: `setCategory(.playback, mode: .moviePlayback)` + `setActive(true)` on every `prepare()`. 3B coordinator: `.playback` / `.spokenAudio` only if the category is not already `.playback`, `setActive(true)` on Hisn play. Two configurators: the known 3B overlap |
| Interruption observing | both | PiPEngine logs interruptions only; the 3B coordinator turns them into player events |

## 2. Lifecycle

- `prepare()` (button «Prepare PiP»): session → controller (once) → `isPrepared` → `setPlaying(true)` → frame heartbeat.
- `startPiP()` / `stopPiP()`: `startPictureInPicture()` / `stopPictureInPicture()`.
- Automatic start: `canStartPictureInPictureAutomaticallyFromInline = autoStartEnabled` (default **true**, toggle on the test screen).
- `requiresLinearPlayback = false`.
- KVO on `isPictureInPicturePossible` / `isPictureInPictureActive`, hopped to main.
- Background: `UIBackgroundModes = audio`; frames keep being enqueued in background (counted in the log).
- Stop / close: `didStop` is logged; nothing is torn down. Timers and the controller live as long as the engine (app lifetime).
- Test hooks: on-screen status rows, the log, «Copy results» (device model, iOS, flags, log).

## 3. Threading

Timers and KVO handlers run on main. Delegate callbacks hop to main with
`DispatchQueue.main.async` before touching state. `isPlaybackPaused` and the time range read
properties directly from whatever thread AVKit calls on.

## 4. Playback delegate semantics today

| Callback | Behaviour |
|---|---|
| `setPlaying` | toggles the 5 s rotation, timebase rate and chime |
| `timeRangeForPlayback` | `.live`: infinite (play/pause only); `.steppable` (default): 0…24 h, so the system shows skip buttons |
| `isPlaybackPaused` | `!isPlaying` |
| `skipByInterval` | positive → next dhikr, negative → previous (an approximation; PiP has no next/previous buttons) |
| `didTransitionToRenderSize` | logged (392×220 seen on device) |
| `ShouldProhibitBackgroundAudioPlayback` | `false` |

## 5. Device evidence (owner's run, from the Phase 1 audit)

iPhone12,5, iOS 26.6.2: PiP supported and possible; automatic PiP on leaving the app PASS;
frames enqueued in background PASS; render size 392×220; chime audio path PASS;
sample-buffer content source PASS. Issue seen: `renderer failed: Operation Interrupted` in the
log after returning to the foreground (the engine flushes and continues). Unknown: auto-PiP
with audio off, Arabic legibility at 392×220, skip mapping, long PiP sessions. Not re-observed
in this phase.

## 6. Baseline before Phase 3C changes

| PiP baseline | Result |
|---|---|
| Build | PASS: CI run 37756031749 (Phase 3B head `0a1339c` lineage), device + simulator `BUILD SUCCEEDED`, `UIBackgroundModes` audio present |
| Unit tests | PASS: 150 Swift tests (the PiP engine has no unit tests; it lives in the app target) |
| Real device | Not re-run in this phase (no device in this session). Last device evidence: section 5 |
| Automatic PiP | PASS on the owner's device run (section 5) |
| Background | PASS on the owner's device run |
| Audio/chime | PASS on the owner's device run |

The baseline is not broken by any evidence available, so Phase 3C proceeds.

## 7. Findings that shape Phase 3C

1. **No reusable audio-session abstraction in the PiP code.** PiPEngine configures the session
   inline. The only abstraction is the 3B coordinator, so it becomes the single owner and
   PiPEngine calls it (the one change to PiPEngine), keeping the proven `.playback` /
   `.moviePlayback` policy.
2. **The proven pipeline is reusable without rewriting it.** `AzkarFrameRenderer.makeSampleBuffer`
   (pixel buffer → sample buffer, display immediately) is shared as is. The Hisn surface uses
   the same parts: host-clock timebase as `controlTimebase`, `ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`,
   a strongly retained controller, an inline visible layer, a periodic heartbeat.
3. **PiPEngine cannot host Hisn.** Its layer lives in the PiP test screen, which is covered
   while Hisn is open (a full-screen presentation), its state is the 4-dhikr rotation, and its
   automatic start is on by default. Making it own Hisn state would violate the ownership
   rules. Hisn therefore gets its own surface instance (one controller, used only by the Hisn
   reader), and the test screen keeps its engine unchanged.
4. **Automatic PiP is global on the test engine.** Hisn does not inherit it: Hisn PiP starts
   manually (section 11 of the integration document).
5. **The heartbeat never stops in the POC.** The Hisn surface runs its heartbeat only while
   the reader shows the inline surface or PiP is active.
6. **skip → next/previous in the POC** would be wrong for audio; Hisn maps skip to seeking
   within the recording only.
