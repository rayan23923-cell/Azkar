# Islamic PiP Technical Test

Minimal SwiftUI proof of concept: can iOS Picture in Picture float Arabic azkar text over other apps,
start automatically when the app goes to the background, and update the text while floating?

- Open `IslamicPiPPOC.xcodeproj` (Xcode 16+, iOS 16+), pick your Team, run on a real iPhone.
- Findings and the device test checklist: [PIP_ISLAMIC_POC_REPORT.md](PIP_ISLAMIC_POC_REPORT.md).
- CI (`.github/workflows/build.yml`) only checks that the project compiles; it cannot test PiP.
