# Phase 3A: KFGQPC Audio Verification

Status: VERIFICATION ONLY. No source code, project, CI (on any merge branch), content or audio files were changed or added.
Date: 2026-10-08
Owner's preferred direction (from the owner's message, not chosen here):
- KFGQPC
- Hafs 'an 'Asim
- Sheikh Maher Al-Muaiqly
- per-ayah audio
- test set: Al-Fatihah, Al-Ikhlas, Al-Falaq, An-Nas

**Result: BLOCKED.** The official KFGQPC server could not be reached from any environment available to this research, so none of the file-level facts could be verified. Details are in section 9.

---

## What was tried (all official-source only)

| Attempt | Target | Result |
|---|---|---|
| Direct HTTPS from the build container | `https://qurancomplex.gov.sa/en/?p=3979` | Proxy refused: `CONNECT tunnel failed, response 403` |
| Web fetch tool | `https://qurancomplex.gov.sa/en/?p=3979` | Returned the page **text** (licence wording below) but **no hyperlinks at all**. The page's audio list and download buttons did not render, likely because they are built by JavaScript. |
| Web fetch tool | `https://qurancomplex.gov.sa/?p=3979` (Arabic) and `/en/wp-json/wp/v2/pages/3979` | `ConnectTimeout` |
| Temporary GitHub Actions runner (ubuntu-latest), curl with a browser user agent, 60 s timeout | Both URLs above | `Connection timed out after 60001 milliseconds`, 0 bytes, both URLs |

Conclusion: qurancomplex.gov.sa does not accept connections from the cloud networks used here, which looks like a regional or network-level restriction. This could not be confirmed further.

Third-party mirrors were found in web search (archive.org, surahquran.com and others). They were **not used**, per the owner's rule. Web search did not surface any official KFGQPC audio subdomain or file host.

Housekeeping: the temporary runner probe lives on branch `scratch/kfgqpc-probe`. It holds only a workflow file and empty logs, no audio, and is not part of any PR. Deleting the branch from this environment failed (the remote hung up); it can be deleted from GitHub's branch page.

---

## 1. Source

- Official page: https://qurancomplex.gov.sa/en/?p=3979 (King Fahd Glorious Qur'an Printing Complex, "Audios" / "Usage License").
- **Official "Download whole Ayat" URL for Maher Al-Muaiqly: NOT VERIFIED.** The URL could not be read from the page, and the server was unreachable.

## 2. License

Official wording, reconfirmed from https://qurancomplex.gov.sa/en/?p=3979 (text retrieved 2026-10-08; the fetch tool may have served it from a short-lived cache):

> "In accordance with the approval of the Honourable Minister of Islamic Affairs, Daʻwah and Guidance, the General Supervisor of King Fahd Glorious Qur'an Printing Complex, the Complex is honoured to offer the digital copies of the voice recordings of Qur'anic recitations appearing on this page for their free general use in computer apps, broadcasting channels, internet websites, and for use in government and private sectors, inside and outside the Kingdom of Saudi Arabia. The Complex is not responsible for any technical or programming mistakes occurring because of using this copy."

What the text does and does not say, without expanding it:
- It grants **free general use** in computer apps, broadcasting channels and internet websites, in government and private sectors, inside and outside Saudi Arabia.
- The grant covers recordings "**appearing on this page**". Whether Maher Al-Muaiqly's per-ayah set appears on that page is **not verified** (see above).
- It says **nothing** about modification, transcoding, trimming, sublicensing, attribution, sale, or ownership. None of these is claimed here. Converting MP3 to AAC or trimming silence would therefore be an **unconfirmed** use.

## 3. Reciter

