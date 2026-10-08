# PIP_V1_ARCHITECTURE_AUDIT

Phase 1 of **Islamic PiP Player V1**. Audit only. **No source code was changed in this phase.**

- Repository: `rayan23923-cell/Azkar`, audited at `main` = `219e304`
- Date: 2026-10-08
- Auditor inputs: the source tree, CI history, and the device results reported by the project owner (iPhone12,5, iOS 26.6.2)

---

## 1. Verdict

**PASS.** The audit is complete. Phase 2 (Domain + Content) is unblocked.

One decision is needed **before Phase 3** (real audio): which Quran recitation source and license to use (section 9). It does not block Phase 2.

---

## 2. What was proven on device (reported by owner, not re-observed by the auditor)

| Item | Result | Note |
|---|---|---|
| `isPictureInPictureSupported` | PASS | iPhone12,5 / iOS 26.6.2 |
| `isPictureInPicturePossible` | PASS | |
| Automatic PiP on leaving the app | PASS | `canStartPictureInPictureAutomaticallyFromInline = true` |
| App kept running in background while PiP active | PASS | frames enqueued while `applicationState == .background` |
| PiP render size | 392×220 | 16:9 from the 1280×720 frames |
| Audio path | PASS | generated chime via `AVAudioPlayer` |
| `AVSampleBufferDisplayLayer` + `ContentSource(sampleBufferDisplayLayer:playbackDelegate:)` | PASS | |
| Renderer after returning to foreground | **Issue** | log showed `renderer failed: Operation Interrupted` |
| Automatic PiP with audio **off** | UNKNOWN | not stated which audio setting was used |
| Arabic legibility at 392×220 | UNKNOWN | not stated |
| PiP skip buttons mapped to next/previous | UNKNOWN | not stated |
| PiP over Safari / other apps for minutes | UNKNOWN | not stated |

If the owner still has the "Copy results" text from that run, attaching it to the repo (`docs/device-runs/`) would turn the UNKNOWN rows into facts.

**Must be preserved in V1 (proven path):**

1. `AVSampleBufferDisplayLayer`, hosted inline in a visible view.
2. `AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer:playbackDelegate:))`, strongly retained.
3. `canStartPictureInPictureAutomaticallyFromInline = true` while a session is playing.
4. `AVPictureInPictureSampleBufferPlaybackDelegate` reporting `isPlaybackPaused == false` while playing.
5. `AVAudioSession` category `.playback` (mode `.moviePlayback`) activated **before** the app leaves the foreground.
6. `UIBackgroundModes = audio`.
7. Frames: BGRA `CVPixelBuffer` → `CMSampleBuffer` with `kCMSampleAttachmentKey_DisplayImmediately`, PTS from a host-clock `CMTimebase` set as the layer's `controlTimebase`.
8. A periodic frame heartbeat (currently 0.5 s). It is part of the configuration that worked; removing it is a change that needs its own device test.

---

## 3. Inventory of the current project

| File | Lines | Role | V1 fate |
|---|---|---|---|
| `IslamicPiPPOC/PiPEngine.swift` | 369 | Everything: audio session, PiP controller, KVO, delegates, content list, 5 s rotation, frame pump, renderer recovery, chime generation, logging, report text | **Split** into PiP, renderer pump, audio, session, logging |
| `IslamicPiPPOC/AzkarFrameRenderer.swift` | 107 | Core Text drawing into 1280×720 BGRA buffer, sample-buffer wrapping | **Keep the sample-buffer part as is**; replace the text layout part with a proper layout engine (section 6) |
| `IslamicPiPPOC/ContentView.swift` | 114 | Test screen, `SampleBufferView` (UIViewRepresentable hosting the layer) | Keep `SampleBufferView`; replace the screen |
| `IslamicPiPPOC/IslamicPiPPOCApp.swift` | 17 | App entry, logs scene phase | Replace |
| `Info.plist` | | `UIBackgroundModes = [audio]` | Keep |
| `IslamicPiPPOC.xcodeproj/project.pbxproj` | | Hand-written, objectVersion 77, one synchronized folder, **one target, no test target** | Replace with XcodeGen (section 8) |
| `project.yml` | | Fallback XcodeGen spec | Becomes the source of truth |
| `.github/workflows/build.yml` | | Unsigned device + simulator build, unsigned IPA artifact | Extend with tests |
| `codemagic.yaml` | | Unsigned IPA for Sideloadly | Keep, add tests step |
| `PIP_ISLAMIC_POC_REPORT.md` | | POC report | Keep as history |
| Assets | none | No asset catalog, no app icon, no fonts, no audio files, no content files | Add in Phases 2, 3, 5 |
| Tests | **none** | | Add in Phase 2 |

