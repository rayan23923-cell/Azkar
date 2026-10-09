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
 ├── PiPPageModel / PiPNavigation   pages (play / pause), items and Hisn counting (skip)
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
| Play | Plays or resumes the recording | The next page of a long text, at once. Stops on the last page, never the next item |
| Pause | Pauses the recording | The previous page, at once. Stops on the first page |
| Skip forward | Next item (Hisn: counts first, see below) | Same |
| Skip back | Previous item | Same |

A one-page text has nothing to turn: play and pause do nothing and the button stays on play.
The button always shows what its next tap does: play (forward) until the last page, then
pause (back) until the first page, so every tap turns a page. The footer says it too
(«▶︎ الصفحة التالية» or «⏸ الصفحة السابقة»). Nothing turns by itself.

**Navigation model** (`PiPNavigation`):

- Presentation level, play / pause: the page of the current item. Never the item.
- Content level, skip: the item. Never the page. An item always opens on its first page.
- Hisn counting, skip forward: on an item with a stated count, one recitation per tap until
  the count is complete (`PiPRepetition`, from `HisnReader.Repetition.counted(completed:total:)`
  and `completedRepetitions`; no upper limit). The reader's own `recite()` records it and saves
  it at once. The full count moves the reader to the next item, as the screen's count button
  does, but the window keeps the finished item, marked «اكتمل ✓ m من m», until the next skip
  forward shows the next item. The chapter's last item completes the chapter (as on the screen)
  and the window keeps «اكتمل الباب» until the user closes it. Skip back never counts.
- Nothing moves past the first or last item. Skip forward never completes a chapter or a
  collection without counting, and PiP never opens another surah or chapter.

What iOS allows: a sample-buffer PiP window has only the system's play/pause, skip ±, close and
return-to-app buttons. Taps on the video itself are not delivered to the app, so a count
button drawn in the frame could never work. That is why counting uses skip forward.

**Audio completion is not Next.** A recording that ends leaves PiP on its item, paused. Moving
to another item stops the recording and loads the new one without playing it (the reader's
rule). Seeking inside a recording is in-app only, since the skip buttons are navigation.

### 5.1 What iOS lets this app configure (audit)

The app uses `AVPictureInPictureController(contentSource:
.init(sampleBufferDisplayLayer:playbackDelegate:))` with an `AVSampleBufferDisplayLayer`
(`SampleBufferPiPController`).

| Control | Who decides | This app |
|---|---|---|
| Close, return to app | iOS, always shown | Cannot be hidden or moved |
| Play / pause button | iOS, always shown in sample-buffer PiP | Its icon only, from `pictureInPictureControllerIsPlaybackPaused`; taps reach `setPlaying(_:)` |
| Skip back / forward | Shown while `requiresLinearPlayback == false` and the time range is finite | Kept, as they carry item navigation and the Hisn count. `requiresLinearPlayback = true` would remove them and the scrubbing together |
| Skip interval icon (±10/15 s) | iOS | Cannot be relabelled; the sign gives the direction |
| Progress bar | iOS, from `timeRangeForPlayback` and the timebase | A finite range (place in the container). A live range (infinite) changes the system UI and is not used, untested |
| Show and hide of the controls | iOS (shown on a tap, hidden again) | Cannot be changed |
| Custom buttons, taps on the frame | Not available | None: taps on the frame do not reach the app |
| Window aspect | The enqueued frames' size | 16:9 (section 7) |

So a single visible control is not possible through public API. Close, return to app and
play/pause are always there, and removing the skip buttons removes counting and item
navigation. Ordinary video-player PiP (`AVPlayerLayer` or `AVPlayerViewController`) has the
same system buttons, driven by the player's state instead of a delegate. It adds no way to
hide them, and it needs a video to play. No private API or key-value workaround is used.

## 6. Sections

| Section | Title | Subtitle | Counter | Previous / next |
|---|---|---|---|---|
| Quran | سورة البقرة | الآية 10 | none | Verse within the surah. PiP follows the reader's jumps and surah changes, not plain scrolling |
| Hisn | Chapter title | الذكر 4 | التكرار 37 من 100, counted by skip forward | The reader's own; stops at the last item |
| Adhkar | Collection title | الذكر 3 | التكرار 1 من 3 | The reader's own |
| Duas | Category title | الدعاء 2 | none (said once) | The reader's own |

Only Hisn items are counted in PiP, only by skip forward, and opening PiP changes nothing. The
Adhkar counter moves only from the reader's count button (skip there is the next dhikr). Previous/next behave exactly like the reader's own buttons, which
start the new item's count at zero. Verses, and adhkar marked `quranVerbatimTanzil`, use the
bundled Quran font.

