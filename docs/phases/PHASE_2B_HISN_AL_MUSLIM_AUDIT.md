# PHASE 2B — HISN AL-MUSLIM AUDIT

Status: RESEARCH / AUDIT ONLY.
- No Swift, JSON, package, project, UI, audio, PiP or content changes.
- This file is the only repository change.

Date: 2026-10-08
Branch: `feature/v1-phase-2b-hisn-audit`, based on `feature/v1-phase-2-content`, the code being audited.

Method and limits:
- Primary sources first: the author's official site binwahaf.com, government-hosted copies, and Apple's guidelines.
- Secondary catalogues (Shamela, Alukah, ddl.ae) were used **only** for bibliographic cross-checks, never as proof of rights.
- The build container cannot download PDFs. Its network proxy blocks binwahaf's CDN, alukah, shamela and risala.prh.gov.sa. The web reader tool *can* open the PDFs, but their Arabic text layer comes out **garbled**, so the printed copyright page could not be read. Everything that depends on reading the book's own pages is marked UNKNOWN.
- This is not legal advice. Each classification says only what the found text supports.

---

## 1. Executive Summary

- **The rights holder publishes the book, but no reuse licence was found.**
  - The author's official site, binwahaf.com, hosts the book page and a downloadable PDF. Its only rights text is the footer "جميع الحقوق محفوظة" ("all rights reserved").
  - No statement was found, on the site or in readable book text, that grants redistribution, app inclusion, conversion to structured data, or commercial use.
  - The printed copyright page could not be read (see Method).
- **The content structure is well understood.**
  - The circulated Arabic edition has **132 numbered chapters** (plus an introduction and "فضل الذكر"), per the Shamela catalogue of the Safeer/Al-Juraisy print.
  - The author's own audio series numbers items **1 to 267**, listed as 262 entries.
  - These counts are indicative and not yet verified against a canonical copy.
- **Several editions exist.**
  - Safeer press with Al-Juraisy distribution (152 pp).
  - Saudi Ministry of Islamic Affairs (Awqaf) colour edition (1421 AH).
  - A PDF on Alukah (160 pp).
  - A PDF on a Saudi government portal (risala.prh.gov.sa).
  - The author's own current PDF (uploaded 2025-12).

  Textual differences between them **could not be determined**.
- **The reference app is a useful capability baseline:** full book, index, search with filters, repeat counter, audio, session resume, share as image, copy, dark mode and reminders. Its listing does not state a content licence, so it is **not evidence** that reuse is allowed.
- **Final gate: BLOCKED_PENDING_PERMISSION.** Source verification is also outstanding (see section 20).

---

## 2. Reference App Capability Baseline

