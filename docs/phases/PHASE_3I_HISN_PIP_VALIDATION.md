# Phase 3I: Hisn PiP validation

The proven path is unchanged:

- `AVPictureInPictureController`;
- `ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`;
- `AVSampleBufferDisplayLayer` fed `CMSampleBuffer`s of `CVPixelBuffer` frames;
- a host-clock `CMTimebase`;
- `HisnPiPCoordinator` above it.

No PiP file was modified.

## Checked in code (CI, fake surface, fake engine, fake audio session, TEST_ONLY fixture)

| Case | Test |
|---|---|
| start / stop, repeated cycles | `testRepeatedStartStopCycles`, Phase 3C lifecycle tests |
| play / pause from the system controls | `testPauseAndPlayFromTheSystemControls`, `testSetPlayingDrivesThePlayer` |
| seek (clamped to the recording, never changes the dhikr) | `testSeekIsClampedToTheRecording`, `testSkipSeeksWithinTheRecordingOnly` |
| interruption (pauses, PiP stays, never auto-resumes) | `testInterruptionPausesAndPiPStays` |
| headphones removed | `testHeadphonesRemovedPausesPlayback` |
| long Arabic text, multiple pages, text unchanged | `testEveryItemPaginatesWithoutChangingTheText` (all 302 items), `testPagesCoverTheTextExactly` |
| item without audio, chapter completion | Phase 3C tests leave PiP |
| no PiP without a recording (production pack) | `testProductionPackHasNoHisnPiP` |
| background / foreground | the heartbeat runs only while the preview is visible or PiP is active (`testHeartbeatOnlyWhileVisibleOrActive`); the app's audio background mode is checked in CI |

## Not done: physical device

Physical-device validation was not possible: this environment has no iPhone. The production
pack has no recordings, so Hisn PiP cannot appear in the production app anyway. The device
checklist in `PHASE_3C_HISN_PIP_INTEGRATION.md` §14 still applies, using the
fixture IPA built by CI.

Physical device: **NOT TESTED**.
