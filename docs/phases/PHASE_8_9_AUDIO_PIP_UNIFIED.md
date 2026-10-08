# Phases 8–9: Unified audio and unified PiP

## Audio (Phase 8)

There is one player model for every section: `HisnAudioPlayer`, built on the
`HisnAudioEngine` and `HisnAudioSessionControlling` protocols. The AVFoundation side
(`HisnAudioPlayback`) is the only code that touches the system audio session.

| Need | Where |
|---|---|
| Queue, next / previous, continuous play | `AudioQueueController` (ContentAudio) |
| Interruption (pause, never auto-resume) | player, shared |
| Headphones removed (pause) | player, shared |
| Background playback | `UIBackgroundModes` audio; session activated only on play |
| Session ownership | `AudioSessionCoordinator`, one owner |
| Restoration | `AudioQueueSnapshot` (refs, index, time), restored against current content, never auto-plays |
| Packs | `hisn_audio.json` (Hisn) and `content_audio.json` (Quran, adhkar, duas); the same validation |

Both packs are empty and `PENDING_RIGHTS_AND_ASSETS`, so no section plays audio in this
build.

## PiP (Phase 9)

PiP has four roles:

- **Engine:** the app's `SampleBufferPiPSurface`. It is unchanged:
  - AVPictureInPictureController with a ContentSource;
  - AVSampleBufferDisplayLayer;
  - CMSampleBuffer and CVPixelBuffer frames;
  - a host-clock CMTimebase;
  - the sample-buffer playback delegate.
- **Content provider:** a closure returning `HisnPiPContent` (title, text, state, time).
- **Renderer:** the frame renderer, with the text paginator that never changes the text.
- **Playback controller:** the `PiPPlaybackControlling` protocol.
  - `HisnPiPCoordinator` implements it for Hisn.
  - `QueuePiPCoordinator` implements it for any queue (Quran, adhkar).

The only change to the proven path is that the surface now holds its controller through that
protocol instead of the concrete Hisn type. The Hisn PiP and validation tests pass unchanged.
PiP remains manual (never automatic), and it is offered only with a loaded recording.

## Gate

The architecture is PASS (unit tested with fakes). Production audio and PiP are
BLOCKED_BY_RIGHTS (no recordings). Device validation of PiP: NOT PERFORMED.
