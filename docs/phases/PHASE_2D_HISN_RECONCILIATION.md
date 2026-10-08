# Phase 2D — Hisn Al-Muslim content reconciliation

Branch `feature/v1-phase-2d-hisn-reconciliation`, based on `feature/v1-phase-2c-hisn-content` (`08d84be`).

**Final gate: PASS_WITH_P0_REVIEW_REQUIRED**

This phase changes no bundled text, count, reference or model. It adds an analysis script
(`tools/content/hisn/reconcile.py`), its machine-readable output
(`tools/content/hisn.reconciliation.json`) and this report. Every item stays
`CONTENT_REVIEW_REQUIRED`, and rights stay `PENDING_PRE_RELEASE_REVIEW`.

---

## 1. Executive summary

- **The book is complete in the source.** All 132 book chapters and all 267 numbered book items are
  carried by the bundled GitHub source (asellam/HisnElMuslim). Phase 2C's "7 missing book numbers" and
  most of its "10 unmatched items" were matcher limits, not missing content. Phase 2C matched
  monotonically and in one direction only, so it could not see swapped items, items with extra words,
  or a short text that differs by one word.
- **The 133 vs 132 difference is a single deliberate split.** Morning and evening adhkar are one book
  chapter (27), and the source presents them as two. The book's own instructions support the split:
  it marks items 93–95 «إذا أصبح» and 97 «إذا أمسى», and gives evening wording in footnotes
  («وإذا أمسى قال: …»). The source's evening chapter follows these exactly.
- **The 302 vs 267 difference is explained item by item.** The 35 extra display items are:
  - 13 extra parts from splitting 8 book items into 21 display items
  - 19 evening items that repeat a morning book item
  - 2 copies of the chapter-27 opening line, which the book prints unnumbered
  - 1 evening variant taken from a book footnote

  No source item merges two book items.
- **Repetition:** the 13 conflicts resolve as follows.
  - 3 have a well-evidenced count (one Phase 2C mismatch, two split parts).
  - 2 have a medium-confidence count.
  - 8 should stay nil because the count applies to a phrase or a narration, not the whole item.
  - 1 of those 8 (`hisn-029-06`) could not be verified at all.
- **Quran:** both "fuzzy" matches are complete verses that differ from Tanzil only in spelling
  (ىٰ/ا, الّيل/الليل). The partly unresolved passage is the instruction to recite al-Sajdah
  and al-Mulk.
- **The real content issues are a short, concrete list (34 P0 items):**
  - 9 book-number corrections
  - 3 swapped item pairs
  - 13 repetition decisions
  - 3 Quran citation corrections
  - 8 items whose recited wording differs from the book
  - 3 items that drop a bracketed narration addition
  - 2 items carrying non-dhikr text inside the dhikr
- **References:** the source keeps volume/page but drops the hadith numbers
  (277 of 299 matched items).
  - 22 items have a volume/page that disagrees with the book.
- **Recommendation:**
  - Source strategy B: keep the GitHub source as the base and apply a reviewed list of corrections.
  - Structure option C: canonical 132 chapters / 267 book items, presented as 133 sections and
    302 display items.

## 2. Source comparison

| | Primary (bundled) | Cross-check |
|---|---|---|
| Source | github.com/asellam/HisnElMuslim `hisn.json` (MIT), vendored verbatim, SHA-256 `b30a448e…9d80` | Shamela book 31307 (151 pages, «ترقيم الكتاب موافق للمطبوع», Safeer press edition) and the author's audio list binwahaf.com/ar/audio-book-series/897 |
| Chapters | 133 | 132 |
| Items | 302 (unnumbered) | 267 numbered items |
| Repetition | `Count` integer per item | stated in the text: «(ثلاث مرات)», «[ثلاثاً]», «-ثلاثاً-» |
| References | short line: collection + volume/page | footnotes: collection, volume/page, **hadith number**, grading, Sahih al-Albani cross-references |
| Quran | in `{…}`, sometimes with verse numbers «(190)» | in `{…}`, with «*» between verses |
| Front matter | none | المقدمة + فضل الذكر (2,269 letters, 14 footnotes) |
| Closing «وصلى الله…» | appended to the last item | separate closing line |

