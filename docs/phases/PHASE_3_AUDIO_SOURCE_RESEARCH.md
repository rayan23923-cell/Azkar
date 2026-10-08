# Phase 3 (pre-work): Quran Recitation Audio Source Research

Status: RESEARCH ONLY. No code, project, CI, content or audio files were changed or added.
Date: 2026-10-08
Branch: `feature/v1-phase-3-audio-research` (docs only)

Method and limits:
- Every licence statement below comes from the source's own page, fetched on 2026-10-08. Where no licence text could be found, the source is marked **LICENSE UNKNOWN**. Reputation and popularity were not used as evidence.
- No audio was downloaded. Several audio hosts (everyayah.com, archive.org, mp3quran.net, qurancomplex.gov.sa) are not reachable from the build container, and the brief forbids adding audio. **Every size in section 4 is an estimate** from bitrate × duration and must be measured on real files before any bundle decision.
- Nothing here is legal advice. Apple's approval of a specific app cannot be predicted; section 6 separates what is technically possible from what review might do.

---

## 1. Executive recommendation

No source is selected. The owner decides. Three candidates are worth the owner's attention, in this order:

1. **King Fahd Glorious Qur'an Printing Complex (KFGQPC), official recordings.** This is the only source found whose own page explicitly grants free use "in computer apps". It is the official publisher, not a mirror. However, the reciters, file format, bitrate, and whether files exist **per verse** could not be verified from the page. It is a candidate for class A/B **only after** those facts are confirmed (ideally with written confirmation from the Complex).
2. **Quran Foundation (Quran.com) Audio API.** The terms are clear, but they make it class C: streaming or API use only. Caching is limited to 1 week, there is no build-time bundling, and the Content API credentials must stay server-side, which implies a backend that V1 rules out. It is useful as a future online mode, not for an offline-first V1.
3. **A direct written licence from one reciter or their estate/publisher** (for example via the Complex, or via the reciter's official publisher). This is the only route that gives certain class A rights for a chosen reciter. It needs owner action outside this project.

Sources that cannot be used for V1 redistribution under the brief's rule ("if the license cannot be verified: LICENSE UNKNOWN, do not recommend"):
- EveryAyah: no licence text.
- QuranicAudio: personal use only, commercial use prohibited.
- Internet Archive uploads: third-party uploaders, not shown to be rights holders.
- mp3quran.net: no licence text on its API page.
- QUL / Tarteel: audio credited to EveryAyah and QuranicAudio.
- Hugging Face datasets: audio scraped from EveryAyah.
- alquran.cloud / Islamic Network: contradictory wording, so low confidence.

---

## 2. Comparison table

| Source | Reciter(s) | License | Bundle allowed | Commercial use | Attribution | Verse-by-verse | Format | Full Quran size | V1 suitability | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|
| KFGQPC official recordings (qurancomplex.gov.sa) | Not listed on the licence page ("certified reciters") | Explicit free general use grant ("computer apps, broadcasting channels, internet websites") | Likely yes (apps named explicitly); no conditions stated | Yes, "government and private sectors" | Not required by the text (recommended anyway) | UNVERIFIED | UNVERIFIED | UNVERIFIED (estimate in §4) | **A/B candidate, pending verification** | Licence: Medium. Files: Low |
| Quran Foundation / Quran.com API | Many (API `recitations` list) | QF Developer Terms: audio is "QF Content" | **No** (no build-time bundle without separate written licence) | App monetization allowed; redistribution needs a commercial licence | Required | Yes (verse recitations + segments) | MP3 (via API) | n/a (streaming) | **C, streaming/API only**; needs server-side credentials | High |
| alquran.cloud / Islamic Network | Several (e.g. Alafasy) | ToS §IV: "free, non-commercial redistribution" yet "You may bundle them into a commercial product"; "copyrights lie with the reciters" | Contradictory | Contradictory | Not stated clearly | Yes (per-ayah endpoints in API; not re-verified here) | MP3 | Not verified | **D for bundling**; at most a cautious B with written confirmation | Low |
| EveryAyah.com | Alafasy, Husary, Minshawy, Abdul Basit, Sudais, Maher Al-Muaiqly and more | **LICENSE UNKNOWN** (no licence/terms found) | Unknown | Unknown | Unknown | Yes (`data/<Reciter_bitrate>/SSSAAA.mp3`) | MP3, 32–192 kbps per reciter | Not measured | **D, do not use** | High that no licence is published |
| QuranicAudio.com | Many | "personal use free of charge"; "may not use these files for commercial purposes" | No | **No** | n/a | No (per surah) | MP3 | n/a | **D, do not use** | High |
| Internet Archive `Quran-MP3-Ghamdi` | Saad Al-Ghamdi | "Public Domain" label set by an uploader (2008), not the rights holder | Unverifiable | Unverifiable | n/a | No (per surah) | MP3 | n/a | **D, do not use** | High that rights are unproven |
| Internet Archive `quran-every-ayah` | Mirror of EveryAyah | **LICENSE UNKNOWN** | Unknown | Unknown | Unknown | Yes | MP3 (98.0 GB total, many reciters) | n/a | **D, do not use** | High |
| mp3quran.net (API) | Many | **LICENSE UNKNOWN** (none on API page) | Unknown | Unknown | Unknown | No: per-surah files + ayah timing | MP3 | n/a | **D, do not use** | Medium |
| QUL (qul.tarteel.ai) | Many | **LICENSE UNKNOWN**; credits audio to EveryAyah and QuranicAudio | Unknown | Unknown | Unknown | Yes + segment timing | MP3 | n/a | **D, do not use** | Medium |
| HF `tarteel-ai/everyayah`, `quranlab/quran-audio` | EveryAyah reciters | Dataset metadata "mit" / "mixed"; audio still EveryAyah | No evidence | No evidence | n/a | Yes | Audio / URLs | n/a | **D, do not use** | High |

Class key: **A** safe to bundle · **B** safe to download · **C** streaming/API only · **D** licence unclear, do not use.

---

## 3. License evidence

Short quotes, all fetched 2026-10-08.

**KFGQPC** (https://qurancomplex.gov.sa/en/?p=3979, "Audios" / "Usage License"):
- "the Complex is honoured to offer the digital copies of the voice recordings of Qur'anic recitations"
- "for their free general use in computer apps, broadcasting channels, internet websites"
- Use "in government and private sectors, inside and outside the Kingdom of Saudi Arabia".
- "The Complex is not responsible for any technical or programming mistakes occurring because of using this copy."
- No reciter names, file links, formats, attribution or no-modification conditions appear on that page.

**Quran Foundation developer terms** (https://api-docs.quran.foundation/legal/developer-terms, last updated 2026-10-04):
- Audio returned by the APIs is "QF Content".
- Caching longer than 1 week is not allowed except through the Content Sync APIs, which must be refreshed every 7 days.
- The terms "does not itself authorize distributing a prepackaged database or build-time bundle of QF Content".
- Redistribution "Requires a separate written commercial license".
- Attribution is required. Scraping and bulk extraction are prohibited.

**alquran.cloud / Islamic Network** (https://alquran.cloud/terms-and-conditions, §IV, last updated 14 June 2026):
- "Recitations are licensed to us by the reciters or their estates for free, non-commercial redistribution"
- "You may bundle them into a commercial product, but please note that copyrights lie with the reciters" (they may ask for removal).
- The audio is described as "originally retrieved from GlobalQuran.com".
- There is no per-reciter licence evidence.

**QuranicAudio** (https://quranicaudio.com/about):
- "Mp3s on this site may be downloaded and used for personal use free of charge"
- "you may not use these files for commercial purposes"
- "many of these files have rules and regulations that prevent their sale except by the publishing companies"

**EveryAyah** (https://everyayah.com/recitations_ayat.html, https://everyayah.com/data/recitations.js, https://everyayah.com/old_index.html): no licence, copyright or terms text found.

**Internet Archive:**
- https://archive.org/details/Quran-MP3-Ghamdi: "Public Domain" selected by the uploader.
- https://archive.org/details/quran-every-ayah: no licence, creator listed as everyayah.com, 98.0 GB.

**mp3quran.net** (https://mp3quran.net/eng/api): no licence or terms text. Whole-surah files plus an "ayat timing" endpoint.

**QUL** (https://qul.tarteel.ai/credits): credits EveryAyah.com and QuranicAudio.com for "collecting and providing Quran recitations". No audio licence. The Tarteel terms page (https://www.tarteel.ai/terms) returned no readable text.

**Hugging Face:**
- https://huggingface.co/datasets/tarteel-ai/everyayah: licence field "mit".
- https://huggingface.co/datasets/quranlab/quran-audio: "mixed-per-row-reference-and-cc-by-timing".
- Both datasets' audio originates from EveryAyah.

**Apple** (https://developer.apple.com/app-store/review/guidelines/):
- 5.2.1: "Don't use protected third-party material such as … copyrighted works … without permission … Apps should be submitted by the person or legal entity that owns or has licensed the intellectual property and other relevant rights."
- 5.2.2: "If your app uses, accesses, monetizes access to, or displays content from a third-party service, ensure that you are specifically permitted to do so under the service's terms of use. Authorization must be provided upon request."
- 2.5.4: "Multitasking apps may only use background services for their intended purposes: VoIP, audio playback, …"
- 2.5.1: "Apps may only use public APIs … Apps should use APIs and frameworks for their intended purposes".

The 5.2.2 sentence "Authorization must be provided upon request" is why a written, verifiable permission matters more than a popular mirror.

---

## 4. Size analysis (ESTIMATES, not measured)

Formula: MB ≈ kbps × seconds / 8 / 1000.
- 32 kbps ≈ 0.24 MB/min
- 48 kbps ≈ 0.36 MB/min
- 64 kbps ≈ 0.48 MB/min
- 128 kbps ≈ 0.96 MB/min

Durations vary a lot by reciter and style. Murattal is roughly 20–40 h for the full Quran; mujawwad is much longer. These durations are general estimates, not measured.

| Set | Est. duration (murattal) | MP3 128k | MP3 64k | AAC/M4A 48k | HE-AAC 32k |
|---|---|---|---|---|---|
| Al-Fatiha (7 ayat) | 0.7–1.2 min | 0.7–1.2 MB | 0.35–0.6 MB | 0.25–0.45 MB | 0.2–0.3 MB |
| Juz Amma (78–114) | 60–90 min | 58–86 MB | 29–43 MB | 22–32 MB | 14–22 MB |
| 5 selected surahs (example: Al-Fatiha, Yasin, Al-Kahf, Al-Mulk, Al-Waqi'ah) | 55–80 min | 53–77 MB | 26–38 MB | 20–29 MB | 13–19 MB |
| Full Quran | 20–40 h | 1.2–2.3 GB | 0.6–1.2 GB | 0.43–0.86 GB | 0.29–0.58 GB |

Notes:
- **Per-verse files add overhead.** There are 6,236 files, each with headers and padding, and each may carry a short silence. Expect a few percent more than one continuous file.
- **Transcoding MP3 to AAC is a modification.** Only do it if the licence permits modification or format conversion. KFGQPC's text states no such condition, but this is unconfirmed. QF forbids redistribution anyway.
- **Correction to the Phase 1 audit.** The audit's "roughly 0.5 to 1 GB" for a full Quran fits 64 kbps MP3 for a faster reciter. At 128 kbps or for a slower reciter it can be about 2 GB or more.
- **Per-ayah file count matters for UX.** Bundling Juz Amma per verse means 564 files (78:1 to 114:6) plus 7 for Al-Fatiha.

---

## 5. V1 strategy recommendation

### Product requirement fit

`QuranVerse` ID (for example 2:255) maps to a local file. When the file ends, the cursor advances and the PiP text updates. This fits best with **per-verse files** named `SSSAAA`, the EveryAyah-style convention. That gives one queue item per verse and no timing data.

The alternative is **per-surah files plus verse timing**, where the app seeks inside one file. That works too, but it needs a timing dataset whose own licence must be verified separately. It also makes "advance to next verse" depend on timing accuracy.

### Strategies A–F

| Strategy | Licence implications | App size | UX | Offline | Complexity | App Store risk |
|---|---|---|---|---|---|---|
| **A. Bundle Al-Fatiha + small test set** | Needs class A rights for those files only | +1–5 MB | Works immediately; limited content | Full for the set | Low | Low *if* rights are documented (5.2.1/5.2.2) |
| **B. Bundle Juz Amma** | Class A rights | +22–86 MB (format dependent) | Good for daily short surahs | Full for Juz Amma | Low–Medium | Low–Medium; larger download |
| **C. Bundle selected surahs** | Class A rights | +20–80 MB | Good for popular surahs; gaps elsewhere | Full for the set | Low–Medium | Same as B |
| **D. Full Quran as downloadable packs (per juz / per surah)** | Class A or B rights, and the right to host and serve the files ourselves | App stays small; packs about 15–80 MB each | User chooses what to download; needs progress and storage UI | Full after download | Medium–High (download manager, integrity check, storage management, hosting) | Medium; needs hosting, which V1 forbids as "backend" unless static hosting is accepted |
| **E. Remote download after choosing a reciter** | Class B rights per reciter | Small | Choose reciter, then download | Full after download | High (as D, times reciters) | Medium |
| **F. Streaming only** | Class C is enough (e.g. QF API) | Small | Needs network; no offline | None | Medium; QF requires server-side credentials, i.e. a backend | Low for licence; conflicts with offline-first V1 |

### Recommendation for the owner's consideration (not a decision)

- **Initial bundled sample:** Strategy A, Al-Fatiha plus a few short surahs (for example 112–114), from **one** source with written or explicit app-use permission. This proves the verse queue, background audio and PiP text sync end-to-end in Phase 3 with minimal size and risk.
- **Future downloadable packs:** Strategy D, per juz, only after the rights are confirmed to cover self-hosted redistribution. This would come after V1, because static hosting is a new piece of infrastructure the owner must approve.
- **Full Quran bundled: not recommended.** At 0.3–2.3 GB it would make the app very large to install. Apple's cellular download limit and install-size guidance were not verified in this research and should be checked before any large bundle. It also maximises licence exposure.

---

## 6. Risks

**Licence and content**
- **Main risk: the KFGQPC files are unverified.** The reciter list, formats, and whether per-verse files exist must be confirmed before Phase 3 depends on them. If only per-surah files exist, Phase 3 needs verse timing data with its own verified licence, or an owner-approved splitting step. Splitting is a modification; check it is allowed.
- **Mirrors are not licences.** Many apps use EveryAyah or archive.org files. That says nothing about permission, and 5.2.2 says authorization "must be provided upon request".
- **The reciter's rights can differ from the publisher's.** Even with a publisher grant, an estate may object. Keep the evidence (screenshots and dated copies of the permission pages) in the repo.
- **Text and audio must match.** The bundled text is Tanzil Uthmani (Hafs). The recitation must also be Hafs 'an 'Asim, or verse boundaries and wording can differ. Verify this per reciter.

**Technical (feasible; needs device proof in Phase 3/6)**
- Background audio through `UIBackgroundModes: audio` and an `AVAudioSession` `.playback` category. The POC already declares the mode and proved the audio path on device. Apple's PiP guide says to configure the audio session and background modes to "participate with PiP".
- Queue playback through `AVQueuePlayer` or `AVPlayer`, with an end-of-item notification to advance the `SessionCursor`. This is standard public API, but it is **not yet implemented or tested**.
- **"Operation Interrupted" after foreground**, already seen on device, must be handled together with audio interruptions (calls, Siri, other apps).

**App Review (approval cannot be predicted)**
- **2.5.4:** background audio must be real audio playback the user hears. A silent or placeholder track used only to keep PiP alive is the classic rejection risk. Real recitation audio fits the intended purpose.
- **Automatic PiP:** Apple's PiP guide says "Only begin PiP playback in response to user interaction and never programmatically. The App Store review team rejects apps that fail to follow this requirement." `canStartPictureInPictureAutomaticallyFromInline` starts PiP when the user leaves the app while content is playing. That is the sanctioned automatic path, but the app must not call `startPictureInPicture()` without a user action.
- **PiP showing text instead of video** (rendered frames through `AVSampleBufferDisplayLayer`) is public API, but a reviewer may question it. Pairing it with real audio playback strengthens the "media playback" purpose. **Technically feasible ≠ approved.**
- **5.2.1/5.2.2:** be ready to show the licence for every audio file.

---

## 7. Decision required from owner

The owner needs to choose:
1. Which source to pursue. KFGQPC needs its reciters, format and per-verse availability confirmed. The alternatives are a direct reciter or publisher licence, or streaming-only through Quran Foundation, which needs a backend.
2. Which reciter (riwayah Hafs 'an 'Asim, to match the Tanzil text).
3. The initial bundle scope: A (Al-Fatiha + test set), B (Juz Amma) or C (selected surahs).
4. Whether self-hosted downloadable packs (D/E) are allowed after V1.

If the owner chooses KFGQPC, the next research step is still docs-only: locate the official audio download pages, list the reciters and formats, confirm per-verse files, and save the evidence. Only after that does Phase 3 implementation start.

RECOMMENDED SOURCE:
RECITER:
LICENSE:
BUNDLE STRATEGY:
WHY:

OWNER DECISION REQUIRED
