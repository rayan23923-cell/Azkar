# Unified Production PiP

One Picture in Picture system for the Quran, Hisn Al-Muslim, the adhkar and the duas. It keeps
the device-proven path and changes only what sits around it.

## 1. What was reviewed first

| Piece | Before this phase | Classification |
|---|---|---|
| `PiPEngine` + `ContentView` (the original POC test tab) | Debug only, its own AVKit controller, synthetic chime | **DEBUG / TEST_ONLY**. Renamed `PiPTestEngine`, still `#if DEBUG`, unchanged otherwise |
| `AzkarFrameRenderer.makeSampleBuffer` | CVPixelBuffer to CMSampleBuffer, display-immediately | **Production**, reused as is |
| `AzkarFrameRenderer.makePixelBuffer` | POC frame | Used by the test engine only |
| `SampleBufferPiPSurface` (Hisn) | The proven AVKit setup (layer, host-clock timebase, ContentSource, delegates, 0.5 s heartbeat) | **Production**, moved to `IslamicPiPPOC/PiP/SampleBufferPiPController.swift` and generalised |
| `HisnPiPFrameRenderer` | UIKit text drawing, Hisn only | Replaced by `PiPRendering` (Core Text, every section, tested) |
| `HisnPiPCoordinator`, `QueuePiPCoordinator` | Hisn-only and queue-only PiP, available only with a recording | Superseded; no longer used by the app, kept with their tests |
| `HisnAudioFixture` / `HISN_AUDIO_FIXTURE` | TEST_ONLY tone for the device-test IPA | **TEST_ONLY**, unchanged; its build marks PiP frames «نغمة اختبار» |

The proven path is unchanged: `AVPictureInPictureController` with
`ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`, `AVSampleBufferDisplayLayer`,
`CVPixelBuffer`, `CMSampleBuffer`, a host-clock `CMTimebase` and
`AVPictureInPictureSampleBufferPlaybackDelegate`.

## 2. Architecture

```
PiPEngine (PiPCore)                 one per app, AppServices.shared.pip
 ├── PiPState                       the only PiP state
 ├── PiPController (protocol)       SampleBufferPiPController in the app, one per reader screen
 ├── PiPRenderer                    PiPFrameRenderer + CoreTextPiPPaginator (PiPRendering)
 ├── PiPPlaybackController          a loaded recording (Hisn audio player adapter)
 ├── PiPContentProvider (protocol)  what a section shows and how it moves
 ├── PiPPageModel / PiPNavigation   pages of a long text, then items
 └── PiPSession / PiPSessionStore   the last session
Providers (PiPProviders)
 ├── QuranPiPProvider               QuranReaderController
 ├── HisnPiPProvider                HisnReaderController (+ HisnAudioPlayer)
 ├── AdhkarPiPProvider              DevotionalReaderController (dhikr collection)
 └── DuaPiPProvider                 DevotionalReaderController (dua category)
```

- `PiPCore` imports no AVKit, UIKit or domain module. PiP only sees `PiPContent`: content type,
  content ID, container ID, title, subtitle, text, text style, index, total and a counter line.
- Each provider wraps the reader the screen already uses. The position, counter, saved place
  and favorites are the screen's own, never a copy.
- Each reader screen creates a `ReaderPiP` (its provider plus its own
  `SampleBufferPiPController`, whose inline layer the window grows from) and registers it with
  the engine. Only one of them runs PiP at a time.

## 3. State

`PiPState`: `inactive`, `starting`, `active` (shown, playing), `paused` (shown, nothing moves
by itself), `stopping`, `error(notSupported | disabled | noContent | failedToStart)`.

Transitions are a pure function (`PiPState.applying(_:)`, unit-tested). Only `PiPEngine` holds
the state; screens read it.

## 4. Lifecycle

1. The reader shows the PiP row: a small live preview and «نافذة عائمة» (Quran:
   «تشغيل في نافذة عائمة»). The audio session is not touched yet.
