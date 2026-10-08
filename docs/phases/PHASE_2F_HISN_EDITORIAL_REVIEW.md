# Phase 2F: Hisn Al-Muslim editorial review gate

Final gate: **PASS_WITH_EDITORIAL_REVIEW_REQUIRED** (section 12).

All 15 P0 findings that Phase 2E left open now have an explicit, evidenced decision. Eight
are settled (2 KEEP_SOURCE, 3 KEEP_METADATA, 3 KEEP_NIL). Seven are **DEFER**: the evidence
does not establish the canonical wording, so the source text is kept unchanged and the
question stays open. A deferred finding is not counted as resolved. No Arabic text was
changed. No independent human reviewer has signed off, so every item remains
`CONTENT_REVIEW_REQUIRED`.

- Branch: `feature/v1-phase-2f-hisn-editorial-review`
- Base: `feature/v1-phase-2e-hisn-content-corrections` at `769bde3` (the 2E branch itself is
  not modified).
- Decision file: `tools/content/hisn.editorial_review.json` (sha256
  `b68e64fc2035918e449ca20b16a39a591b14839ea645d466438ca3068c7bf8e6`).

## 1. Scope

Only the 15 P0 findings below. Nothing in this phase adds UI, audio, PiP, notifications,
widgets, search, sharing or product features. P1 findings, front matter and rights are out
of scope.

## 2. Evidence policy

| Tier | Source | Used as |
|---|---|---|
| 1 | Shamela transcription of the Safeer / Al-Juraisy print, book 31307 (retrieved 2026-10-08, Phase 2B), page cited per decision | the canonical book cross-check |
| 2 | Author's official PDF, binwahaf.com/ar/book/854 (sha256 `50d53982…cbb9`) | **not usable in this phase** (see below) |
| 3 | Vendored upstream `asellam/HisnElMuslim` `hisn.json` (sha256 `b30a448e…9d80`) | the bundled text |

No new source was introduced. No search snippet, generated text or recollection is used as
evidence. Every Arabic quotation inside a finding was copied programmatically from the
witness it quotes (the source text, the book text, its footnotes, or the Shamela page),
not retyped; `test_hisn_editorial_review.py` checks the source quotations.

**Tier 2 was not available.** The PDF's text layer uses a custom font encoding and cannot
be read as text (established in Phase 2B), and on 2026-10-08 this session's network policy
refused `cdn.binwahaf.com` (HTTP 403), so its pages could not be rendered and checked. For a
wording difference this leaves one witness (the cross-check print) against another (the
source, which follows a different printing, دار السجلات). That is why the wording cases
are deferred rather than decided.

Decision vocabulary: `ACCEPT_CORRECTION`, `KEEP_SOURCE`, `KEEP_NIL`, `KEEP_METADATA`,
`DEFER`. A text change could only be applied through the Phase 2E
`ACCEPTED_TEXT_CORRECTION` mechanism (exact before/after, `acceptedBy`). None was.

## 3–5. The 15 P0 cases, decisions and evidence

| # | Item | Issue | Decision | Confidence | Applied? | Independent review? |
|---|---|---|---|---|---|---|
| 001 | hisn-016-01 | Text: بالماء والثلج / بالثلج والماء | DEFER | INSUFFICIENT | No | No |
| 002 | hisn-016-06 | Text: two bracketed phrases absent | DEFER | INSUFFICIENT | No | No |
| 003 | hisn-017-04 | Text: استقلّ / [استقلّت] | DEFER | INSUFFICIENT | No | No |
| 004 | hisn-025-02 | Text: [ثلاثاً] absent | KEEP_SOURCE | HIGH | No change needed | No |
| 005 | hisn-029-15 | Text: رهبة ورغبة / رغبة ورهبة | DEFER | INSUFFICIENT | No | No |
| 006 | hisn-037-02 | Text: أجول / أحول | DEFER | INSUFFICIENT | No | No |
| 007 | hisn-043-01 | Text: ويتفل على يساره / واتفل على يسارك -ثلاثاً- | KEEP_SOURCE | HIGH | No change needed | No |
| 008 | hisn-052-02 | Text: لسكرات / سكرات | DEFER | INSUFFICIENT | No | No |
| 009 | hisn-112-01 | Text: منهم / منهنّ | DEFER | INSUFFICIENT | No | No |
| 010 | hisn-001-03 | Non-dhikr: virtue text | KEEP_METADATA | HIGH | Metadata only | No |
| 011 | hisn-133-01 | Non-dhikr: closing doxology | KEEP_METADATA | HIGH | Metadata only | No |
| 012 | hisn-029-14 | Non-dhikr: surah labels | KEEP_METADATA | HIGH | Metadata only | No |
| 013 | hisn-130-02 | Repetition: 1 vs «مائة مرة» | KEEP_NIL | HIGH | No (count stays nil) | No |
| 014 | hisn-130-06 | Repetition: 1 vs «مائة مرة» | KEEP_NIL | HIGH | No (count stays nil) | No |
| 015 | hisn-029-06 | Repetition: source 3, book silent | KEEP_NIL | MEDIUM | No (count stays nil) | No |

