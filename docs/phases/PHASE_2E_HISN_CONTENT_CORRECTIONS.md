# Phase 2E: Hisn Al-Muslim content corrections

Status: implementation complete, editorial review still required.
Final gate: **PASS_WITH_P0_REVIEW_REQUIRED** (section 15).

This phase turns the Phase 2D reconciliation findings into an auditable correction
manifest and applies only the decisions that were accepted. It distinguishes three things
throughout:

- **Implemented corrections**: accepted manifest entries the build applies (book item
  numbers, canonical order, repetition counts, Quran citations, relations, presentation
  sections). None of them changes a letter of the Arabic text.
- **Identified discrepancies**: entries recorded as `OBSERVED_DIFFERENCE` or
  `OBSERVATION`. They are attached to each item and never applied.
- **Pending editorial review**: entries in `PENDING_DECISION`, and every item, which stays
  `CONTENT_REVIEW_REQUIRED`. Accepting a correction decision is not an editorial review.

## 1. Objective

Apply the P0 structural corrections from Phase 2D with evidence, establish the canonical
book structure (132 chapters / 267 items) beside the source's presentation structure
(133 sections / 302 items), and record every other discrepancy without altering religious
text, inferring words, or importing bibliographic data.

## 2. Branch and base

- Branch: `feature/v1-phase-2e-hisn-content-corrections`
- Base: `feature/v1-phase-2d-hisn-reconciliation` at `cdfbe06` (the Phase 2D head).
  The request named `08d84be` as the base; that is the Phase 2C head and an ancestor of
  `cdfbe06`. Phase 2E needs the 2D reconciliation files, so it is built on the 2D head.
- PR base: `feature/v1-phase-2d-hisn-reconciliation`. Not merged.

## 3. Upstream hash

`Packages/IslamicCore/Upstream/hisn/asellam/hisn.json` is byte-for-byte unchanged:

```
b30a448ef40184b0422c40bd3c372bf2b25bfb5b0539fd3699e6b4fba9459d80
```

The manifest records this hash in `source.upstreamSha256`. `build_content.py` refuses to
build when the file's hash differs, and the Swift test `testUpstreamFileIsUnchanged`
checks it again.

## 4. Manifest schema

File: `tools/content/hisn.corrections.json` (82 entries, sha256
`8df14088ef713c15b2460ae1ba9d2262008615a46aae55305cc6f8c3a8043bc5`).

```
{
  "schemaVersion": 1,
  "source": { "phase": "2E", "reconciliation", "reconciliationReport", "upstreamFile", "upstreamSha256" },
  "reviewStatuses": { status: meaning },
  "corrections": [
    {
      "id": "HISN-CORR-NNN",
      "sourceItemId": "hisn-CCC-II" | null,
      "type": one of the types below,
      "target": { "sourceItemId" } | { "sourceItemIds": [...] } | { "chapterId" } | { "scope": "BOOK" },
      "before": the value the cross-check mapping produced (checked by the build),
      "after": the value to apply, or null for record-only entries,
      "evidence": { "source", "reference", "reason", ...supporting data copied from Phase 2D },
      "confidence": "HIGH" | "MEDIUM" | "LOW",
      "reviewStatus": see below,
      "reviewPriority": "P0" | "P1" | "P2",
      "acceptedBy": who accepted it (accepted entries)
    }
  ]
}
```

Types: `BOOK_ITEM_NUMBER`, `CANONICAL_ORDER`, `REPETITION_COUNT`, `QURAN_CITATION`,
`BOOK_ITEM_RELATION`, `TEXT_DISCREPANCY`, `NON_DHIKR_TEXT`, `REFERENCE_METADATA`, plus one
added type, `PRESENTATION_SECTION`, which records how book chapter 27 is shown as two
sections.

Review statuses:

