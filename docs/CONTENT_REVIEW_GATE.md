# Content review gate

**No content was marked reviewed in this release.** Scholarly review is an external gate.
Nothing here changes a text or a status.

## Status vocabulary

| Status | Meaning | Where |
|---|---|---|
| `QURAN_VERBATIM_TANZIL` | Verbatim Tanzil verse text; reviewed by Tanzil, not editable | Quran, Quranic adhkar and duas |
| `CONTENT_REVIEW_REQUIRED` | Transcribed text; needs a qualified reviewer to check wording, diacritics, source and repeat count | every Hisn item, non-Quranic adhkar and duas |
| `REVIEWED` | Set only after a named qualified reviewer approves an item | no item carries it |
| DEFERRED (`DEFER`) | An editorial decision on a finding that is postponed to the external reviewer; the item stays `CONTENT_REVIEW_REQUIRED` | `tools/content/hisn.editorial_review.json` |

`ContentReviewStatus` in code has the first three cases. DEFER is a decision on a finding,
not an item status, so no schema change was made.

## Status by section

| Section | Items | Status | Gate |
|---|---|---|---|
| Quran | 114 surahs / 6236 verses | `QURAN_VERBATIM_TANZIL`; hash-pinned and compared verse by verse | READY |
| Hisn Al-Muslim | 302 display items (133 sections; 132 / 267 canonical) | all 302 `CONTENT_REVIEW_REQUIRED` | BLOCKED (external review) |
| Adhkar | 51 | 18 `QURAN_VERBATIM_TANZIL`, 33 `CONTENT_REVIEW_REQUIRED` | BLOCKED for the 33 |
| Duas | 17 | 10 `QURAN_VERBATIM_TANZIL`, 7 `CONTENT_REVIEW_REQUIRED` | BLOCKED for the 7 |

## Hisn: the 12 open P0 findings

These are P0 entries in `tools/content/hisn.corrections.json` with status
`OBSERVED_DIFFERENCE`. The difference is recorded but never applied; the text is as in the
source.

| Correction | Item | Type | Editorial decision |
|---|---|---|---|
| HISN-CORR-048 | hisn-016-01 | TEXT_DISCREPANCY | DEFER (HISN-REVIEW-001) |
| HISN-CORR-049 | hisn-016-06 | TEXT_DISCREPANCY | DEFER (HISN-REVIEW-002) |
| HISN-CORR-050 | hisn-017-04 | TEXT_DISCREPANCY | DEFER (HISN-REVIEW-003) |
| HISN-CORR-051 | hisn-025-02 | TEXT_DISCREPANCY | KEEP_SOURCE (HISN-REVIEW-004) |
| HISN-CORR-052 | hisn-029-15 | TEXT_DISCREPANCY | DEFER (HISN-REVIEW-005) |
| HISN-CORR-053 | hisn-037-02 | TEXT_DISCREPANCY | DEFER (HISN-REVIEW-006) |
| HISN-CORR-054 | hisn-043-01 | TEXT_DISCREPANCY | KEEP_SOURCE (HISN-REVIEW-007) |
| HISN-CORR-055 | hisn-052-02 | TEXT_DISCREPANCY | DEFER (HISN-REVIEW-008) |
| HISN-CORR-056 | hisn-112-01 | TEXT_DISCREPANCY | DEFER (HISN-REVIEW-009) |
| HISN-CORR-057 | hisn-001-03 | NON_DHIKR_TEXT | KEEP_METADATA (HISN-REVIEW-010) |
| HISN-CORR-058 | hisn-133-01 | NON_DHIKR_TEXT | KEEP_METADATA (HISN-REVIEW-011) |
| HISN-CORR-059 | hisn-029-14 | NON_DHIKR_TEXT | KEEP_METADATA (HISN-REVIEW-012) |

The other three decisions (KEEP_NIL: HISN-REVIEW-013, 014 and 015, on hisn-130-02, hisn-130-06
and hisn-029-06) settle repetition-count findings that are not among the 12. None of the 15
decisions has had an independent review.

## Hisn: the 7 deferred decisions

| Decision | Item |
|---|---|
| HISN-REVIEW-001 | hisn-016-01 |
| HISN-REVIEW-002 | hisn-016-06 |
| HISN-REVIEW-003 | hisn-017-04 |
| HISN-REVIEW-005 | hisn-029-15 |
| HISN-REVIEW-006 | hisn-037-02 |
| HISN-REVIEW-008 | hisn-052-02 |
| HISN-REVIEW-009 | hisn-112-01 |

The one other open entry is HISN-CORR-010 (hisn-028-05, P1, BOOK_ITEM_NUMBER),
`PENDING_DECISION`.

## What the external reviewer must do

1. Decide each of the 7 DEFER items, against the author's edition.
2. Confirm or overturn the 8 other decisions (5 on the rows above, plus the 3 KEEP_NIL); each needs an independent reviewer recorded.
3. Decide HISN-CORR-010.
4. Compare the 302 Hisn items with the canonical edition (currently `NOT_YET_COMPARED`).
   Item flags to start from:
   - SHORT_TEXT_MATCH: 41;
   - ITEM_NOT_MATCHED_IN_BOOK: 10;
   - REPEAT_UNVERIFIED: 10;
   - REPEAT_CONFLICT: 6;
   - several partial-coverage flags.
5. Review the 33 non-Quranic adhkar and 7 non-Quranic duas: wording, diacritics, source and
   repeat count.

Approved changes go through the existing pipeline: `hisn.corrections.json` /
`hisn.editorial_review.json`, then `build_content.py`, then `--check` in CI. Only then may an
item be set to `REVIEWED`, with the reviewer named.

## Gate

**SCIENTIFIC REVIEW: BLOCKED** (EXTERNAL_BLOCKER: qualified scholarly reviewer required).