Full question, both texts, evidence records and rationale for each are in
`hisn.editorial_review.json`. Summary of the evidence:

**Text discrepancies.**
- *016-01, 029-15* (word order), *037-02* (ج / ح), *052-02* (لـ), *112-01* (هم / هنّ):
  the cross-check print and the source cite the same narrations and differ only in
  wording. Nothing in the project's evidence says which wording the author intends;
  grammar or plausibility is not evidence. **DEFER**, source unchanged.
- *016-06*: the two missing phrases are bracketed in the book, like eight other segments of
  the item that the source does contain, and this footnote (unlike items 36 and 67) does
  not say what the brackets mark. There is no explicit evidence they belong to the recited
  text. Nothing is inserted. **DEFER**.
- *017-04*: the footnote states «وما بين المعقوفين لفظ ابن خزيمة… وابن حبان», so the book's
  bracketed phrase is a specific narration's wording. Whether the source's «استقلّ» is
  another narration or a slip is not established. **DEFER**.
- *025-02*: the footnote states «وما بين المعقوفين زيادة من البخاري، برقم ٦٤٧٣»: «ثلاثاً» is
  a repetition instruction from an additional narration, covering only the tahlil. It is
  neither recited wording nor a whole-item count. **KEEP_SOURCE**: nothing inserted, count
  stays nil, the instruction stays recorded (HISN-CORR-051).
- *043-01*, judged separately: (1) the recited words «أعوذ بالله من الشيطان الرجيم» are the
  same; (2) the direction is the left in both; (3) the book's «-ثلاثاً-» matches the
  applied count 3. Only the phrasing of the accompanying action differs (imperative in the
  book, third person after «يقول:» in the source), and that is not recited. **KEEP_SOURCE**.

**Non-dhikr text.** All three are kept verbatim and marked, never deleted:
- *001-03*: the book prints item 2 ending at «رب اغفر لي» and the virtue «فإن دعا استجيب
  له…» in its footnote. The source has the virtue after its own closing parenthesis; that
  exact span is marked `NARRATION`.
- *133-01*: on the last page the book closes hadith 267 with «)) (١).» and prints the
  doxology on its own line afterwards: the book's closing. Marked `CLOSING`.
- *029-14*: the labels «(سُورَةُ السَّجْدَة)» and «(سُورَةُ المُلْكِ)» are not in the book
  and are not Quran text; the citations (32:1–2, 67:1, `recitesWholeSurah`) already carry
  what they name. Marked `LABEL`. No surah text added.

**Repetition.**
- *130-02, 130-06*: the book introduces both with «وقال ﷺ:» and «مِائَةَ مَرَّةٍ» sits inside
  his quoted words, describing his own practice. It is not a repeat count, and the book
  states no whole-item count, so 1 would be inferred. **KEEP_NIL**; the 2E proposals
  (HISN-CORR-017/018) are now `REJECTED` with `rejectedBy` naming these decisions.
- *029-06*: the book's footnotes for item 104 (Shamela page 72) quote only the hadith's
  opening and cite Abu Dawud 5045 and al-Tirmidhi 3398; no count. The source's 3 is not
  supported or contradicted by the evidence. **KEEP_NIL**, not inferred; HISN-CORR-026
  (keep nil) is now `ACCEPTED`.

## 6. Changes actually applied