- Name: Maher Al-Muaiqly (owner's preference)
- Riwayah: Hafs 'an 'Asim (owner's requirement)
- **Whether the KFGQPC set for this reciter exists and is labelled Hafs 'an 'Asim on the official page: NOT VERIFIED.**

## 4. Audio structure

| Item | Status |
|---|---|
| Per-ayah files | UNKNOWN |
| Filename convention | UNKNOWN |
| Format | UNKNOWN |
| Bitrate | UNKNOWN |
| Sample rate | UNKNOWN |
| Total files | UNKNOWN |
| Archive structure (single ZIP / per surah / per file) | UNKNOWN |
| Separate basmala or isti'adha files | UNKNOWN |

No partial download, directory listing, manifest or ZIP central directory could be read, because every option needs a connection to the official server.

## 5. Mapping

**Not confirmed.**

The target side is known. Our Tanzil Uthmani data (`Packages/IslamicCore/Upstream/tanzil/quran-uthmani.xml`, Phase 2) has:
- 114 surahs, 6,236 `<aya>` elements, Hafs/Kufan numbering.
- **Al-Fatihah:** 1:1 *is* the basmala ("بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ"), so the basmala is an ayah there.
- **Other surahs except At-Tawbah:** the basmala is a separate `bismillah` attribute, not an ayah. For example, surah 2 and surah 112 carry it.
- **Surah 9:** no basmala.

A deterministic rule would be "file `SSSAAA` → `QuranVerse(surahId: SSS, ayahNumber: AAA)`". That convention is **NOT assumed**. It must be read from the official files.

Points to check once files are visible:
- (a) Does Al-Fatihah's file 1 contain the basmala as ayah 1? It should under Hafs.
- (b) For surahs 112–114, does ayah 1's file start with a recited basmala, or is the basmala a separate file (for example an `xxx000` file or a shared basmala file)? If it is a separate file, it must not be counted as an ayah. The player would then need a policy for playing it before ayah 1, which is an owner decision.
- (c) Is there exactly one file per ayah, with no merged ayat?

## 6. Test set

| Surah | Expected ayat (Tanzil, Hafs) | Verified files | Result |
|---|---|---|---|
| Al-Fatihah (1) | 7 (basmala = 1:1) | not verifiable | UNKNOWN |
| Al-Ikhlas (112) | 4 | not verifiable | UNKNOWN |
| Al-Falaq (113) | 5 | not verifiable | UNKNOWN |
| An-Nas (114) | 6 | not verifiable | UNKNOWN |

Expected ayah files: 7 + 4 + 5 + 6 = **22**. Any basmala files would be listed separately and not counted. Whether these four surahs can be obtained independently of a full archive is **UNKNOWN**.

## 7. License confidence

**UNKNOWN.** The general usage grant is clear and was quoted from the official page. However, it is not verified that this reciter's per-ayah set is among the recordings "appearing on this page". There is also no statement on modification or transcoding.

## 8. Technical confidence

**UNKNOWN.** No file-level fact could be observed.

## 9. Phase 3 readiness

**BLOCKED**

Missing evidence, all of which requires reading the official KFGQPC server:
1. The official "Download whole Ayat" URL for Maher Al-Muaiqly, Hafs 'an 'Asim.
2. Confirmation that this set is listed on the licensed page (p=3979) or is covered by the same usage statement.
3. Per-ayah structure: one file per ayah.
4. The filename convention and its deterministic mapping to `QuranVerse(surahId, ayahNumber)`.
5. Format, bitrate and sample rate.
6. Total file count (6,236 or explained differences) and any basmala or extra files.
7. File counts for surahs 1, 112, 113 and 114 (7, 4, 5, 6).
8. Hafs 'an 'Asim labelling on the official page.

Ways to unblock, for the owner to choose. Nothing here was done:
- **A. The owner opens the official page in their browser** (it loads where they are) and pastes here:
  - the exact "Download whole Ayat" link for Maher Al-Muaiqly
  - a screenshot of the reciter row showing the riwayah

  If the link is a ZIP, the server may allow reading only the ZIP's file list with HTTP range requests, but only from a network that can reach the server.
- **B. The owner downloads the official archive on their own computer** and connects that folder to this project. The ZIP's file list, names, counts and format could then be read in place without extracting or committing any audio, and the 22 test-set files could be inspected.
- **C.** Run the verification from a machine or CI runner located where qurancomplex.gov.sa is reachable.

STOP. Nothing implemented. Waiting for owner approval.