| Status | Applied | Meaning |
|---|---|---|
| `ACCEPTED` | yes | The correction decision is accepted. Not an editorial review. |
| `ACCEPTED_TEXT_CORRECTION` | yes | An exact text replacement the owner accepted (`acceptedBy` required). **None exist.** |
| `PENDING_DECISION` | no | Proposed with evidence; applied only after the owner accepts it. |
| `OBSERVED_DIFFERENCE` | no | A recorded discrepancy. |
| `OBSERVATION` | no | A recorded finding the build checks for consistency. |

Evidence: every entry's `evidence.reference` points at the Phase 2D report section and the
reconciliation record it comes from, and carries the book text, footnote or word
differences it rests on, copied from `hisn.reconciliation.json` or the source text. Non-dhikr
excerpts are sliced from the source text itself. No evidence comes from memory or from a
generated correction.

### Build pipeline

`tools/content/build_content.py`: upstream text → cross-check mapping (Phase 2C) →
correction manifest → `hisn.json`. There is no per-item logic in the code; everything
item-specific is in the manifest. The build stops when:

- an entry names an item or chapter that does not exist;
- a book item number is outside 1...267, or belongs to another book chapter;
- a Quran reference is outside the surah, or a citation is malformed;
- `evidence.source/reference/reason` is missing or vague, or `reviewStatus` is missing;
- an entry is accepted at LOW confidence, or at MEDIUM without `acceptedBy`;
- a record-only type (`NON_DHIKR_TEXT`, `REFERENCE_METADATA`) or a text change without
  `ACCEPTED_TEXT_CORRECTION` is accepted;
- two accepted entries set the same value of the same item (conflict);
- an entry's `before` differs from the mapped value;
- a canonical book number 1...267 is carried by no item;
- one book number is carried by unrelated sections, or by non-adjacent items of a section;
- relations contradict (numbered introduction, evening variant outside the evening section,
  explicit relation on a split part, item with neither number nor relation);
- a display/book order inversion has no accepted `CANONICAL_ORDER` entry, or the derived
  order differs from the entry;
- the split groups differ from the recorded `OBSERVATION` entries;
- the upstream hash differs from `source.upstreamSha256`.

`tools/content/test_hisn_corrections.py` checks each of these by editing a copy of the
manifest (18 cases, run in CI).

New output fields: item `bookItemRelation` and `corrections {applied, open}` (manifest ids);
citation `recitesWholeSurah`; chapter `presentationSection`; `book.provenance.corrections`
(manifest path, sha256 and counts). Phase 2C `reviewFlags` are kept unchanged as history.

## 5. Accepted corrections (implemented)

### Book item numbers (P0, HIGH, 9)

| Entry | Item | Before | After | Basis |
|---|---|---|---|---|
| HISN-CORR-001 | hisn-001-03 | null | 2 | Book dhikr fully inside the source, reference identical; listed after 3 |
| HISN-CORR-002 | hisn-004-02 | null | 7 | Letter-identical, same footnote; listed after 8 |
| HISN-CORR-003 | hisn-010-02 | null | 16 | Letter-identical, same footnote; listed after 17 |
| HISN-CORR-004 | hisn-027-20 | 92 | 93 | Hundred-times virtue, Bukhari 4/95, source count 100 |
| HISN-CORR-005 | hisn-028-16 | null | 89 | Book footnote gives this evening wording for 89 |
| HISN-CORR-006 | hisn-029-14 | null | 110 | Book wording fully inside the source |
| HISN-CORR-007 | hisn-041-02 | null | 133 | Second half of 133, same footnote |
| HISN-CORR-008 | hisn-046-02 | 141 | 142 | Letter-identical to 142 «الأذان» |
| HISN-CORR-009 | hisn-133-01 | null | 267 | Book wording fully inside the source |

No other number was inferred. `hisn-028-05` → 78 is recorded as `PENDING_DECISION`
(HISN-CORR-010).

### Canonical order (P0, HIGH, 3)

| Entry | Display order (kept) | Book order |
|---|---|---|
| HISN-CORR-011 | hisn-001-02, hisn-001-03 | hisn-001-03 (2), hisn-001-02 (3) |
| HISN-CORR-012 | hisn-004-01, hisn-004-02 | hisn-004-02 (7), hisn-004-01 (8) |
| HISN-CORR-013 | hisn-010-01, hisn-010-02 | hisn-010-02 (16), hisn-010-01 (17) |