2. On tap, the engine checks the setting and the build, device support, and that there is
   content. Then the controller activates the audio session through `AudioSessionCoordinator`
   (the proven `.playback` / `.moviePlayback` policy) and starts PiP. If the system has not
   reported PiP possible yet, it waits up to 1.5 s and then reports `failedToStart`.
3. In the background, frames keep coming from the 0.5 s heartbeat (proven on device). A
   renderer that failed after returning to the foreground is flushed and continues.
4. Closing the window saves the session (status `closed`) and asks the reader to save its
   place. The reader stays on the item PiP showed.
5. "Return to app" in the window switches to the section's tab, where the reader still is.
6. Closing the reader screen (going back) closes its PiP. Switching tabs does not.

**Switching sections.** Quran PiP is running, the user opens the app, goes to Hisn and starts
Hisn PiP. The engine stops the Quran window first and saves its session and position. It
starts Hisn PiP when the system reports the old window closed. Late events from the old
controller are ignored, so the Quran PiP never controls anything again. This is covered by
`PiPEngineTests.testStartingAnotherSectionReplacesTheSession` and
`PiPDomainSwitchTests.testQuranThenHisnReplacesTheSession`.

**Auto PiP.** `canStartPictureInPictureAutomaticallyFromInline` is off for every section.
`PiPAvailability.allowsAutomaticStart` is the flag to turn it on later, as a product decision.

## 5. Controls

The system draws the PiP controls. A sample-buffer PiP has play/pause and skip
back/forward, and nothing custom. The skip buttons show the system's ±seconds icons, not
chevrons.

| Button | With a loaded recording | Without one (this build) |
|---|---|---|
| Play / Pause | Plays, pauses or resumes the recording | Turns the pages of a long text every 8 s and stops on the last page. A one-page text has nothing to play, so the button stays paused |
| Skip forward | Next page, then next item | Same |
| Skip back | Previous page, then previous item | Same |

**Navigation model** (`PiPNavigation`):

- Presentation level: the next page while the item has one.
- Content level: the next item only after its last page.
- Previous mirrors it, and an item always opens on its first page.
- Nothing moves past the first or last item. PiP never completes a Hisn chapter or a
  collection, and never opens another surah.

**Audio completion is not Next.** A recording that ends leaves PiP on its item, paused. Moving
to another item stops the recording and loads the new one without playing it (the reader's
rule). Seeking inside a recording is in-app only, since the skip buttons are navigation.

## 6. Sections

| Section | Title | Subtitle | Counter | Previous / next |
|---|---|---|---|---|
| Quran | سورة البقرة | الآية 10 | none | Verse within the surah. PiP follows the reader's jumps and surah changes, not plain scrolling |
| Hisn | Chapter title | الذكر 4 | التكرار 2 من 3 | The reader's own; stops at the last item |
| Adhkar | Collection title | الذكر 3 | التكرار 1 من 3 | The reader's own |
| Duas | Category title | الدعاء 2 | none (said once) | The reader's own |

PiP never counts a repetition, and opening it changes nothing. The counter moves only from the
reader's count button. Previous/next behave exactly like the reader's own buttons, which
start the new item's count at zero. Verses, and adhkar marked `quranVerbatimTanzil`, use the
bundled Quran font.

## 7. Rendering

`PiPFrameRenderer` draws a 1280×720 frame (16:9) with Core Text into the `CVPixelBuffer`. From
the top: the title and subtitle, the page of the text, a progress bar filling from the right,
and the footer (state, counter, «n من m», «صفحة p من q»). Everything is right to left, and
Core Text handles Arabic shaping and diacritics. Dark and light palettes follow the app's
appearance setting or the system's. The dark one is the POC's proven green.

**Long text.** The body uses the largest of 84, 72, 62 or 54 pt that fits. Text that does not
fit at 54 pt is split into pages at 54 pt, never shrunk further. Pages are exact slices of the
stored text, broken after whitespace, and joined they give back the text (tested on the
longest Hisn item and on verse 2:282).

**Progress bar.** With a recording, the system's progress follows it (rate 1 while playing).
Without one, the time range is the container's item count, and the bar shows the place in the
surah or collection (rate 0).