**Author's official list.** After fixing a parser gap, the list covers all 267 numbers. Phase 2C read
only 255, because entries written «135:133-» and «115،114-» group several numbers into one recording.

**Method.**
- Every source item is scored against every book item of its mapped chapter, in both directions:
  how much of the source is inside the book item, and how much of the book's dhikr wording (the
  «((…))» part) is inside the source.
- The reference line breaks ties between candidates whose text is the same, such as one phrase said
  ten times versus a hundred times.
- Items shorter than 20 letters must appear literally in the book item. Otherwise they need at least
  75% of their letters and a matching reference.
- Order is no longer forced, so order differences are recorded instead of being hidden.

## 3. Chapter reconciliation

- Chapter order is identical: the 133 source chapters map to the 132 book chapters in increasing order.
- One structural difference:

| Source | Book | Difference |
|---|---|---|
| 27 أذكار الصباح (24 items) | 27 أذكار الصباح والمساء (24 numbered items, 75–98) | split into presentation sections |
| 28 أذكار المساء (22 items) | ↑ same book chapter | |

The split follows the book's own instructions:
- The morning section carries every book item except 97, which the book marks «إذا أمسى».
- The evening section leaves out 93, 94 and 95, which the book marks «إذا أصبح».
- The evening section carries 78 as the evening wording from the book's footnote.

So both sections are faithful to the book. Neither one is an invented chapter.

**Title wording differences (7, P1).** These are edition or wording differences, not structural ones:

| Source | Book |
|---|---|
| 24 الدعاء بعد التشهد الأخير **و**قبل السلام | … قبل السلام |
| 41 دعاء من أصابه **شك** في الإيمان | … **وسوسة** في الإيمان |
| 65 الدعاء إذا **نزل** المطر | … إذا **رأى** المطر |
| 73 الدعاء لمن سقاه أو إذا أراد ذلك | التعريض بالدعاء لطلب الطعام أو الشراب |
| 111 الدعاء عند صياح الديك… | الدعاء عند **سماع** صياح الديك… |
| 117 التكبير إذا أتى **الركن** الأسود | … **الحجر** الأسود |
| 125 ما يقول من أحس وجعاً | ما **يفعل و**يقول من أحس وجعاً |

## 4. Item reconciliation

Full table: `tools/content/hisn.reconciliation.json` → `items` (302 rows). Each row has:
- `sourceItemId`, `sourceChapter`, `sourceOrder`, `sourceText`
- `sourceBookNumber` (Phase 2C), `matchedBookNumber` (this phase)
- `matchType`, `matchQualities`, `similarity`, `sourceInBook`, `bookInSource`
- `wordDifferences`, `repetition`, `quranPassages`, `referenceComparison`
- `reviewFlag`, `recommendedAction`, `reviewPriority`

The reverse view is `bookItems` (267 rows): the source items carrying each book number, coverage,
and bracketed additions.

| matchType | Items |
|---|---|
| EXACT (same letters, or same after spelling bridge) | 177 |
| STRONG (≥95% both ways) | 49 |
| SHORT_TEXT (<20 letters, literal part of the book item) | 32 |
| SPLIT (part of one book item) | 21 |
| WORDING_DIFFERENCE | 14 |
| ORDER_DIFFERENCE | 6 |
| UNMATCHED | 3 |
| MERGED | 0 |
| **Total** | **302** |

- 299 of 302 items now have a book number (Phase 2C had 292). All 267 book numbers are carried.
- 9 book numbers differ from Phase 2C; see section 5 and section 13.
- The primary type is the structural finding. The other qualities stay in `matchQualities`, for
  example an ORDER_DIFFERENCE item can also be EXACT.

## 5. Missing book numbers

None of the seven is missing from the source. Each one was a Phase 2C matching limit.