The upstream order is not changed. Book order is derived (by book item number; an
introduction first; an unnumbered item after the one before it) both by the build, which
checks it against these entries, and by `HisnChapter.itemsInBookOrder` in Swift. These
three chapters are the only ones where the two orders differ.

### Repetition (P0)

Applied counts (HIGH): hisn-027-20 → 100, hisn-032-03 → 1, hisn-032-04 → 1.
Kept nil (accepted decision, no value changed): hisn-016-05, hisn-025-01, hisn-025-02,
hisn-025-04, hisn-119-01, hisn-125-01, hisn-131-02. See section 9.

### Quran citations (P0, HIGH, 3)

| Entry | Item | Before | After |
|---|---|---|---|
| HISN-CORR-027 | hisn-001-04 | RESOLVED, 3:190–200 FUZZY, partial verses | RESOLVED, 3:190–200 EXACT, whole verses |
| HISN-CORR-028 | hisn-029-03 | RESOLVED, 2:285–286 FUZZY, partial verses | RESOLVED, 2:285–286 EXACT, whole verses |
| HISN-CORR-029 | hisn-029-14 | PARTIAL, 67:1 only | RESOLVED, 32:1–2 and 67:1, incipits, `recitesWholeSurah` |

### Structure (P1, HIGH)

- HISN-CORR-030/031: `hisn-ch-027` is `MORNING` (27A), `hisn-ch-028` is `EVENING` (27B),
  both book chapter 27.
- HISN-CORR-032/033: `hisn-027-01`, `hisn-028-01` are `CHAPTER_INTRODUCTION`.
- HISN-CORR-034…039: `hisn-028-04/05/07/08/16/17` are `EVENING_VARIANT`, each with the
  book footnote it comes from.

All accepted entries carry `acceptedBy: "Project owner, Phase 2E instructions (2026-10-08)"`,
because each is one the Phase 2E request listed explicitly.

## 6. Observation-only discrepancies (identified, not applied)

### Text discrepancies (P0, `OBSERVED_DIFFERENCE`)

| Entry | Item | Book | Source | Kind |
|---|---|---|---|---|
| HISN-CORR-048 | hisn-016-01 | بالثلج والماء | بالماء والثلج | wording |
| HISN-CORR-049 | hisn-016-06 | [وما أنت أعلم به مني], [ولا حول ولا قوة إلا بالله] | both absent | wording, bracketed addition |
| HISN-CORR-050 | hisn-017-04 | [وما استقلّت به قدمي] | وما استقلّ به قدمي | wording, bracketed addition |
| HISN-CORR-051 | hisn-025-02 | [ثلاثاً] | absent | bracketed addition |
| HISN-CORR-052 | hisn-029-15 | رغبةً ورهبةً | رهبةً ورغبةً | wording |
| HISN-CORR-053 | hisn-037-02 | بك أحول | بك أجول | wording |
| HISN-CORR-054 | hisn-043-01 | واتفل على يسارك -ثلاثاً- | ويتفل على يساره | wording |
| HISN-CORR-055 | hisn-052-02 | إن للموت سكرات | إن للموت لسكرات | wording |
| HISN-CORR-056 | hisn-112-01 | منهنّ | منهم | wording |

No bracketed addition was inserted and no word was changed. A change would need an
`ACCEPTED_TEXT_CORRECTION` entry with the full replacement text and `acceptedBy`.

### Non-dhikr text inside items (P0, `OBSERVED_DIFFERENCE`)

| Entry | Item | Excerpt (verbatim from the source) | What it is |
|---|---|---|---|
| HISN-CORR-057 | hisn-001-03 | أَوْ دَعَا اسْتُجِيبَ لَهُ فَإِنْ تَوَضَّأَ وَصَلَّى قُبِلَتْ صَلَاتَهُ | virtue text from the book's footnote |
| HISN-CORR-058 | hisn-133-01 | وَصَلَّى اللَّهُ وَسَلَّمَ وَبَارَكَ عَلَى نَبِيِّنَا مُحَمَّدٍ… | the book's closing doxology |
| HISN-CORR-059 | hisn-029-14 | (سُورَةُ السَّجْدَة) and (سُورَةُ المُلْكِ) | surah labels |