## 8. Audio integration

- `PiPPlaybackController` is the only audio surface PiP knows. The Hisn adapter wraps
  `HisnAudioPlayer`, and only a loaded production recording counts.
- The production packs are empty (`PENDING_RIGHTS_AND_ASSETS`), so every section runs as text
  PiP. No audio is invented.
- PiP never configures the audio session itself. `AudioSessionCoordinator` stays the single
  owner, so PiP cannot break the rest of the app's audio.
- Limitation: the proven policy has no `mixWithOthers`, so starting PiP pauses another app's
  music. This needs a device test before changing it.

## 9. Release activation: audit and decision

### Why PiP was hidden in Release (audit, 2026-10-09)

I checked every possible cause in the code, the project and the built apps. Only the first one
applies.

| Cause | Finding |
|---|---|
| 1. A condition the project wrote | **Yes, and it is the only one.** `AppServices` builds `PiPAvailability` from `Bundle.main.infoDictionary`; with no `UIBackgroundModes = audio` it is false, and `PiPEntryView` and the setting hide. It mirrors item 2. |
| 2. A real iOS requirement | **Yes, documented by Apple** (below). The project gate exists because of it. |
| 3. A wrong dependency on audio | **No.** Availability never looks at a recording. Without a recording every section runs in text mode (`PiPEngine.frame`, `mode: .text`); the Hisn recording is used only when one is loaded. Tested in `ReleasePiPConfigurationTests` and `PiPEngineTests`. |
| 4. Lifecycle or the sample-buffer renderer | **No.** The production path (`SampleBufferPiPController`, `PiPFrameRenderer`, the providers, the reader buttons) has no `#if DEBUG`. CI now checks that every piece is inside the Release binary. |

Release build settings: `INFOPLIST_FILE = Info.plist` for Release and `Info-Debug.plist` for
Debug (`project.pbxproj`, `project.yml`). The only difference between the two files is
`UIBackgroundModes = [audio]`. CI prints the Info.plist of the built Release app.

The one Debug-only piece that sat in the Release binary, the POC frame drawing
(`AzkarFrameRenderer.makePixelBuffer`, used only by the Debug test engine), is now compiled in
Debug only.

### What Apple says

- `AVPictureInPictureController`: "To use Picture in Picture, you need to configure your app to
  support background audio playback."
  ([docs](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller))
- "Configuring your app for media playback": "Your app also needs this capability to enable
  advanced playback features like AirPlay streaming and Picture in Picture playback", and "in
  iOS and tvOS it can use Picture in Picture playback" once the mode "Audio, AirPlay, and
  Picture in Picture" is enabled.
  ([docs](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback))
- The documents do not exempt `ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`.
  The only device evidence in this project (Phase 3C, iPhone12,5) was taken with the mode
  declared. Whether text PiP would start without it has **not been tried on a device**, so
  this section claims only what the documents say.

### Decision (owner, 2026-10-09): PiP ships in Release

The owner chose to add the PiP background mode to Release.

- `Info.plist` (Release) now declares `UIBackgroundModes = [audio]`, the same as
  `Info-Debug.plist`. That is the only change to what Release declares.
- It is declared for PiP, not to keep the app running. PiP starts only from the button, never
  automatically (`allowsAutomaticStart = false`), and the app plays nothing in the background.
- No silent or synthetic audio is used. No audio file ships in Release, and CI fails the
  Release build if one appears.
- CI (`build.yml`, `codemagic.yaml`) now requires the Release background modes to be exactly
  `[audio]`, where it used to require none. `ReleasePiPConfigurationTests` checks the same in
  both plists.
- Risk: App Review 2.5.4. A reviewer may ask why an app with no recordings declares the audio
  mode. The answer is PiP, which Apple ties to this mode. The review notes should say so and
  show the «نافذة عائمة» button.
- Whether PiP starts and keeps updating in the background on a real iPhone is **NOT_TESTED**.

## 10. Settings

There is one setting: «العرض العائم», on by default. It appears only in builds that can run
PiP, which are now Debug and Release. Turning it off closes a running window.

