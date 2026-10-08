# Rights and attribution

**STATUS: PENDING_PRE_RELEASE_REVIEW** (an external blocker, not a reason to stop other work).

**No content in this app is claimed to be legally cleared.** This is the record of each source,
its terms as found, and what remains before release.

| Content | Source | Terms found | Status |
|---|---|---|---|
| Quran text (114 / 6236, Uthmani) | Tanzil Quran Text, Uthmani 1.1, tanzil.net | CC BY 3.0 with Tanzil terms: verbatim only, source credited, link to tanzil.net, notice reproduced | Requirements implemented (see below). Review: PENDING_PRE_RELEASE_REVIEW |
| Surah names, juz and page data | Tanzil `quran-data.xml` | As above | As above |
| Hisn Al-Muslim («حصن المسلم من أذكار الكتاب والسنة», سعيد بن علي بن وهف القحطاني) | Transcription from github.com/asellam/HisnElMuslim | MIT (Copyright (c) 2021 Abdellah SELLAM) for the transcription; nothing from the book's rights holder | **PENDING_PRE_RELEASE_REVIEW: release blocker** |
| Adhkar and duas (68 items) | Curated by the project; Quranic items from Tanzil | Tanzil terms for verses; non-Quranic texts are transcribed hadith wording | PENDING_PRE_RELEASE_REVIEW; non-Quranic items await scholarly review |
| Amiri Quran font | Khaled Hosny, via google/fonts `ofl/amiriquran` | SIL Open Font License 1.1 (bundled, shown in app) | OFL obligations met: licence shipped, font not renamed or sold alone |
| App icon | Generated for this project | — | Provisional; the owner may replace it |
| Hisn audio | none | — | PENDING_RIGHTS_AND_ASSETS (empty pack) |
| Quran / adhkar audio | none | — | PENDING_RIGHTS_AND_ASSETS (empty pack) |

## Code and third-party libraries

- **Swift packages:** none from third parties. The only package is the project's own
  `Packages/IslamicCore`, which has no dependencies.
- **Frameworks:** Apple system frameworks only (SwiftUI, UIKit, AVFoundation, AVKit, Core
  Text, Core Graphics, UserNotifications, CryptoKit).
- **Icons:** the app icon was generated for this project. In-app symbols are Apple SF Symbols,
  used through the system APIs as Apple's terms allow.
- **Build tooling (not shipped):** Python scripts in `tools/content`, and fontTools for a
  one-off font coverage check.

## Tanzil requirements and how they are met

- **Verbatim text:** the verse text is never edited (`TanzilFidelityTests`, `build_content.py
  --check`).
- **Source indicated and link to tanzil.net:** Settings → «حول التطبيق», section «نص القرآن
  الكريم», with a link to tanzil.net.
- **Notice reproduced:**
  - the full Tanzil notice is shown on the same page;
  - it is kept in `Content/ATTRIBUTION.md`;
  - the source and licence are written in `quran.json` `source`.

## What the owner must do before release

1. Get a rights decision for Hisn Al-Muslim, or remove the Hisn tab from the release.
2. Have a qualified reviewer approve:
   - the non-Quranic adhkar and duas;
   - the Hisn content decisions (see `HISN_RELEASE_AUDIT.md`).
3. Confirm the attribution wording on the About page with counsel. It is a faithful draft,
   not final legal text.
4. For any audio: licence terms on file per recording, then a READY manifest.

Rights status stays `PENDING_PRE_RELEASE_REVIEW` in code (`ContentRightsStatus` has no cleared
case by design).