Build status at `219e304`: compiles for device and simulator on GitHub Actions (Xcode 26.6). One warning: interface orientations on iPad.

---

## 4. PiP implementation review (`PiPEngine.swift`)

Good:
- Uses only public AVKit APIs; controller is created once and retained.
- KVO on `isPictureInPicturePossible` / `isPictureInPictureActive`.
- Implements all `AVPictureInPictureSampleBufferPlaybackDelegate` methods, including `skipByInterval` and `didTransitionToRenderSize`.
- `restoreUserInterfaceForPictureInPictureStop` completes with `true`.

Problems to fix in V1:
1. **No state machine.** State is spread over booleans (`isPrepared`, `isPlaying`, `isActive`, `isPossible`). Nothing prevents invalid combinations (e.g. PiP active while session stopped).
2. **PiP closed by the user (X) is not handled.** `didStop` only logs; the rotation timer, audio and frame pump keep running in the background with no visible surface.
3. **Audio session is configured inside `prepare()` of the PiP engine.** In V1 the audio service must own the session.
4. **`requiresLinearPlayback = false` with a 24 h fake time range** is how skip buttons appear. That is acceptable (documented delegate API), but the time range should come from the real session (e.g. verse index × duration) so the PiP progress bar means something.
5. **Delegate callbacks hop with `DispatchQueue.main.async`** inconsistently. V1 should mark the PiP adapter `@MainActor` (AVKit calls on main).
6. **Not testable.** AVKit is called directly. V1 needs a `PictureInPictureEngine` protocol with a fake for unit tests. The owner's other repo (`multi_pip`, `PictureInPictureEngine.swift`) already uses exactly this pattern and can be reused as a model.

---

## 5. Renderer and foreground recovery

Current behaviour (`PiPEngine.swift`, `enqueueCurrentFrame`):
- Every 0.5 s re-renders a full 1280×720 frame **on the main thread**, even when nothing changed.
- Recovery = `if renderer.status == .failed { flush() }` before the next enqueue. Nothing reacts to foreground/background, and `requiresFlushToResumeDecoding` (iOS 17+) is not checked.

Likely explanation (inferred, not verified) of the observed `renderer failed: Operation Interrupted`: around the background/foreground transition the system interrupts the video renderer, which then reports `.failed`. The next heartbeat flushes and re-enqueues, so it self-heals within about 0.5 s, but by accident rather than by design.

V1 requirements:
1. One `FrameRenderer` / `VideoSurface` component owns the layer and is the only place that calls `enqueue`/`flush`.
2. Before each enqueue: `if status == .failed || requiresFlushToResumeDecoding { flush() }`, then enqueue the **cached last frame** plus the new one.
3. Observe `AVSampleBufferVideoRenderer.requiresFlushToResumeDecodingDidChangeNotification`, `UIApplication.willEnterForegroundNotification` and `didBecomeActiveNotification`, and PiP `didStop`; on each, flush and re-enqueue the last frame.
4. Render frames off the main thread into a small `CVPixelBufferPool`; cache the frame per content item; the heartbeat re-enqueues the cached buffer with a fresh PTS instead of redrawing.
5. Log every recovery under `[RENDERER]`.
6. Raise the minimum iOS to 17 so only `sampleBufferRenderer` is used (removes the deprecated `displayLayer.enqueue` branch). The test device is on iOS 26.

---

## 6. Arabic rendering review

Current: `NSAttributedString.draw(with:options:)`, system bold 110 pt, `baseWritingDirection = .rightToLeft`, centered, single text block, no fitting.