Nothing was deleted. The build checks that each excerpt occurs in the item.

### Split groups (P1, `OBSERVATION`, 8)

Book items 19, 20, 106, 114, 133, 160, 162 and 199 are each shown as several display items
(HISN-CORR-040…047). `SPLIT_PART` is derived from the mapping; the build checks the
derived groups equal these entries.

### Reference metadata (P1)

22 volume/page conflicts (HISN-CORR-060…081) and one book-wide entry (HISN-CORR-082);
see section 11.

## 7. Canonical structure: 132 chapters, 267 items

`HisnBook.canonicalChapters` groups presentation sections by `bookChapterNumber`:
132 canonical chapters, numbers 1...132. Every book item 1...267 is carried by at least
one display item; concatenating each canonical chapter's distinct book numbers gives
exactly 1...267 in order. Missing: 0. Duplicate mappings outside the allowed relations: 0.

There is no 133rd canonical chapter. Chapter 27 is one canonical chapter shown as 27A and
27B.

## 8. Presentation mapping: 133 sections, 302 items

| | Count |
|---|---|
| Presentation sections | 133 |
| Display items | 302 |
| `DIRECT` | 273 |
| `SPLIT_PART` | 21 (8 book items) |
| `EVENING_VARIANT` | 6 |
| `CHAPTER_INTRODUCTION` | 2 |
| Items without a book number | 3 (the two introductions, and hisn-028-05 pending 78) |

A book number may appear more than once only as consecutive split parts in one section, or
once in each of the morning and evening sections of chapter 27 (the book's items 75–98
are said morning and evening).

## 9. Repetition

| Item | Before | After | Status | Note |
|---|---|---|---|---|
| hisn-027-20 | nil | 100 | ACCEPTED, HIGH | book 93 «مائة مرة إذا أصبح» |
| hisn-032-03 | nil | 1 | ACCEPTED, HIGH | part 3 of 114 states no count |
| hisn-032-04 | nil | 1 | ACCEPTED, HIGH | part 4 of 114 states no count |
| hisn-130-02 | nil | (1) | PENDING_DECISION, MEDIUM | not applied; needs explicit acceptance |
| hisn-130-06 | nil | (1) | PENDING_DECISION, MEDIUM | not applied; needs explicit acceptance |
| hisn-016-05, 025-01, 025-02, 025-04, 119-01, 125-01, 131-02 | nil | nil | ACCEPTED (keep nil) | phrase-level or in-hadith counts |
| hisn-029-06 | nil | nil | PENDING_DECISION, LOW | source 3, book silent; not guessed |

Inline wording such as «(ثَلَاثًا)» inside hisn-025-01 is untouched. 10 items keep a nil
count (13 in Phase 2C); a session treats nil as one recitation and the text carries the
instruction.

## 10. Quran

- hisn-001-04: 3:190–200, `EXACT`, `coversWholeVerses: true`. The only differences from
  Tanzil are spelling (Uthmani ٱلَّيْل / اللَّيْل, مَأْوَىٰهُمْ / مَأْوَاهُمْ). The source
  wording is kept; nothing is replaced with Tanzil text.
- hisn-029-03: 2:285–286, `EXACT`, `coversWholeVerses: true`; spelling-only difference
  (مَوْلَىٰنَا / مَوْلَانَا).
- hisn-029-14: 32:1–2 and 67:1, `EXACT`, `coversWholeVerses: false`,
  `recitesWholeSurah: true`. The item quotes the openings and instructs reciting
  al-Sajdah and al-Mulk. Domain extension: one Boolean on `HisnQuranCitation`; validation
  requires such a citation to start at verse 1. No surah text was added.

