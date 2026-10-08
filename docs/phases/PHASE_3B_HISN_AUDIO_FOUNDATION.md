# Phase 3B: Hisn Al-Muslim audio foundation

Final gate: **PASS_WITH_KNOWN_LIMITATIONS** (section 17).

**Audio infrastructure complete; production audio pack pending rights/assets.**

**PiP integration is NOT implemented in Phase 3B.**

- Branch: `feature/v1-phase-3b-hisn-audio`
- Base: `feature/v1-phase-3a-hisn-reader` at `78197d7` (Phase 3A is not merged and not modified).

## 1. Architecture

```
Hisn reader (SwiftUI, IslamicPiPPOC/Hisn)
  └─ HisnReaderController          HisnReading: owns navigation; tells the player what to load
       ├─ HisnReader / HisnSession  navigation and repetition (Phase 3A, unchanged)
       └─ HisnAudioPlayer           HisnReading: state machine; reports state, never moves the reader
            ├─ HisnAudioEngine          protocol → AVHisnAudioEngine (AVAudioPlayer)
            ├─ HisnAudioSessionControlling → HisnAudioSessionCoordinator (the one AVAudioSession owner)
            └─ HisnAudioRepository      IslamicCore → BundledHisnAudioRepository (hisn_audio.json)
```

| Target | Contains | Imports AVFoundation |
|---|---|---|
| IslamicCore | `HisnAudioManifest`, `HisnAudioAsset`, `HisnAudioSource`, `BundledHisnAudioRepository`, `hisn_audio.json` | no |
| HisnReading | `HisnAudioPlaybackState`, `HisnAudioPlayer`, the engine/session protocols, `HisnReaderController` | no |
| HisnAudioPlayback (new) | `AVHisnAudioEngine`, `HisnAudioSessionCoordinator` | yes (only target that does) |
| App | `HisnAudioControls` view; wiring in `HisnModels.swift` | no |

SwiftUI sees only `HisnAudioPlayer` (state, availability, duration, current time) and calls
play / pause / resume / stop / seek. No AVFoundation type reaches a view. The app's Phase 3A
`HisnReaderModel` moved into the package as `HisnReaderController` so the reader, session,
player and repository chain is testable without a device.

Existing code inspected first: the only audio code in the repository is the PiP test
engine (`PiPEngine.swift`: its own `AVAudioPlayer` chime and its own `AVAudioSession`
setup in `prepare()`). It is PiP experiment code and was neither reused nor changed. No other
`AVAudioSession`, `AVPlayer` or `AVAudioEngine` use existed.

## 2. Audio domain

`HisnAudioAsset`: `id`, `itemId` (stable `HisnItem.id`), `usage` (`PRODUCTION` / `TEST_ONLY`),
`resourceName`, `format` (`m4a`, `mp3`, and `wav` for the generated test fixture),
`durationMilliseconds` (nullable), `byteCount`, `sha256`, `source` (provenance, section 12).

Mapping is by item id only: never by display order, Arabic text, chapter title or array
index, so editorial corrections cannot shift a recording onto another dhikr.

## 3. Manifest

`Packages/IslamicCore/Sources/IslamicCore/Resources/Content/hisn_audio.json`:

```json
{ "formatVersion": 1, "packStatus": "PENDING_RIGHTS_AND_ASSETS", "assets": [] }
```

Files would live in `Resources/Content/HisnAudio/` beside it. The app never builds a path or
searches the file system: it asks the repository.

## 4. Repository

`BundledHisnAudioRepository` (actor; `audio(for:)`, `resourceURL(for:)`, `allAssets()`).
The whole manifest is validated on first use; any problem fails it with
`ContentError` and the reader shows an Arabic error, not a half-checked pack. Rules:

- format version supported; `packStatus` present;
- asset ids unique; one recording per item; every `itemId` is an item of the bundled book;
- usage allowed (the app allows `PRODUCTION` only, so a `TEST_ONLY` asset can never ship as
  Hisn audio);
- format supported and matching the file extension;
- `resourceName` a plain file name (no folder, no `..`, no URL, not hidden); the resolved URL
  must sit directly in the audio directory;
- file present, non-empty, size equal to `byteCount`, SHA-256 equal to `sha256`;
- provenance present: `sourceName` non-empty, `rightsStatus` present and only
  `PENDING_PRE_RELEASE_REVIEW` decodes, unknown fields `null` (empty strings are refused),
  `sourceURL` only `https://` or null, `retrievalDate` `YYYY-MM-DD` or null.

An item without a recording returns nil: a normal state.

## 5. Player