Arabic shaping itself is handled by Core Text through `NSAttributedString` drawing; this is not naive glyph drawing, so letters will join correctly. Gaps for V1:
- **No fit-to-box.** Long verses (e.g. Al-Baqarah 2:282) will overflow at 110 pt. Need a binary-search font size between a min and max, and paging for text that is still too long at the minimum size.
- **Quran script needs a Quran font.** Uthmani text includes marks (small high letters, pause marks, Unicode U+06D6 to U+06ED) that the system Arabic font may draw badly. Bundle an OFL-licensed Quran font (candidate: *Amiri Quran*, SIL OFL) and register it with `CTFontManagerRegisterFontsForURL`. Adhkar and dua can use the system font or *Amiri*.
- **Line spacing** for harakat must be larger than Latin defaults (`lineHeightMultiple` around 1.4 to 1.6) so stacked diacritics are not clipped.
- **Safe margins:** the PiP window is about 392×220 on this device, and the system draws controls over the edges; keep text inside the central ~80%.
- **Layout:** header (surah or group name + number) small at top, text centered and dominant, a thin progress bar at bottom. No buttons inside the video.
- Must be tested with: long verses, heavily marked text, multi-line wraps, and letters that commonly break (لا، ﷲ، ـٰ، ۛ، ۚ).

Use Core Text (`CTFramesetter`) directly for measurement and drawing, so measurement and drawing use the same engine.

---

## 7. Audio review

Current: `AVAudioPlayer` playing a generated chime WAV in a loop; on/off toggle; interruption notification only logged; no route-change handling; no Now Playing info; no remote commands.

V1 requirements (Phase 3):
- `AudioPlaybackService` (protocol + `AVQueuePlayer`/`AVPlayer` implementation) with `play`, `pause`, `resume`, `stop`, `next`, `previous`, `currentItem`, a published `AudioState`.
- Owns `AVAudioSession`: category `.playback`. Mode: keep `.moviePlayback` (proven). `.spokenAudio` may suit recitation better, but must be device-tested with automatic PiP before switching.
- Interruption handling: pause on `.began`; resume on `.ended` only when `.shouldResume`.
- Route change: pause on `.oldDeviceUnavailable` (headphones unplugged).
- `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` (play/pause/next/previous) so lock screen and Control Center match the session. This also supports the App Store case that the app is a real audio player.
- Per-verse audio files make verse ↔ audio sync trivial (one item per verse). The session advances on `AVPlayerItemDidPlayToEndTime`.
- Text-only sessions (audio off) must still run. Whether automatic PiP starts with audio off is UNKNOWN (see section 2).

---

## 8. Project, tests and CI review

- **Hand-written `project.pbxproj`** works but is hard to extend with test targets and packages. The owner's other repo already uses XcodeGen in CI and Codemagic. Recommendation: make `project.yml` the source of truth, generate the project in CI, and gitignore the generated `.xcodeproj`.
- **Domain and content in a local Swift package** (`Packages/IslamicCore`): pure Swift + Foundation, no UIKit/AVKit. Its tests run with `swift test` on macOS CI quickly and do not need a simulator.
- **App-level tests** (session engine with fake PiP/audio/renderer) in an XCTest target run on an iOS Simulator in CI.
- CI today builds only. Phase 2 adds `swift test` for the package; later phases add the simulator test target.
- Swift language mode 5 with `@MainActor` on UI/PiP/audio types. Moving to Swift 6 strict concurrency is not needed for V1.
- Bundle ID is `com.example.IslamicPiPPOC` in the project and `com.azkar.pippoc` in Codemagic. V1 should pick one real ID.
- `TARGETED_DEVICE_FAMILY = 1,2` causes the orientation warning. V1 should be iPhone-only (`1`) unless iPad is wanted.

---

## 9. Content sourcing (affects Phases 2 and 3)

| Content | Proposed source | License / status | Phase |
|---|---|---|---|
| Quran text | Tanzil Uthmani text (via a package that redistributes it; tanzil.net itself is blocked from the build container) | Tanzil terms: verbatim redistribution allowed with attribution, no modification | 2 |
| Surah metadata (names, ayah counts, Makki/Madani) | Tanzil metadata | Same | 2 |
| Adhkar | Curated subset of *Hisn al-Muslim* (Arabic hadith texts with source: Bukhari, Muslim, etc.) | Arabic hadith text is not copyrighted; the selection must be reviewed by someone qualified before release | 2 |
| Dua | Quranic duas (from the Quran text) + prophetic duas from Hisn al-Muslim | Same | 2 |
| Quran font | Amiri Quran | SIL OFL 1.1 | 2/5 |
| Quran recitation audio | **Decision needed.** Per-verse MP3 sets (e.g. EveryAyah collections) have per-reciter terms; full Quran per reciter is roughly 0.5 to 1 GB, too large to bundle | Licensing and size are **open** | 3 |