| Book | Book text (start) | Carried by | Why Phase 2C missed it | Type |
|---|---|---|---|---|
| 2 | لا إله إلا الله وحده لا شريك له… رب اغفر لي | `hisn-001-03` | Swapped with 3. The source also appends the footnote's virtue text «أو دعا استجيب له فإن توضأ وصلى قبلت صلاته» to the dhikr. | order difference + extra text |
| 7 | تبلي ويخلف الله تعالى | `hisn-004-02` | Swapped with 8 | order difference |
| 16 | بسم الله توكلت على الله… | `hisn-010-02` | Swapped with 17 | order difference |
| 93 | لا إله إلا الله وحده… (مائة مرة إذا أصبح) | `hisn-027-20` | Same wording as 92; Phase 2C gave both 27.19 and 27.20 the number 92. The reference and count 100 identify 93. | numbering difference |
| 110 | يقرأ {الم} تنزيل السجدة وتبارك الذي بيده الملك | `hisn-029-14` | The source adds «(سورة السجدة)», «(سورة الملك)» labels, so less of it matched. | wording (editorial labels) |
| 142 | الأذان | `hisn-046-02` | A short text, wrongly matched to 141 by letter overlap | numbering difference |
| 267 | إذا كان جنح الليل… | `hisn-133-01` | The source appends the book's closing «وصلى الله وسلم وبارك على نبينا محمد وعلى آله وأصحابه أجمعين» to the hadith. | extra text |

Result: 0 genuinely missing, 0 duplicates.

## 6. Unmatched source items

The 10 items Phase 2C flagged ITEM_NOT_MATCHED_IN_BOOK:

| Item | Finding | Classification |
|---|---|---|
| `hisn-001-03` | Book 2 (section 5) | order difference; virtue text inside the dhikr |
| `hisn-004-02` | Book 7 | order difference |
| `hisn-010-02` | Book 16 | order difference |
| `hisn-027-01` | «الحمد لله وحده والصلاة والسلام على من لا نبي بعده» is the book's unnumbered opening line of chapter 27 (with its Anas footnote, which the source puts in the reference). | chapter introduction promoted to an item |
| `hisn-028-01` | Same line, repeated in the evening section | chapter introduction (repeat) |
| `hisn-028-05` | «اللهم بك أمسينا وبك أصبحنا… وإليك المصير» is footnote (٢) on Shamela page 58: «وإذا أمسى قال: …». It is the evening wording of book 78. | evening variant from a book footnote |
| `hisn-028-16` | Evening wording of book 89, from the book's footnote | evening variant from a book footnote |
| `hisn-029-14` | Book 110 (section 5) | editorial labels |
| `hisn-041-02` | «ينتهي عما شك فيه». Book 133 is «يستعيذ بالله» + «ينتهي عما **وسوس** فيه». | split part with a one-word wording difference |
| `hisn-133-01` | Book 267 (section 5) | closing doxology appended |

No item is a source error of invented content. Nothing is deleted.

## 7. Split and merged items

8 book items are split into 21 display items. No source item merges two book items.

| Book | Source items | Counts | Assessment |
|---|---|---|---|
| 19 دعاء الذهاب إلى المسجد | `hisn-012-01…04` | 1,1,1,1 | Split on the book's own narration breaks (each part has its own footnote). Acceptable. |
| 20 دخول المسجد | `hisn-013-01…02` | 1,1 | Split into the two du'as. The book's «يبدأ برجله اليمنى» instruction is not in the source. |
| 106 التسبيح عند النوم | `hisn-029-08…10` | 33,33,34 | Each phrase becomes a counted item with exactly the book's counts. A correct split. |
| 114 الرؤيا | `hisn-032-01…04` | 3,3,1,1 | Four actions. Counts follow the book (ثلاثاً, ثلاث مرات, none, none). |
| 133 الوسوسة في الإيمان | `hisn-041-01…02` | 1,1 | Two instructions; the second has «شك» for «وسوس». |
| 160 الصلاة على الطفل | `hisn-057-01…02` | 1,1 | The second part is the book's alternative «وإن قال…». |
| 162 التعزية | `hisn-058-01…02` | 1,1 | Same as 160 |
| 199 فتنة الدجال | `hisn-089-01…02` | 1,1 | Two instructions |

**Model.** The current model already expresses splits:
- Every part keeps the same `bookItemNumber`.
- `order` gives the display order.