## 7. Rendering

`PiPFrameRenderer` draws the frame with Core Text into the `CVPixelBuffer`. `PiPLayout` places
every part from the frame's size, as fractions of its shorter side, so the same layout works
at any size and in either orientation. The app draws 1280×720 (16:9), the size proven on a
device. Everything is right to left, and Core Text handles Arabic shaping and diacritics. Dark
and light palettes follow the app's appearance setting or the system's. The dark one is the
POC's proven green.

**Content first, around the system controls.** iOS draws its controls over the window and the
app cannot move or remove them (section 5.1). The places the layout keeps for them were
measured on an iPhone screenshot of the portrait window (2026-10-09), as fractions of the
window's width, with a margin:

| Control | Measured on the device | Kept by the layout (of the shorter side) |
|---|---|---|
| Close, return to app | Buttons 0.13 wide, bottom at 0.18 | Each corner 0.22 × 0.19 |
| Skip back, play/pause, skip forward | 0.05 to 0.95 across, 0.26 tall, centred | 0.96 of the width (at most 1.0) × 0.29, centred |
| Progress bar | Top 0.14 above the bottom | Bottom 0.15 |

iOS keeps its controls' size in points, so in a smaller window they cover more. These places
are an estimate from one device, not a guarantee (section 13, rows 3 and 7).

| Part | Where | Clear of |
|---|---|---|
| Title · subtitle | Top, between the two corner buttons | Close, return to app |
| Counter («التكرار 37 من 100  ·  ⏩ عُدّ») | Large. Portrait: across the window under the corner buttons. Landscape: under the title, between the corner buttons | Every control |
| Text, portrait | Two blocks, above and below the middle row | Every control |
| Text, landscape | One block between the counter (or title) and the information line | Corners and progress bar. The middle row shows over its centre while the controls are visible |
| Information («▶︎ الصفحة التالية  ·  4 من 10  ·  صفحة 2 من 3») | Just above the system progress bar | Every control |
| Thin progress line | Where the system bar shows | Nothing essential |

**Text blocks.** `PiPLayout.textBlocks(withCounter:)` gives the blocks in reading order. There
are two, above and below the middle row, when each holds at least two lines of a verse at the
smallest size; that is so in every portrait size tested (360×640 to 1080×1920) and in no
landscape one, which is too short. A text that fits the upper block is centred there, so a
short verse is never behind the play button (the screenshot showed «مَٰلِكِ يَوۡمِ ٱلدِّينِ» there).
A longer one fills the upper block and goes on, from the next line, in the lower one. Lines
are never split across blocks, and every character is drawn once.

The header, counter and information line each stay on one line, at a smaller size if they
must (tested up to «اكتمل ✓ 1000 من 1000»).

**Font size.** The body uses the largest of 97, 86, 76, 68 or 62 px (of 720) at which the whole
page fits the blocks. Text that does not fit at 62 is split into pages at 62, never shrunk
further: more pages rather than smaller type. Pages are exact slices of the stored text,
broken after whitespace, and joined they give back the text (tested on the longest Hisn item,
verses 2:255 and 2:282, dense marks, long words, digits and punctuation, in seven frame sizes).
No line is wider than its block, so nothing is squeezed.

**Portrait.** A sample-buffer PiP window takes the aspect ratio of the frames enqueued, and the
API sets no orientation limit, so a 9:16 frame gives a portrait window. Settings has
«اتجاه النافذة العائمة»: أفقي (the default, 16:9, the device-proven size) or عمودي (تجريبي,
9:16). The choice is read when the app opens (`PiPLayout.saved()`), so the pages and the frames
always agree; a change applies only after the app is quit (swiped away in the app switcher) and opened again. Going to the background, closing and reopening PiP, or a new PiP controller does not apply it. The pixel buffer
enqueued on the `AVSampleBufferDisplayLayer` is the chosen layout's size (720×1280 or
1280×720, `makePixelBuffer`), shown with `resizeAspect`. Nothing switches orientation by itself.

Device evidence (one screenshot, 2026-10-09): the portrait setting gives a 9:16 window, and
the system controls are where the table above puts them. That run predates the two text
blocks, so the new layout itself is not yet seen on a device. Portrait stays an experimental
setting and landscape the default until the checklist in section 13 passes.

**Frame previews.** `PiPFramePreviewTests` writes PNGs of rendered frames when
`PIP_PREVIEW_DIR` is set, and CI uploads them as the `pip-frame-previews` artifact: portrait
and landscape, a short and a long verse, Hisn counters (37 of 100, 1000 of 1000, a long item
counted 3), dense marks, light mode and the smallest frame (360×640). Each has a `-zones`
copy with the kept control places outlined in red and the text blocks in green. They are
renderer output, not device captures, and the red outlines are the layout's estimate, not
the real iOS controls. Nothing of this is in the app.

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