## 11. Release safety

- No PiP test UI in Release. The test tab, `PiPTestEngine` and the chime stay `#if DEBUG`.
- CI fails the Release build if it contains `PiPTestEngine` or the string
  `PiP Technical Test`, or if the production `PiPEngine` is missing.
- The only background mode Release may declare is `audio` (for PiP), and no audio file may ship.
- CI fails the Release build if any production PiP piece is missing from it:
  `SampleBufferPiPController`, `PiPFrameRenderer`, the four providers, and the button titles.
- `ReleasePiPConfigurationTests` fails if the production PiP path gets a `#if DEBUG` or test-only
  code.
- No production frame carries a test marker. Only the `HISN_AUDIO_FIXTURE` build adds «نغمة اختبار».

## 12. Tests

81 PiP tests (PiPCore 55, PiPRendering 9, PiPProviders 17). In CI they run with the rest of the
package: 393 tests, 0 failures.

| Suite | Covers |
|---|---|
| `PiPCoreTests/PiPStateTests` | Every transition, failure and retry, rejection while running |
| `PiPCoreTests/PiPPageModelTests` | Pages, clamping, exact slices, oversize words |
| `PiPCoreTests/PiPNavigationTests` | Page before item, ends, skip sign |
| `PiPCoreTests/PiPSessionAndAvailabilityTests` | Info.plist background mode, setting, session store, footer and progress |
| `PiPCoreTests/PiPEngineTests` | Start and refusals, navigation, long text, play and pause in text and audio modes, audio completion, close and session, section switch, heartbeat, return to app |
| `PiPCoreTests/ReleasePiPConfigurationTests` | No `#if DEBUG` or test-only code on the production PiP path, availability gated only by the declared mode, every reader offers PiP, both plists declare only `audio` |
| `PiPRenderingTests` | One page at 84 pt, longest Hisn item paged at 54 pt and fully drawn, RTL runs with diacritics, Quran font, verse 2:282 paged, light and dark |
| `PiPProvidersTests` | Quran (first, middle, last, next, previous, long ayah, scroll vs jump), Hisn (first, repetition, last, next, previous, long text, completed chapter, no counting, no production audio), Adhkar (first, middle, last, counter), Dua (first, middle, last), Quran → Hisn switch on real content |

## 13. Physical device status

**NOT_TESTED.** This environment has no iPhone, and nothing in this phase was run on a device.
The device evidence that exists is the earlier POC run (iPhone12,5, iOS 26.6.2: PiP start,
background frames, the sample-buffer source). It covers the path, not this feature.

To test, use the Release IPA (`azkar-release-ipa` on Codemagic), signed for your own iPhone:

1. Quran, Hisn, Adhkar, Dua: open an item and tap «نافذة عائمة». Check that the window shows
   the title, subtitle and text.
2. Skip forward and back: the page, then the item. Check the ends.
3. Play on a long Hisn item: the pages turn and it stops on the last page.
4. Home, another app, return to the app via the window, close the window. Then check the
   reader is on the item PiP showed.
5. Quran PiP, then open the app, go to Hisn and start PiP: the Quran window closes and Hisn
   opens.
6. Lock/unlock, dark mode, the longest Hisn item, VoiceOver on the PiP row, a phone call
   interruption.

7. Release IPA: Settings shows «العرض العائم»; the four readers show the button; the window
   starts, and keeps updating while another app is in front.

Watch for black or frozen frames, stale content after switching, two windows, and other apps'
audio pausing.

## 14. Limitations

- No custom PiP buttons exist. The skip buttons carry the system's ±seconds icons.
- Play/pause cannot be hidden in a sample-buffer PiP. In text mode it turns pages, and for a
  one-page text it does nothing.
- Without recordings, the system progress bar shows the place in the container, not time.
- Seeking a recording is in-app only.
- Release declares the audio background mode for PiP; App Review 2.5.4 risk (section 9).
- Starting PiP takes the audio session (section 8).
- Physical device: NOT_TESTED.