This is the proposed relationship:

| Proposed field | Meaning |
|---|---|
| `bookItemNumber` | canonical number (exists) |
| `displayItemGroup` | the book number within a chapter (can be derived; no new field needed) |
| `displayItemOrder` | `order` (exists) |
| `bookItemRelation` | new: DIRECT / SPLIT_PART / EVENING_VARIANT / CHAPTER_INTRODUCTION |

`bookItemRelation` is the only field that cannot be derived today. It is not added in this phase,
because the next content phase needs it only once the relations are reviewed (section 14).

## 8. Repetition conflicts

None of the 13 is resolved by guessing. Nothing in the bundled data changes: all 13 stay `count: nil`
until a reviewer accepts a decision.

| Item | Book | Source count | Book phrase (as written) | Category | Recommended count | Confidence |
|---|---|---|---|---|---|---|
| `hisn-016-05` | 31 | 1 | ثَلاثاً (after the takbir block only) | phrase level | nil | high |
| `hisn-025-01` | 66 | 1 | (ثَلاَثَاً) after أستغفر الله | phrase level | nil | high |
| `hisn-025-02` | 67 | 1 | [ثلاثاً] after the tahlil; **the source omits it** | phrase level + source omission | nil | high |
| `hisn-025-04` | 69 | 1 | (ثلاثاً وثلاثين) for each tasbih phrase | phrase level | nil | high |
| `hisn-027-20` | 93 | 100 | (مائةَ مرَّةٍ إذا أصبح) | resolved: the Phase 2C mismatch | **100** | high |
| `hisn-029-06` | 104 | 3 | none in the book text or footnote | unverified source count | nil | low |
| `hisn-032-03` | 114 | 1 | the counts belong to parts 1–2 | resolved by the split | **1** | high |
| `hisn-032-04` | 114 | 1 | as above | resolved by the split | **1** | high |
| `hisn-119-01` | 236 | 1 | ثَلاَثَ مَرَّاتٍ (in the narration at Safa) | narrative | nil | medium |
| `hisn-125-01` | 243 | 1 | ثَلاَثاً / سَبْعَ مَرَّاتٍ | phrase level | nil | high |
| `hisn-130-02` | 249 | 1 | مِائَةَ مَرَّةٍ (inside the hadith wording) | count inside the hadith | **1** | medium |
| `hisn-130-06` | 253 | 1 | مِائَةَ مَرَّةٍ (inside the hadith wording) | count inside the hadith | **1** | medium |
| `hisn-131-02` | 255 | 10 | عَشْرَ مِرَارٍ (inside the hadith wording) | count inside the hadith | nil | medium |

The Arabic text is untouched in every case. Inline instructions such as «(ثَلَاثًا)» stay as written.

"Phrase level" means the book counts one phrase inside the item, not the whole item. A single
`repeatCount` cannot express that. Showing the inline instruction is correct, and a whole-item
counter would be wrong. A later model could add per-phrase counts. That is outside this phase.

## 9. Quran reconciliation

The source has 25 braced passages; each was located again in Tanzil. Spelling differences between
the Uthmani and common script are bridged: ىٰ/ا inside a word, and الّيل/الليل.

| Status | Passages |
|---|---|
| EXACT (whole verses) | 18 |
| PARTIAL (a phrase within verses, `coversWholeVerses = false`) | 7 |
| FUZZY | 0 |
| UNRESOLVED | 0 |

These are the Phase 2C items that change:

| Item | Phase 2C | Finding | Recommended citation |
|---|---|---|---|
| `hisn-001-04` | 3:190–200, FUZZY, `coversWholeVerses=false` | All 11 verses present. Word-by-word, the only differences are الّيل/الليل (190) and مأوىٰهم/مأواهم (197), both spelling. | 3:190–200, EXACT, `coversWholeVerses=true` |
| `hisn-029-03` | 2:285–286, FUZZY | Both verses complete. Only difference: مولىٰنا/مولانا (spelling) | 2:285–286, EXACT, `coversWholeVerses=true` |
| `hisn-029-14` | PARTIAL: 67:1 found, «ألم * تنزيل …» unresolved | «الم تنزيل» has one match in the whole Quran, 32:1–2. The source labels it «(سورة السجدة)». Both passages are incipits («…»): the item instructs reciting **the whole surahs** al-Sajdah and al-Mulk. | 32:1–2 and 67:1, PARTIAL, plus a surah-recitation note (32, 67) |