108 PiP tests (PiPCore 67, PiPRendering 19, PiPProviders 22). In CI they run with the rest of the
package: 420 tests, 0 failures.

| Suite | Covers |
|---|---|
| `PiPCoreTests/PiPStateTests` | Every transition, failure and retry, rejection while running |
| `PiPCoreTests/PiPPageModelTests` | Pages, clamping, exact slices, oversize words |
| `PiPCoreTests/PiPNavigationTests` | Play/pause pages and their bounds, skip items and ends, counting before moving on for counts 1, 3, 100, 101, 1000, skip sign |
| `PiPCoreTests/PiPSessionAndAvailabilityTests` | Info.plist background mode, setting, session store, footer and progress |
| `PiPCoreTests/PiPEngineTests` | Start and refusals, navigation, play = next page and pause = previous page drawn at once, first/last page, one-page text, button direction, new item and reopen on page 1, counting by skip only, play and pause in audio mode, audio completion, close and session, section switch, heartbeat, return to app |
| `PiPCoreTests/ReleasePiPConfigurationTests` | No `#if DEBUG` or test-only code on the production PiP path, availability gated only by the declared mode, every reader offers PiP, both plists declare only `audio` |
| `PiPRenderingTests` | Layout clear of the system controls in seven frame sizes (16:9 and 9:16, 360×640 to 1920×1080); portrait text blocks clear of every control and landscape one block; the short verse 1:4 drawn above the play button (screenshot regression); long texts flowing across both blocks with every character drawn once; whole text drawn readably in every layout, no line wider than its block, RTL on every Arabic line, dense marks, long words, digits and punctuation; Hisn counter on one line, RTL and clear of the text up to 1000 in both orientations; one page at the largest size; longest Hisn item paged at 62 px; Quran font; verse 2:282 paged; light and dark; frame previews (`PiPFramePreviewTests`) |
| `PiPProvidersTests` | Quran (first, middle, last, next, previous, long ayah, scroll vs jump), Hisn (first, repetition, last, next, previous, long text, completed chapter, only skip forward counts, counts 1/3/100/101/250, finished item kept in view, pause/close/reopen/relaunch keep the count, last item completes the chapter, screen change, skip back, no production audio), Adhkar (first, middle, last, counter), Dua (first, middle, last), Quran → Hisn switch on real content |

## 13. Physical device status

**NOT_TESTED.** No check below has been run on a device. The device evidence so far is the
earlier POC run (iPhone12,5, iOS 26.6.2: PiP start, background frames, the sample-buffer
source) and one owner screenshot of the portrait setting (2026-10-09, before the two text
blocks): a 9:16 window, the system controls where section 7 puts them, and a short verse
behind play/pause, which this layout fixes in the renderer.

**Build to test:** `IslamicPiPPOC-release-unsigned-ipa-NOT-SIGNED` from the CI run of the PR's
latest commit. It is unsigned and cannot be installed as is; Codemagic's `azkar-release-ipa`
is unsigned too. To run Release on an iPhone, build it from Xcode with your own team:

1. Check out the PR's head commit and open `IslamicPiPPOC.xcodeproj`.
2. Target IslamicPiPPOC, Signing & Capabilities: Automatically manage signing, your Team (a
   free Apple ID works; the app has no entitlements), and a bundle ID of your own in place of
   `com.example.IslamicPiPPOC`. Do not commit the team or the bundle ID.
3. Product › Scheme › Edit Scheme › Run › Build Configuration: Release (Debug adds the PiP test
   tab and is not what ships).
4. On the iPhone, turn on Settings › Privacy & Security › Developer Mode, connect it and trust
   the Mac, then Run. If iOS asks, trust the developer in Settings › General › VPN & Device
   Management. A free Apple ID's install expires after 7 days.

**Controls per section** (from `SampleBufferPiPController`'s playback delegate: `setPlaying`
calls `PiPEngine.setPlaying`, `skipByInterval` calls `PiPEngine.skip`):

| Section | Play / Pause | Skip forward | Skip back |
|---|---|---|---|
| Quran | Next / previous page of a long verse | Next verse | Previous verse |
| Hisn | Next / previous page of a long item | One recitation, then the next item once the count is done | Previous item |
| Adhkar | Next / previous page | Next dhikr (never counts) | Previous dhikr |
| Dua | Next / previous page | Next dua | Previous dua |