No Hisn item has `PARTIAL` or `UNRESOLVED` Quran status now. Phase 2C's
`QURAN_FUZZY_MATCH` / `QURAN_SEGMENT_UNRESOLVED` flags stay in `reviewFlags` as history,
and each of these items names its applied manifest entry.

## 11. Unresolved P1 (recorded, nothing fabricated)

| Finding | Items | Entry |
|---|---|---|
| Hadith numbers in the book footnotes, absent from the source | 277 | HISN-CORR-082 (book-wide) |
| Volume/page present in the book, absent from the source | 50 (22 conflicting) | HISN-CORR-060…081 per item, 082 |
| Collection names absent from the source reference | 22 | HISN-CORR-082 |
| Grading statements absent | 13 | HISN-CORR-082 |
| hisn-028-05 → book 78 | 1 | HISN-CORR-010 (PENDING_DECISION) |
| Split groups editorially acceptable | 8 | HISN-CORR-040…047 |

The per-item lists remain in `hisn.reconciliation.json`. The 22 conflicting volume/page
pairs (source vs book) include hisn-001-03 3/144 vs 3/39, hisn-007-01 2/387 vs 1/19,
hisn-073-01 3/126 vs 3/1626; neither side is corrected here.

## 12. Rights

Unchanged. `ContentRightsStatus` has the single case `PENDING_PRE_RELEASE_REVIEW`;
`book.attribution.rightsStatus` is `PENDING_PRE_RELEASE_REVIEW`; `attributionText` is
null. No rights work was done.

## 13. Test results

| Check | Result |
|---|---|
| `python3 tools/content/build_content.py --check` | content up to date |
| Two consecutive builds | byte-identical `hisn.json` |
| `python3 tools/content/test_hisn_corrections.py` | 18 tests OK |
| `swift test` (CI) | 71 tests, 0 failures (run 37749035664) |
| App build + IPA (CI) | success (run 37749035664) |

Swift coverage added in `HisnCanonicalTests` (12 tests): canonical 132/267, presentation
133/302, chapter 27 morning/evening, split groups 106/114/133, relation consistency, the 9
book numbers, swapped-pair order, accepted repetitions, kept-nil repetitions, the 3 Quran
citations, review/rights state, open discrepancies. `HisnTests` changes: book-number order
is checked in book order; the Quran test no longer requires an unresolved passage;
invalid-content fixtures carry the new fields and 11 new rejection cases.

## 14. Generated counts

```
Hisn corrections:
  total 82, accepted 35, observation-only 43, pending 4, P0 accepted 25, P0 pending 15
  canonical 132 chapters / 267 items, presentation 133 sections / 302 items
```

| Type | Accepted | Pending | Observation-only |
|---|---|---|---|
| BOOK_ITEM_NUMBER | 9 | 1 | |
| CANONICAL_ORDER | 3 | | |
| REPETITION_COUNT | 10 | 3 | |
| QURAN_CITATION | 3 | | |
| BOOK_ITEM_RELATION | 8 | | 8 |
| PRESENTATION_SECTION | 2 | | |
| TEXT_DISCREPANCY | | | 9 |
| NON_DHIKR_TEXT | | | 3 |
| REFERENCE_METADATA | | | 23 |

P0 pending (15): 2 medium repetition proposals, hisn-029-06, 9 text discrepancies,
3 non-dhikr texts. Content review: 0 REVIEWED, 302 CONTENT_REVIEW_REQUIRED.

## 15. Final gate

**PASS_WITH_P0_REVIEW_REQUIRED**

All P0 structural corrections (9 book numbers, 3 order pairs, 3 repetition counts,
3 Quran citations) are applied with evidence and no conflict. P0 items that change text or
need a judgement (9 wording discrepancies, 3 non-dhikr texts, 2 medium repetition
proposals, hisn-029-06) are recorded and wait for editorial review. Not
`PASS_P0_CORRECTIONS_APPLIED`, because those P0 items are open; not
`BLOCKED_CORRECTION_CONFLICT`, because the build found no conflicting corrections.

Phase 2F and all UI work are not started.