Proposed Phase 3 default (to confirm then): bundle a small, clearly licensed sample (e.g. Al-Fatiha and the last juz for one reciter) for V1 testing, with the `AudioRepository` interface ready for downloadable packs later. Remote downloads would add network use, which V1 says to avoid for core content; text stays fully offline either way.

---

## 10. Proposed V1 architecture

```
App (SwiftUI)
 ├─ Features: Home, Quran, Adhkar, Dua, Session, Settings      ← UI state only
 ├─ SessionEngine  (@MainActor, state machine, logging)        ← the only coordinator
 │    ├─ ContentCursor   (Domain: what is current, next/prev, repeat count)
 │    ├─ AudioPlaybackService  (protocol; AVFoundation impl)   ← AudioState
 │    ├─ FrameRenderer  (Core Text → CVPixelBuffer, cache, pool)
 │    └─ PiPController  (protocol; AVKit impl = proven path)   ← PiPState
 └─ Packages/IslamicCore (pure Swift)
      ├─ Domain: QuranSurah, QuranVerse, QuranSession, DhikrGroup, DhikrItem,
      │          DhikrSession, DuaCategory, DuaItem, DuaSession,
      │          SessionState, PlaybackState, PiPState, AudioState
      ├─ Repositories (protocols): QuranRepository, DhikrRepository, DuaRepository
      └─ Bundled implementations reading JSON resources (offline)
```

Session states (as requested): `idle → preparing → ready → playing ⇄ paused`, with PiP sub-states `pipStarting → pipActive`, app sub-states `background / foreground`, and `stopping → stopped`, `error(recoverable)`. PiP and app lifecycle are kept as separate state variables, not merged into the playback state, so "playing + background + pipActive" is representable without combinatorial states. Every transition is logged as `[SESSION] from → to (reason)`.

Logging: `os.Logger` with categories `PIP`, `SESSION`, `AUDIO`, `RENDERER`, `CONTENT`, plus an in-memory ring buffer for an in-app "Copy diagnostics" button (needed for Sideloadly device tests). No personal data is logged.

---

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Refactor breaks the proven PiP path | High | Keep the 8 preserved items (section 2) unchanged; move code, don't rewrite it; device-test after Phase 6 before merging |
| Automatic PiP may require audio actually playing | Medium | Test text-only sessions explicitly in Phase 6 |
| App Review 2.5.4 (background audio for intended purpose) | Medium | Real recitation playback, Now Playing, remote commands; PiP shows the content being played |
| Quran text integrity | High (religious accuracy) | Use Tanzil verbatim, checksum the bundled file in tests (6236 verses, 114 surahs) |
| Recitation audio licensing and size | Blocks Phase 3 content | Decide source before Phase 3 |
| Free Apple ID signing expires every 7 days | Low | Already documented in README |
| No way to run iOS tests in the cloud container | Low | CI on macOS runners (GitHub Actions, Codemagic) |

---

## 12. Phase 2 plan (Domain + Content) — awaiting approval

Branch: `feature/v1-phase-2-content`. PiP code is **not touched**.

1. Create `Packages/IslamicCore` (Swift package, iOS 17 / macOS 14).
2. Domain models: `QuranSurah`, `QuranVerse`, `DhikrGroup` (morning, evening, after prayer, sleep, general), `DhikrItem` (number, Arabic text, source, repeat count, group), `DuaCategory`, `DuaItem`, and the session/cursor types with next/previous and repeat counting. Plus `SessionState`, `PlaybackState`, `PiPState`, `AudioState` as plain enums (no behaviour yet).
3. Repository protocols (`QuranRepository`, `DhikrRepository`, `DuaRepository`) with `async throws` APIs, and bundled JSON implementations. A `RemoteRepository` can be added later behind the same protocols.
4. Content files: full Quran text (Tanzil Uthmani) + surah metadata; an initial curated adhkar set (5 groups) and dua set with sources.
5. Unit tests: repository loading, counts (114 surahs, 6236 verses, Al-Fatiha has 7), Arabic text is non-empty and contains no replacement characters, next/previous at bounds, repeat counting, state enums.
6. CI: add a `swift test` job for the package to `build.yml`; keep the existing app build green.
7. Document results in `docs/phases/PHASE_2.md`, commit, open a PR for review. Not merged until you approve.