| Change | Count |
|---|---|
| Arabic text changes | **0** |
| `ACCEPTED_TEXT_CORRECTION` entries | 0 |
| Repetition counts changed | 0 (three stay nil) |
| Upstream changes | 0 (sha256 `b30a448e…9d80` unchanged) |

Data added, text untouched:
- Item `nonRecitationText`: exact spans of `arabicText` with a role (`NARRATION`,
  `CLOSING`, `LABEL`; `INSTRUCTION` is defined but unused). The build requires each span to
  occur exactly once, verbatim. Set on 3 items only. A later recitation flow can leave
  these spans out without any heuristic.
- Item `editorialReviews`: the decision id, issue type, decision and `changesApplied`.
- `book.provenance.editorialReview`: file hash, counts per decision, `changesApplied 0`,
  `independentlyReviewed 0`, `editorialReviewComplete false`.
- Correction manifest: new status `REJECTED` (needs `rejectedBy`); HISN-CORR-017/018
  rejected, HISN-CORR-026 accepted (keep nil, owner's Phase 2F instruction).

The build stops when: a P0 finding the manifest did not settle has no decision; a decision
or its evidence (`source`, `reference`, `finding`) is missing; `independentReviewer` is
anything but null or a named, dated, referenced sign-off; `reviewStatus` claims independent
review without one; `editorialReviewComplete` is set without a reviewer on every decision; a
DEFER/KEEP decision reports a change or sits on an applied text correction; an applied
ACCEPT_CORRECTION lacks an `ACCEPTED_TEXT_CORRECTION` with exact before/after; a KEEP_NIL item
has a count; a metadata span is not verbatim; `sourceText`/`bookText` differ from the item
and the cross-check.

## 7. Decisions deliberately deferred

hisn-016-01, hisn-016-06, hisn-017-04, hisn-029-15, hisn-037-02, hisn-052-02, hisn-112-01.

What would settle them: the corresponding pages of the author's official edition (tier 2),
read by a person or rendered for comparison, or an independent reviewer's decision. Each
would then be recorded as ACCEPT_CORRECTION (with an `ACCEPTED_TEXT_CORRECTION` entry
carrying the exact replacement and `acceptedBy`) or KEEP_SOURCE.

## 8. Independent-review status

None. `independentReviewer` is null on all 15 decisions, `editorialReviewComplete` is
false, and no item is `REVIEWED`. The decisions are the project's editorial decisions from
recorded evidence, not scholarly certification.

## 9. Remaining P1 (untouched)

| Finding | Items |
|---|---|
| Hadith numbers missing from source references | 277 |
| Volume/page conflicts | 22 (of 50 with volume/page in the book) |
| Collection names missing | 22 |
| Grading statements missing | 13 |
| hisn-028-05 → book 78 | 1 (PENDING_DECISION) |
| Split groups editorial check | 8 |
| Front matter | not imported |

P1 manifest entries keep their 2E statuses; references remain the upstream text verbatim
(both checked by `test_hisn_editorial_review.py`).

## 10. Tests

| Check | Result |
|---|---|
| `python3 tools/content/test_hisn_editorial_review.py` | 24 tests OK |
| `python3 tools/content/test_hisn_corrections.py` | 20 tests OK |
| `python3 tools/content/build_content.py --check` | content up to date |
| `swift test` (CI) | 75 tests, 0 failures (run 37751031669) |
| App build (CI) | success (run 37751031669) |

Regression guarantees re-checked: 132 canonical chapters, 267 canonical book items, 133
presentation sections, 302 display items, 0 missing book numbers, 0 conflicting
corrections, upstream sha256 unchanged, every bundled text equal to upstream.

## 11. Rights

Unchanged: `PENDING_PRE_RELEASE_REVIEW`, no attribution text, no public-domain claim.

## 12. Final gate

**PASS_WITH_EDITORIAL_REVIEW_REQUIRED**

Every one of the 15 P0 findings has an explicit, evidenced, defensible decision, so the
gate is not BLOCKED_P0_UNRESOLVED. It is not PASS_P0_EDITORIAL_DECISIONS_COMPLETE because
seven findings are deferred and no independent editorial review exists.

Phase 2G and all UI work are not started.
