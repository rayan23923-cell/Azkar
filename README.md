# Islamic PiP Technical Test

Minimal SwiftUI proof of concept: can iOS Picture in Picture float Arabic azkar text over other apps,
start automatically when the app goes to the background, and update the text while floating?

- Open `IslamicPiPPOC.xcodeproj` (Xcode 16+, iOS 16+), pick your Team, run on a real iPhone.
- Findings and the device test checklist: [PIP_ISLAMIC_POC_REPORT.md](PIP_ISLAMIC_POC_REPORT.md).
- CI (`.github/workflows/build.yml`) only checks that the project compiles; it cannot test PiP.

## Install on iPhone (from Windows, free Apple ID)

1. In [Codemagic](https://codemagic.io), add this repository and start the `pip-azkar-ipa` workflow
   (it reads `codemagic.yaml`). Download `IslamicPiPPOC.ipa` from the build's artifacts.
   The same unsigned IPA is also attached to each GitHub Actions run of `build.yml`.
2. Install [Sideloadly](https://sideloadly.io) on Windows, connect the iPhone by USB, drag the IPA in,
   sign in with your Apple ID and press Start.
3. On the iPhone: Settings > General > VPN & Device Management > trust your Apple ID.
   On iOS 16+ also turn on Settings > Privacy & Security > Developer Mode (the phone restarts).
4. Settings > General > Picture in Picture > Start PiP Automatically = ON, then follow the checklist in
   [PIP_ISLAMIC_POC_REPORT.md](PIP_ISLAMIC_POC_REPORT.md#device-test-checklist).

A free Apple ID signature expires after 7 days; reinstall with Sideloadly to renew it.
If Sideloadly says the bundle ID is taken, change `BUNDLE_ID` in Codemagic's environment variables.