**Real examples in the bundled Hisn content:**
- Long item: «أذكار الاستيقاظ من النوم», الذكر 4.
- Short item: «الدعاء لمن لبس ثوباً جديداً», الذكر 2.
- Count 3: «دعاء الركوع», الذكر 1.
- Count 100: «أذكار الصباح», الذكر 18.
- The book has no count above 100; tests cover 101, 250 and 1000.

Each row is PASS, FAIL, BLOCKED or NOT_TESTED. Only a result observed on an iPhone changes a
row; tests and frame previews never do.

| # | Check | Status |
|---|---|---|
| 1 | Entry: «نافذة عائمة» shows and starts PiP from Quran, Hisn, Adhkar and Dua, in Release | NOT_TESTED |
| 2 | Portrait setting: the window is 9:16 and the text is readable with the system controls hidden | NOT_TESTED (an earlier build gave a 9:16 window, 2026-10-09 screenshot) |
| 3 | Portrait with the controls shown: no text behind skip, play/pause or skip; the title, counter and information line stay readable | NOT_TESTED (the 2026-10-09 screenshot, before this layout, had a short verse behind play/pause: FAIL then) |
| 4 | No overlap between the text, the header and the counter | NOT_TESTED |
| 5 | Short text (Quran 1:4, «الدعاء لمن لبس ثوباً جديداً» الذكر 2) and long text (Quran 2:282, «أذكار الاستيقاظ من النوم» الذكر 4) | NOT_TESTED |
| 6 | Diacritics and RTL: marks on their letters, nothing clipped, lines right to left | NOT_TESTED |
| 7 | Resize the window (pinch, smallest and largest): nothing clipped, the text clear of the controls | NOT_TESTED |
| 8 | Pages: each Play shows the next page and each Pause the previous one, at once, stopping at the first and last; the icon follows | NOT_TESTED |
| 9 | Hisn counter: count 3 («دعاء الركوع» الذكر 1) and 100 («أذكار الصباح» الذكر 18) up to «اكتمل ✓», then the next item; the reader shows the same count, and counting on the reader updates the window | NOT_TESTED |
| 10 | Close mid-count (37 of 100) and reopen: «التكرار 38 من 100» | NOT_TESTED |
| 11 | Background, lock and return to the app: the reader is on the item PiP showed | NOT_TESTED |
| 12 | Dark mode, and VoiceOver on the PiP button | NOT_TESTED |
| 13 | Calls and audio interruptions (music, podcast, a phone call): what pauses, and that iOS's own play/pause calls do not turn pages unexpectedly | NOT_TESTED |
| 14 | No black or frozen frame, no stale content after switching sections | NOT_TESTED |
| 15 | Portrait compared with landscape: the same item in both settings, in both phone orientations | NOT_TESTED |
| 16 | Quran, Adhkar and Dua: skip moves one item and stops at the first and last | NOT_TESTED |
| 17 | Quran PiP, then Hisn PiP: one window, Quran position kept | NOT_TESTED |

Record each result with the iPhone model and iOS version.

## 14. Limitations

- No custom PiP buttons exist. The skip buttons carry the system's ±seconds icons, and
  close, return to app and play/pause are always shown (section 5.1).
- In portrait the text avoids the middle row; in landscape the window is too short for two
  blocks, so the middle row covers the text's centre while the controls are shown. The kept
  control places come from one screenshot of one iPhone; on another model or in a smaller
  window the controls may reach further (section 13, rows 3 and 7).
- The text blocks leave the space behind the middle row empty, so a portrait page holds less
  text and a long item has more pages.
- Portrait is a setting, off by default; it applies after reopening the app. Its layout with
  two text blocks has not been seen on a device.
- Play/pause cannot be hidden in a sample-buffer PiP. In text mode it turns pages, and for a
  one-page text it does nothing. Whether iOS redraws its icon at once after each tap is
  device-only behaviour (the app asks it to with `invalidatePlaybackState`).
- With a recording loaded (device-test build only), play/pause drives the recording, so a long
  item's later pages are not reachable in PiP.
- Counting uses the skip-forward button, whose system icon shows seconds, not a count.
- The «اكتمل ✓» view of a finished item lasts until the next skip or a change on the screen.
- Without recordings, the system progress bar shows the place in the container, not time.
- Seeking a recording is in-app only.
- Release declares the audio background mode for PiP; App Review 2.5.4 risk (section 9).
- Starting PiP takes the audio session (section 8).
- iOS can call `setPlaying` by itself, for example on an audio interruption. In text mode
  that turns a page. Whether it happens is device-only (check 13 in section 13).
- Physical device: NOT_TESTED.