**Correctly partial passages:**
- 23:14 «فتبارك الله أحسن الخالقين»
- 43:13–14 «سبحان الذي سخر لنا هذا…», in 2 items
- 2:201 «ربنا آتنا في الدنيا حسنة…»
- 2:158 «إن الصفا والمروة من شعائر الله»

**`hisn-028-03` An-Nas.** The source writes 114:1–6 in parentheses, not braces. Phase 2C already
cites it through the book's braces (EXACT, whole), and that stays.

Only the citation metadata changes in the recommendations above. The source's Quran wording is not
replaced in this phase.

## 10. Reference/takhrij differences

299 matched items were compared with their book footnotes. The comparison covers collection names,
volume/page, hadith numbers and grading words, read on text without diacritics.
- «أهل/أصحاب السنن», «الأربعة» and «إلا النسائي» count as naming the Sunan, so they are formatting,
  not missing information.

| Missing from the source | Items | Kind |
|---|---|---|
| Hadith numbers («برقم …») | 277 | real bibliographic information; the source keeps them in only 44 items |
| A volume/page the book gives | 50, of which **22** carry a different volume/page instead | real; most look like digit slips (8/238 vs 8/337, 4/418 vs 4/318, 2/273 vs 2/373, 3/126 vs 3/1626) |
| A collection the book names | 22 | real (e.g. البيهقي, الحاكم, مالك, ابن السني in 013-01) |
| A grading statement (صححه، حسنه، إسناده…) | 13 | real |

- Per-item detail: `items[].referenceComparison.missingInSource` and `.notInBook`.
- Nothing is copied over and nothing is invented. Every number above comes from a footnote in the
  cross-check transcription.

## 11. Front matter

| Section | In GitHub source | In cross-check | Content |
|---|---|---|---|
| المقدمة | no | yes | author's preface, dated Safar 1409, explaining the book's purpose and its brief takhrij |
| فضل الذكر | no | yes | 4 verses and several hadith on the virtue of dhikr, 14 footnotes |

The book treats both as front matter, outside the numbered 132 chapters. **Recommendation: an optional
informational section.** It is not part of the dhikr reading flow, and it should not be numbered or
counted. The text is not added: the selected source dataset does not contain it, and the
cross-check transcription is not a licensed source.

## 12. Recommended canonical structure

**Option C: a canonical 132-chapter book with presentation sub-sections.**

| Layer | Shape | Evidence |
|---|---|---|
| Canonical chapters | 132, book numbering | Book TOC; all 132 carried, same order |
| Canonical items | 267, book numbering | All 267 carried (section 5); official list has 267 |
| Presentation sections | 133: chapter 27 shown as الصباح / المساء | Book marks «إذا أصبح» (93–95), «إذا أمسى» (97) and gives evening wording in footnotes |
| Display items | 302 (299 linked to a book number) | 267 + 13 split parts + 19 evening repeats + 2 introduction lines + 1 footnote variant |

**Why not Option A or B:**
- Option A (132 with morning/evening merged) would lose the evening wording, which the book itself
  supplies.
- Option B (133 independent sections) would hide that both sections are one numbered book chapter.

**Content source strategy: B.** The current GitHub source remains the base, with specific corrections:
- 177 items are letter-identical and 49 are ≥95% identical.
- Nothing is missing and nothing is invented.
- The defects are a short, enumerable list (section 13).