`HisnAudioPlayer` (`@MainActor`, `ObservableObject`): `load(itemId:)`, `play()`, `pause()`,
`resume()`, `stop()`, `seek(to:)`, `togglePlayback()`. Published: `state`, `availability`
(`unknown` / `available` / `unavailable`), `currentAudioItemId`, `currentAsset`, `duration`,
`pausedBySystem`. `currentTime` is read on demand (the view samples it four times a second
only while playing), so playback does not flood state updates.

Engine: `AVAudioPlayer`, the simplest reliable player for short local files (play, pause,
seek, duration, current time, end-of-file, decode errors). No `AVPlayer`, no `AVAudioEngine`,
no streaming.

State machine (`HisnAudioPlaybackState.applying(_:)`), deterministic; a disallowed event
returns nil and the player ignores it (no crash, no change):

| From | Event | To |
|---|---|---|
| any | load | loading |
| loading | loaded | ready |
| ready / paused / finished | play | playing (from finished: from the start) |
| playing | pause | paused |
| paused | resume | playing |
| ready / playing / paused / finished | stop | ready (rewound) |
| ready / playing / paused | seek | same state |
| finished | seek | paused |
| playing | finish | finished |
| any | fail | failed |
| any | unload | idle |

A newer `load` wins over a slower one still running. `next()` / `previous()` are the
reader's (section 9): the player never moves through items by itself.

## 6. AVAudioSession

`HisnAudioSessionCoordinator.shared` is the single owner for Hisn audio: views, the
controller and the player never touch `AVAudioSession` (a test checks that only this file
calls `AVAudioSession.sharedInstance()` in the audio targets).

- Activated only when playback starts (`play` / `resume`), never at launch.
- Category `.playback`, mode `.spokenAudio`. If the session is already `.playback` (the PiP
  test engine sets `.playback` / `.moviePlayback` when it is prepared), the category and mode
  are left as they are, so Hisn playback does not reconfigure PiP.
- Never deactivated in Phase 3B, so stopping a dhikr cannot cut off other in-app audio.
- Background: `.playback` plus the existing `UIBackgroundModes` `audio` let a playing dhikr
  continue when the screen locks or the app goes to the background. `Info.plist` is unchanged.

Known overlap: `PiPEngine.prepare()` also configures the session. That is pre-existing PiP
code that this phase must not touch; Phase 3C has to make the coordinator the only owner.

## 7. Interruptions

| Event | Behaviour |
|---|---|
| Interruption began (call, Siri, another app) | if playing: pause, mark `pausedBySystem` |
| Interruption ended (with or without `shouldResume`) | stay paused; the user resumes |
| Media services reset | the loaded player is dropped, state `failed`; the next load recovers |
| App suspended while paused | nothing to do; position is kept |

## 8. Route changes

| Route change | Behaviour |
|---|---|
| Old device unavailable (headphones unplugged, Bluetooth lost) | if playing: pause (the system convention, avoids sudden loudspeaker output) |
| Any other change (device connected, override, category change) | no action; the route is never overridden |

## 9. Reader integration

- Controls (only when the item has a recording): play / pause (44 pt), stop while playing or
  paused, a progress slider, elapsed time and duration. They sit in the bottom bar above the
  repetition button, in caption and footnote sizes, so the Arabic text stays dominant.
- No recording: nothing is shown. No placeholder or synthetic audio.
- Failure: one line, «التسجيل غير متوفر» / «تعذر تشغيل التسجيل» / «حدث خطأ أثناء تشغيل
  التسجيل». No file paths, error codes or checksums.
- «التالي» / «السابق» / «إعادة»: stop the recording, move the reader, load the new item's
  recording, not playing (autoplay is off and there is no autoplay setting).
- A recording that reaches its end becomes `finished` and stays on the same dhikr.
- Chapter completion unloads the recording; closing the reader stops it.
- Search is unchanged; a result opens the item and its controls appear if it has a recording.

## 10. Repetition

Repetition counting is the Phase 3A button only. A recording ending never counts a
repetition, and counting a repetition does not stop or restart the recording (unless the
count moves the reader to the next item, which stops it like «التالي»). Tests play a count-3
item to the end twice and check the count is still 0.

## 11. Offline

Local files only. No network call, download, retry or CDN. `sourceURL` is recorded for audit
and never opened; the engine refuses non-file URLs. A test scans the IslamicCore, HisnReading
and HisnAudioPlayback sources for `URLSession`, `URLRequest`, download/data tasks, `AVPlayer`,
`AVURLAsset`, `http://` and `NWConnection`.

## 12. Provenance

Every asset carries `sourceName`, `sourceURL`, `reciter`, `narrationStyle`, `retrievalDate`,
`licenseOrRightsStatement`, `rightsStatus`, plus `sha256` and `byteCount`. Unknown values
are `null`. There are no production assets, so there is no real provenance to record yet.