Source: the public App Store listing only (https://apps.apple.com/us/app/id6471274071). No UI, assets or text were copied.

| Capability | Publicly listed? |
|---|---|
| Complete book | Yes ("contains a complete book, Hisn Al-Muslim") |
| Chapters / index | Yes (index) |
| Search | Yes, with filters by source, ruling and repetition count |
| Repeat counter (tasbih) | Yes; haptics, reset, volume-button counting |
| Audio | Yes, audio for well-known adhkar |
| Resume reading / session | Yes, resumes the previous dhikr session on the same day |
| Share | Yes, as image; save to Photos |
| Copy | Mentioned in release notes |
| Dark mode / display options | Yes |
| Reminders / notifications | Yes |
| Favorites | Not listed |
| Widgets | Not listed |

Other listing facts: free, no in-app purchases, 62.3 MB, iOS 13+, "Data Not Collected". The listing names **no** content source or permission. Under Apple 5.2.1, that app's rights are its developer's matter and say nothing about ours.

---

## 3. Canonical Edition Recommendation

**Recommended canonical source, pending verification: the author's own current PDF** on his official website.
- Book page: https://binwahaf.com/ar/book/854/
- PDF: https://cdn.binwahaf.com/uploads/2025/12/حصن-المسلم-من-أذكاء-الكتاب-والسنة.pdf (page dated 2025-12-06)

Reasons:
- It is the only copy found that the author's own site publishes, so its provenance is the strongest.
- It is the most recent copy.

What remains unverified:
- its edition number
- its page count
- its copyright page
- whether it matches the printed Safeer/Al-Juraisy or Ministry editions

**It is not chosen as final.** Section 8 explains why differences cannot yet be ruled out.

---

## 4. Bibliographic Information

| Field | Value | Evidence |
|---|---|---|
| Title | حصن المسلم من أذكار الكتاب والسنة | binwahaf.com/ar/book/854; Shamela 31307 |
| Author | د. سعيد بن علي بن وهف القحطاني | same |
| Origin | Abridged from the author's *الذكر والدعاء والعلاج بالرقى من الكتاب والسنة* | Alukah book page |
| Author's note dated | Safar 1409 AH | risala.prh.gov.sa PDF (front matter, partially readable) |
| Printer / distributor (one print) | مطبعة سفير، الرياض / مؤسسة الجريسي للتوزيع والإعلان | Shamela 31307 front matter |
| Pages | 152 (Shamela, matches print); 160 (Alukah PDF) | Shamela; Alukah |
| Ministry edition | Colour edition, Saudi Ministry of Islamic Affairs, Da'wah and Guidance, 1421 AH | ddl.ae/book/150553 (catalogue only) |
| Translations | The author's site lists the title in 43 languages | binwahaf.com/en/ |
| Edition number of canonical copy | UNKNOWN | copyright page unreadable |
| ISBN / legal deposit | UNKNOWN | same |

---

## 5. Complete Chapter/Index Structure

This is from the Shamela table of contents for the Safeer/Al-Juraisy print (https://shamela.ws/book/31307), used only as a structural cross-check. Front matter is "المقدمة" and "فضل الذكر", followed by **132 numbered chapters**:

1. Waking up
2. Wearing a garment
3. Wearing a new garment
4. For one who wears a new garment
5. Removing a garment
6. Entering the toilet
7. Leaving the toilet
8. Before ablution
9. After ablution
10. Leaving the house
11. Entering the house
12. Going to the mosque
13. Entering the mosque
14. Leaving the mosque
15. The adhan
16. Opening supplication
17. Ruku'
18. Rising from ruku'
19. Sujud
20. Between the two prostrations
21. Prostration of recitation
22. Tashahhud
23. Salawat after tashahhud
24. After the final tashahhud, before salam
25. After salam
26. Istikhara
27. Morning and evening
28. Sleep
29. Turning over at night
30. Fright and loneliness in sleep
31. After a dream
32. Qunut in witr
33. After witr
34. Worry and grief
35. Distress
36. Meeting an enemy or a ruler
37. Fear of a ruler's oppression
38. Against an enemy
39. Fearing a people
40. Doubts in faith
41. Repaying debt
42. Whispering in prayer and recitation
43. Something difficult
44. After a sin
45. Repelling Satan
46. When something disliked happens
47. Congratulating on a newborn
48. Seeking refuge for children
49. Visiting the sick
50. Virtue of visiting the sick
51. A sick person who has despaired
52. Instructing the dying
53. Calamity
54. Closing the eyes of the deceased
55. Funeral prayer
56. A child who died young
57. Condolence
58. Placing the deceased in the grave
59. After burial
60. Visiting graves
61. Wind
62. Thunder
63. Seeking rain
64. Seeing rain
65. After rain
66. Fair weather
67. The new crescent
68. Breaking the fast
69. Before eating
70. After eating
71. Guest for host
72. Hinting for food or drink
73. Breaking the fast at someone's home
74. Fasting person when food is present
75. Fasting person when insulted
76. First fruits
77. Sneezing
78. A non-Muslim who sneezes
79. One who marries
80. Newlyweds; buying an animal
81. Before intercourse
82. Anger
83. Seeing one afflicted
84. In a gathering
85. Expiation of a gathering
86. Reply to "may Allah forgive you"
87. One who does you good
88. Protection from the Dajjal
89. Reply to "I love you for Allah"
90. One who offers his wealth
91. Repaying a loan
92. Fear of shirk
93. Reply to "may Allah bless you"
94. Bad omens
95. Riding
96. Travel
97. Entering a town
98. Entering the market
99. When the mount stumbles
100. Traveller for the resident
101. Resident for the traveller
102. Takbir and tasbih while travelling
103. Traveller at dawn
104. Stopping at a place
105. Returning from travel
106. Pleasing or disliked news
107. Virtue of salawat
108. Spreading salam
109. Returning a non-Muslim's salam
110. Rooster or donkey
111. Dogs barking at night
112. For one you have insulted
113. When a Muslim is praised
114. When a Muslim is commended
115. Talbiyah
116. Takbir at the Black Stone
117. Between the Yemeni Corner and the Black Stone
118. Safa and Marwa
119. Day of Arafah
120. Al-Mash'ar al-Haram
121. Takbir at the jamarat
122. Wonder and pleasant news
123. Upon pleasant news
124. Bodily pain
125. Fear of the evil eye
126. When frightened
127. At slaughter
128. Against the schemes of devils
129. Istighfar and repentance
130. Virtue of tasbih, tahmid, tahlil and takbir
131. How the Prophet ﷺ made tasbih
132. Comprehensive good manners

The chapter titles above are short English descriptions for this audit, not the book's wording. The Arabic titles must come from the canonical copy.

**Item count:** the author's audio series numbers items 1 to 267, in 262 list entries; some entries combine numbers (https://binwahaf.com/ar/audio-book-series/897/). This gives **about 267 numbered items**. It is indicative only and must be counted from the canonical text.

---

## 6. Content Structure

Fields observed in readable excerpts (risala.prh.gov.sa PDF, pages 4–14; binwahaf audio list):

| Proposed field | Supported by source? |
|---|---|
| Chapter number + title | Yes, numbered chapter headings |
| Item number (global, running across chapters) | Yes (1…267 in the author's series) |
| Arabic text | Yes |
| Repetition | Yes, **written inside the text in words** (for example "ثلاثاً"), not as a separate field. A `repeatCount` field would be **our derived metadata**. |
| Source / takhrij | Yes, as **numbered footnotes** "(١)": collection name, volume/page, "برقم", grading such as "وصححه الألباني". |
| Embedded Quran verses | Yes; some items are verses (for example chapter 1 includes Al-Imran 190–200). |
| Notes / author comments | Footnotes contain explanatory remarks as well as takhrij; separation not verified. |

---

## 7. Text Fidelity Findings

- **No machine-readable copy with a reliable text layer was found.** The author's PDF and the government-portal PDF both extract as garbled Arabic: broken ligatures and misplaced diacritics. Any structured text would need **OCR or manual transcription plus a separate, independent verification pass**, which is the Phase 2 `CONTENT_REVIEW_REQUIRED` process.
- The Shamela HTML is a readable transcription. It is a third-party transcription and **not canonical**; it can only serve as a cross-check.
- **Quranic passages inside items** should be taken verbatim from our Tanzil data by verse reference, as Phase 2 already does. The book's own Quran typography must not be retyped. Whether the book's verses match Tanzil Uthmani character for character is **UNKNOWN**, because the book uses its own script and font.
- Special characters to preserve exactly: ﷺ, ﷻ (if present), Arabic parentheses and quotation marks, verse markers, footnote numerals in Arabic-Indic digits, and diacritics. Nothing may be normalised silently.

---

## 8. Edition Differences

| Edition / copy | Where | Pages | Provenance strength | Readable? |
|---|---|---|---|---|
| Author's current PDF | binwahaf.com (official) | UNKNOWN | **Strongest** (author's site) | Garbled text layer |
| Saudi government portal PDF | risala.prh.gov.sa | UNKNOWN | Government host | Garbled; front matter partly readable |
| Ministry (Awqaf) colour edition, 1421 AH | catalogue ddl.ae | UNKNOWN | Catalogue only | Not accessed |
| Safeer / Al-Juraisy print | Shamela transcription | 152 | Third-party transcription | Readable |
| Alukah PDF (added 2013) | alukah.net | 160 | Third-party host | Not downloadable here |

**Textual differences: UNKNOWN.** The differing page counts (152 vs 160) suggest at least layout differences. Item numbering may also differ between older and newer printings; the author's series uses 267. No edition is chosen arbitrarily. The recommendation in section 3 rests on provenance alone.

---

## 9. Copyright / License Findings

Text found:
- binwahaf.com (all pages checked, including the book page and the audio series): footer "جميع الحقوق محفوظة © 2026". There is **no** licence, permission, "printing allowed", "free distribution" or "وقف" statement.
- Alukah page: site footer "حقوق النشر محفوظة". There is no licence for the PDF.
- Shamela: describes itself as a free non-profit project. There is no licence for this book.
- The printed copyright page (حقوق الطبع) of the canonical edition: **UNREADABLE / UNKNOWN**.

A general consideration, not legal advice: the hadith and Quran texts themselves are ancient. The **book**, meaning its selection, arrangement, chapter titles, numbering, takhrij footnotes and comments, is the author's work, and the site reserves all rights.

| # | Question | Classification |
|---|---|---|
| A | Read / download for personal use | **ALLOWED** (the author's site offers the PDF for download) |
| B | Free redistribution of the unchanged book | **REQUIRES_PERMISSION** |
| C | Inside a free mobile app | **REQUIRES_PERMISSION** |
| D | Inside a commercial app | **REQUIRES_PERMISSION** |
| E | Extract text into JSON / database | **REQUIRES_PERMISSION** |
| F | Reformat for mobile UI | **REQUIRES_PERMISSION** |
| G | Add IDs, chapter numbers, repeat counters as metadata | **REQUIRES_PERMISSION** (depends on E) |
| H | Search indexing | **REQUIRES_PERMISSION** (depends on E) |
| I | Favorites / progress state | **REQUIRES_PERMISSION** (depends on C) |
| J | Audio playback | **REQUIRES_PERMISSION** (separate rights, section 12) |
| K | Change punctuation / orthography | **REQUIRES_PERMISSION**; also rejected by our own fidelity rule |
| L | Translation | **REQUIRES_PERMISSION**; translations carry their own rights |
| M | Derivative content | **REQUIRES_PERMISSION** |

Specific answers:

| # | Question | Answer |
|---|---|---|
| 1 | Redistribute unchanged book | REQUIRES_PERMISSION |
| 2 | Text in an iOS app | REQUIRES_PERMISSION |
| 3 | Structured JSON | REQUIRES_PERMISSION |
| 4 | Change presentation/layout | REQUIRES_PERMISSION |
| 5 | Search indexing | REQUIRES_PERMISSION |
| 6 | Favorites | REQUIRES_PERMISSION |
| 7 | Reading progress | REQUIRES_PERMISSION |
| 8 | Repetition counters | REQUIRES_PERMISSION |
| 9 | Audio | REQUIRES_PERMISSION |
| 10 | Monetize | REQUIRES_PERMISSION |
| 11 | App Store distribution | REQUIRES_PERMISSION |
| 12 | Attribution required | UNKNOWN (expected; see section 16) |
| 13 | Specific wording required | UNKNOWN |
| 14 | Permission from rights holder required | Yes. No grant was found, so permission is the only verified path. |
| 15 | Responsible organisation / contact | UNKNOWN (section 17) |

Q14 (whether "وقف لله تعالى" or similar wording must appear): no such wording was found on any page that could be read. **UNKNOWN.**

---

## 10. Digital Transformation Rights

| Transformation | Classification |
|---|---|
| Extract text | REQUIRES_PERMISSION |
| Convert to JSON | REQUIRES_PERMISSION |
| Reorganise into chapters/items | REQUIRES_PERMISSION |
| Assign IDs | REQUIRES_PERMISSION |
| Add metadata | REQUIRES_PERMISSION |
| Repetition counts as structured fields | REQUIRES_PERMISSION |
| Search indexing | REQUIRES_PERMISSION |
| Render in our own UI | REQUIRES_PERMISSION |

The permission request should name each of these uses explicitly. A common Islamic-book notice such as "free printing without deletion, addition or change" does **not** clearly cover structured conversion, even if such a notice is later found in the canonical copy.

---

## 11. App Store Distribution Risk

Apple App Review Guidelines (https://developer.apple.com/app-store/review/guidelines/):
- **5.2.1:** "Don't use protected third-party material such as … copyrighted works … without permission … Apps should be submitted by the person or legal entity that owns or has licensed the intellectual property and other relevant rights."
- **5.2.2:** applies when content comes from a third-party service: "ensure that you are specifically permitted to do so under the service's terms of use. Authorization must be provided upon request."

Practical decision: **we cannot currently show authorization**, so shipping the full book is an unresolved rights blocker. The exact blocker is the **absence of a written permission from the rights holder** covering app inclusion and structured conversion. Other apps on the Store doing this is not evidence for us.

---

## 12. Audio Rights

- **Official audio:** the author's site has an audio series for the whole book (https://binwahaf.com/ar/audio-book-series/897/). It has 262 entries, one lesson page per item, with share and copy controls.
- **Not stated:** the reader's name, the file format, and any download option.
- **Rights:** only the site's "جميع الحقوق محفوظة". In-app playback, offline bundling, per-item audio, streaming, background playback and PiP sync are all **REQUIRES_PERMISSION**, and must be requested separately from the text rights. The reader may hold separate rights.
- **Not implemented, per scope.**

---

## 13. Recommended Data Source

Preferred, in order:
1. **An official machine-readable text** (Word/InDesign/Unicode text or database) obtained **directly from the rights holder** together with the permission. This avoids OCR entirely.
2. The author's current official PDF, transcribed by OCR or by hand, then **independently verified** item by item against the printed edition, using the Phase 2 `CONTENT_REVIEW_REQUIRED` flow.
3. Shamela or other third-party transcriptions: **cross-check only, never canonical.**

Quranic portions use Tanzil by verse reference. Hadith takhrij stays as written in the book.

---

## 14. Proposed Future Domain Model

Proposed only; not created. It is a separate domain from `DhikrItem`.

```
HisnBook        id, title, author, edition, sourceURL, attribution, rightsRef
HisnChapter     id, number (1…132), titleArabic, itemIDs (ordered)
HisnItem        id, number (book's global numbering), chapterID, order,
                arabicText (verbatim), repeatCount (derived, nullable, with
                origin note), references: [HisnReference], quranRefs: [QuranReference],
                notes, reviewStatus (reuse ContentReviewStatus)
HisnReference   footnoteNumber, text (verbatim takhrij), collection?, number?
HisnSession     cursor over items (reuse SessionCursor), chapter-scoped or book-wide
```

- `repeatCount` must keep a pointer to the in-text phrase it was derived from, so the original wording stays authoritative.
- Footnotes stay verbatim.
- The structured `collection` and `number` fields are optional extras and never replace the footnote text.

---

## 15. Proposed Future UX

Not implemented.

- **Home:** Quran · Hisn Al-Muslim · Adhkar · Dua
- **Hisn Al-Muslim:**
  - continue reading
  - full index (132 chapters)
  - search (Arabic, diacritic-insensitive matching on a normalised *index copy*, never on displayed text)
  - chapter list and chapter detail
  - previous/next item
  - repeat counter
  - favorites
  - copy
  - share (text, with attribution)
  - source/reference view (footnotes)
  - reading progress
- **Playback (later, only if audio rights are granted):**
  - normal reading
  - audio
  - PiP and automatic PiP
  - previous/next item
  - repeat current item
  - continuous chapter playback

---

## 16. Required Attribution

- **UNKNOWN until permission terms are received.**
- Minimum expected: title, author's full name, edition, and a link to binwahaf.com.
- Any wording the rights holder requires (for example a "وقف" statement) must be shown exactly as given.

## 17. Required Permission / Contact

To be obtained in writing from the rights holder, before Phase 2C:
1. Inclusion of the full Arabic text in an iOS app distributed on the App Store, free and, if relevant, commercial.
2. Conversion into structured data: JSON, IDs, chapter and item metadata, repeat-count fields, search index.
3. Display in our own UI with our layout, with the wording unchanged.
4. User features over the text: favorites, progress, copy, share.
5. Offline bundling, and future content updates.
6. Required attribution wording, and any required statement.
7. Which edition is canonical, and ideally a source text file.
8. Separately: audio rights (reader, files, offline, per item, PiP/background).

Contact:
- **UNKNOWN.** binwahaf.com shows no contact page or email on any page checked.
- Candidate channels to try (owner action): the author's office through binwahaf.com; the distributor named in the print (مؤسسة الجريسي للتوزيع والإعلان، الرياض); and, for its own edition, the Saudi Ministry of Islamic Affairs, Da'wah and Guidance.
- Who currently holds the rights (the author or another party) must be confirmed through that contact.

---

## 18. Implementation Risks

- **Rights:** shipping without written permission conflicts with App Review 5.2.1. This is the gating risk.
- **Text fidelity:** no clean text layer exists. OCR errors in diacritics are likely, and verifying about 267 items needs a qualified reviewer.
- **Edition drift:** numbering and wording may differ between printings. One edition must be fixed, with a checksum and source record, as was done for Tanzil.
- **Repeat counts:** these are derived from prose such as "ثلاثاً" and "مائة مرة". Mis-derivation changes religious practice, so each derived count needs review.
- **Quran inside items:** mixing the book's Quran text with Tanzil text needs a clear rule. The proposed rule is Tanzil by reference.
- **Scope creep:** notifications, widgets and share-as-image appear in the reference app but are outside V1 rules (no notifications or widgets).

## 19. Phase 2C Implementation Plan

Only after the permission is granted and the source is fixed:
1. Store the permission evidence and the pinned source file (with SHA-256) under `Packages/IslamicCore/Upstream/hisn/`, as done for Tanzil.
2. Prepare the text by transcription or OCR into `tools/content/hisn.source.json`, every item `CONTENT_REVIEW_REQUIRED`.
3. Add generator support in `build_content.py` to produce `hisn.json`, with the `--check` mode in CI.
4. Add domain types `HisnBook`, `HisnChapter`, `HisnItem` and `HisnReference`, plus a `HisnRepository` (actor, bundled source) in IslamicCore. `DhikrItem` stays untouched.
5. Add tests:
   - 132 chapters and the item count match the source
   - ordering
   - verbatim text hash per item
   - Quran references resolve against Tanzil
   - repeat counts present only where derived and reviewed
6. Update `ATTRIBUTION.md` with the required wording.
7. Leave PiP, UI and audio untouched; they belong to later phases.

## 20. Final Gate

**BLOCKED_PENDING_PERMISSION**

Blockers:
1. There is no written permission from the rights holder for app inclusion, structured conversion, or App Store distribution. The author's official site states only "جميع الحقوق محفوظة".
2. The canonical edition's copyright page, edition number and exact text could not be read; the PDF text layers are garbled. Source verification is therefore also outstanding.
3. The rights-holder contact is unknown.

STOP. Nothing implemented. Waiting for product owner review.
