# App Store readiness (Phase 20)

Nothing was submitted. This is the checklist against App Store requirements as of
`feature/v1-release`, with the owner's remaining actions.

## Ready in the project

| Item | State |
|---|---|
| Release build | Builds unsigned in CI (Release, iphoneos), with bundle checks |
| Minimum iOS | 17.0; iPhone and iPad (`TARGETED_DEVICE_FAMILY 1,2`) |
| Display name | «أذكار» |
| Version / build | 1.0 / 1 |
| App icon | 1024 px single-size asset (`AppIcon`); provisional design |
| Accent colour | Light and dark variants |
| Launch screen | Generated |
| Privacy manifest | `PrivacyInfo.xcprivacy`: no tracking, no data collected, UserDefaults `CA92.1` |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` (no encryption beyond the OS) |
| Permissions | Notifications only, asked on use; no usage-description keys needed |
| Network | None (offline app) |
| Test and fixture code | Excluded from production and Release builds; CI fails otherwise |
| Debug-only screens | The PiP test tab is `#if DEBUG` |
| Attribution | In-app About page with the Tanzil notice and link, the MIT notice and the OFL text |
| Privacy statement | In-app About page |

## Owner actions (not done by design)

1. **Bundle identifier.** It is still `com.example.IslamicPiPPOC`. Register the real identifier
   and set it. It was not changed here, per instruction.
2. **Signing.** Set a development team, certificates and profiles. None are in the repository.
3. **App Store Connect:**
   - the app record;
   - description, keywords and category (Reference or Lifestyle);
   - screenshots for iPhone and, because iPad is supported, iPad;
   - support URL;
   - **privacy policy URL** (required). The in-app statement can be its basis.
4. **App Privacy answers:** «Data Not Collected» matches the code and the manifest.
5. **Age rating questionnaire:** no objectionable content.
6. **Device testing:** run a signed build on real iPhone and iPad hardware before submitting.
   The checklist is in `RELEASE_READINESS_REPORT.md`.

## Review risks to resolve first

| Risk | Guideline | Resolution |
|---|---|---|
| ~~`UIBackgroundModes: audio` declared, but no audio ships~~ | 2.5.4 | **Resolved in release hardening.** Release uses `Info.plist`, which has no background modes. Debug keeps `audio` (`Info-Debug.plist`) for the PiP test screen. CI fails if a Release build has a background mode. Add it back when licensed audio ships. |
| Hisn Al-Muslim text without a rights decision | 5.2 (intellectual property) | Rights decision, or release without the Hisn tab |
| Religious texts not yet reviewed | Accuracy (not a guideline, but a product risk) | Scholarly review of non-Quranic adhkar, duas and Hisn decisions |
| iPad layout not checked | 2.1 / 4.0 (completeness and design) | Check on iPad, or make the app iPhone-only |

## Not applicable

- In-app purchases.
- Accounts and sign-in.
- Ads.
- Tracking (no ATT prompt).
- User-generated content.
- Extensions and widgets.

## Status

Not ready to submit. The project side is in place. The blockers are owner decisions (identity,
signing, rights, review, metadata) and device testing.