Option C (making the author's official edition primary) is not needed for quality. It stays the
pre-release comparison target, recorded as `NOT_YET_COMPARED`.

## 13. P0/P1/P2 review priorities

Per item: `items[].reviewPriority` and `items[].recommendedAction`.

| Priority | Items |
|---|---|
| P0 — must resolve before UI/content freeze | **34** |
| P1 — before final release | 249 |
| P2 — may stay review-required | 2 |
| No finding | 17 (still CONTENT_REVIEW_REQUIRED) |

**P0 (34 items):**
- **Book numbering (9):**
  - `001-03`→2
  - `004-02`→7
  - `010-02`→16
  - `027-20`→93 (was 92)
  - `028-16`→89
  - `029-14`→110
  - `041-02`→133
  - `046-02`→142 (was 141)
  - `133-01`→267
- **Order (3 swapped pairs, 6 items):** decide whether to restore the book order.
  - `001-02/03` (book 3/2)
  - `004-01/02` (book 8/7)
  - `010-01/02` (book 17/16)
- **Repetition (13):** section 8. 3 apply a recommended count; 10 need a decision.
- **Quran citations (3):** `001-04`, `029-03`, `029-14` (section 9).
- **Recited wording differs from the book (8):**

  | Item | Book wording | Source wording |
  |---|---|---|
  | `016-01` | «بالثلج والماء» | «بالماء والثلج» |
  | `016-06` | includes «وما أنت أعلم به مني», «ولا حول ولا قوة إلا بالله» | both missing |
  | `017-04` | «استقلّت» | «استقلّ» |
  | `029-15` | «رغبة ورهبة» | «رهبة ورغبة» |
  | `037-02` | «أحول» | «أجول» |
  | `043-01` | «واتفل على يسارك -ثلاثاً-» | «ويتفل على يساره» |
  | `052-02` | «سكرات» | «لسكرات» |
  | `112-01` | «منهنّ» | «منهم» |

- **Bracketed narration additions missing (3):** `016-06`, `017-04`, `025-02` «[ثلاثاً]».
- **Non-dhikr text inside the item (3):**
  - `001-03`: virtue text from the footnote
  - `133-01`: the book's closing doxology
  - `029-14`: surah labels

  The first two would be recited as if they were part of the dhikr.

Several items appear in more than one P0 group, so the groups add up to more than 34.

**P1:**
- hadith numbers and other takhrij detail (277)
- 22 volume/page discrepancies
- confirming the 8 split groups (21 items)
- instruction wording such as «يبدأ برجله اليسرى» (book 21) and «يقول ذلك عقب تشهد المؤذن» (book 23)
- 6 evening-variant links
- deciding whether the chapter-27 opening line is a display item (2)
- 7 chapter-title differences
- front matter

**P2:**
- 2 short exact matches (`088-01`, `094-01`)

No religious wording is placed in P2.

## 14. Proposed next phase

**Phase 2E: Hisn content corrections (data only, gated on P0 review).**

1. The owner or a qualified reviewer decides the P0 list. The reconciliation JSON is the worksheet.
2. Accepted decisions go into a small reviewed override file, for example
   `tools/content/hisn.corrections.json`, applied by `build_content.py`.
   - The vendored upstream stays verbatim.
   - Each override records its evidence.
3. Book numbers, Quran citations and accepted repetition counts are applied. `bookItemRelation`
   is added only if the reviewer accepts the presentation model in section 12.
4. Items stay `CONTENT_REVIEW_REQUIRED` until an independent review marks them `REVIEWED`.

The UI phase for Hisn should start after 2E, so that screens are built on settled structure and counts.

---

### Files

| File | Change |
|---|---|
| `tools/content/hisn/reconcile.py` | new: the reconciliation script (reads the vendored source, the Phase 2C cross-check and the raw cross-check pages) |
| `tools/content/hisn.reconciliation.json` | new: generated table (302 items, 267 book items, 133 chapters, summary) |
| `docs/phases/PHASE_2D_HISN_RECONCILIATION.md` | new: this report |

No Swift source, bundled content, Quran/Dhikr/Dua data, Tanzil data, PiP code, audio or state machine
is touched.

Regenerate the table with:

```
python3 tools/content/hisn/reconcile.py <raw-dir>
```

The raw pages are not committed, as in Phase 2C.

### Checks

- `python3 tools/content/build_content.py --check`: content up to date (quran, adhkar, duas, hisn).
- `swift test` and the app build run in CI on this branch; the result is recorded in the PR.