The only audio file in the repository is the test fixture
`Packages/IslamicCore/Tests/HisnAudioTests/Fixtures/HisnAudio/test-silence-1s.wav`: one second
of digital silence written by `tools/content/make_hisn_audio_fixture.py` (deterministic; CI
checks it is reproducible). It is not a recitation, is marked `TEST_ONLY`, lives in the test
target's resources (not in the app bundle), and the app's repository refuses `TEST_ONLY`.

## 13. Rights status

All audio rights: `PENDING_PRE_RELEASE_REVIEW` (the only value the domain accepts). Nothing is
marked licensed, public domain, royalty free or redistributable. No recording was downloaded.
The author's site (binwahaf.com) publishes an audio series but states only «جميع الحقوق
محفوظة» (Phase 2B), so none of it is bundled.

## 14. Tests

New target `HisnAudioTests` (in `swift test`):

| Area | Tests |
|---|---|
| Manifest | production manifest valid and empty; TEST_ONLY refused by the app repository; valid fixture; missing file; empty file; duplicate id; two recordings for one item; unknown item; checksum and byte-count mismatch; unsupported format and extension mismatch; missing provenance, empty source name, no rights status, empty instead of null; rights claims refused; paths outside the bundle; `sourceURL` metadata only; invalid JSON, format version, pack status, duration |
| Repository | load valid asset; item without audio; foreign asset has no URL; invalid manifest |
| Player | initial state; load without playing; unavailable item; play / pause / resume / stop; toggle; seek clamped; finish and replay; failures (pack, decode, session refused, engine refused, error while playing); illegal calls ignored; newer load wins; unload |
| State machine | every valid transition; disallowed transitions return nil |
| Interruptions / routes | pause and stay paused; no change when not playing; headphones removed; other route change ignored; media reset |
| Reader integration | open loads without playing; next stops and loads the next item; unavailable item; previous without autoplay; audio does not move the reader or the saved position; completion does not count a repetition; counting does not stop audio; chapter completion unloads; close stops; reader without audio |
| AVFoundation engine | loads the fixture, duration, seek, stop, unload; rejects non-file and broken files |
| Offline / separation | no network API in the audio sources; no PiP API; only HisnAudioPlayback imports AVFoundation; one session owner |

Regression, CI run 37756031749 on `b8da27f`:

| Check | Result |
|---|---|
| `python3 tools/content/build_content.py --check` | content up to date |
| `python3 tools/content/test_hisn_corrections.py` | OK |
| `python3 tools/content/test_hisn_editorial_review.py` | OK |
| `python3 tools/content/make_hisn_audio_fixture.py --check` | fixture up to date |
| `swift test` | 150 tests, 0 failures (104 existing + 46 new) |
| App build, device and simulator (existing CI commands) | BUILD SUCCEEDED; unsigned IPA packaged; `UIBackgroundModes` audio present |

## 15. Real-device results

**Not performed.** This session has no device, and there is no production recording, so the
device checklist (play, pause, resume, stop, seek, duration, lock screen, background,
interruption, speaker / wired / Bluetooth, VoiceOver) cannot be run against real audio yet.
Nothing in this document claims a device result. The checklist stays open for the first
authorized asset.

## 16. PiP smoke regression

Not run on a device. Statically: `PiPEngine.swift`, `AzkarFrameRenderer.swift`,
`ContentView.swift`, `IslamicPiPPOCApp.swift` and `Info.plist` are byte-identical to Phase 3A
(`git diff 78197d7` is empty for them); the CI app build keeps `UIBackgroundModes` `audio`;
Hisn audio never runs unless the user plays a recording, and there are none in the app. The
on-device PiP smoke test (entry, rendering, background) remains for the user.

## 17. Limitations

- No production audio: the controls never appear in the shipped app until an authorized
  pack is added to `hisn_audio.json`.
- No real-device or PiP on-device verification (sections 15–16).
- Two session configurators exist: the new coordinator and the untouched PiP test engine
  (section 6); Phase 3C must unify them.
- No Now Playing / lock-screen controls (out of scope).
- The fixture is WAV; production formats m4a / mp3 are supported by the model and engine but
  not exercised with a real file.

Final gate: **PASS_WITH_KNOWN_LIMITATIONS**.

## 18. Exclusions

PiP, `AVPictureInPictureController`, PiP rendering, sample buffers, video frames, screen
capture, Broadcast, notifications, widgets, sharing, cloud sync, online streaming, Quran
audio, audio packs, rights acquisition, Hisn content correction, Now Playing.
No Quran, Hisn, dhikr or dua text, numbering, correction manifest or editorial decision
changed; the 7 DEFER cases are unchanged.

Phase 3C is not started.
