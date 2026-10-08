# Phase 2C: Hisn Al-Muslim Content & Domain

Branch: `feature/v1-phase-2c-hisn-content` · Base: `feature/v1-phase-2-content` @ `c5344ce` · Date: 2026-10-08

**Final gate: PASS_WITH_CONTENT_REVIEW_REQUIRED.**
- All 302 items are `CONTENT_REVIEW_REQUIRED`. None has been independently reviewed.
- Rights are a pre-release gate (`PENDING_PRE_RELEASE_REVIEW`), per the owner's decision.

## 1. Scope

Hisn Al-Muslim is now an independent domain in `Packages/IslamicCore`. It contains:
- bundled content
- an actor repository with validation
- a session model
- tests

There is no UI, audio, PiP, persistence, notifications or widgets. The existing Quran, Dhikr and Dua content and code are unchanged. Their generated JSON is byte-identical, and `build_content.py --check` confirms it.

## 2. Source used

During this phase the owner instructed: "استخدم مستودع حصن المسلم من GitHub بدون حقوق" (use the Hisn Al-Muslim repository from GitHub, without rights). The text therefore comes from a GitHub repository with an explicit licence.

| Role | Source | Notes |
|---|---|---|
| **Primary text (bundled)** | https://github.com/asellam/HisnElMuslim, `hisn.json` | MIT licence, © 2021 Abdellah SELLAM. Committed verbatim under `Upstream/hisn/asellam/` with its LICENSE and README. SHA-256 `b30a448e…9d80` is pinned in a test. The README says the text was typed from a printed edition by دار السجلات and then checked against an online copy with Levenshtein distance. |
| **Cross-check (not bundled)** | Shamela transcription, https://shamela.ws/book/31307 (151 pages, Safeer / Al-Juraisy print) | Parsed by `tools/content/hisn/extract_hisn.py` into 132 chapters and 267 numbered items with footnotes. It is used only to check numbering, Quran passages and repetition. It is never shown as text. |
| **Official numbering check** | https://binwahaf.com/ar/audio-book-series/897/ (author's site) | Item numbers 1–267 and incipits. The last item (267, «إذا كان جنح الليل») agrees with the cross-check. |
| **Canonical edition (pinned, not yet compared)** | Author's PDF from https://binwahaf.com/ar/book/854/ | 161 pages, created 2010 from «حصـن المسـلم إملائي ملون», modified 2025-12-02. SHA-256 `50d53982…cbb9`. Its text layer uses custom font encodings and extracts as garbage, so comparing against it needs OCR or manual work. This is recorded as `NOT_YET_COMPARED`. |

The raw pages and the PDF were fetched by a temporary GitHub runner, because the build container cannot reach these hosts. They are not committed.

The MIT licence covers the repository's transcription only. It is not permission from the book's rights holder. That question stays in the pre-release gate.

## 3. Edition used

- **Bundled text:** asellam's transcription of the دار السجلات print. The edition number is not stated.
- **Cross-check:** the Shamela transcription of the Safeer / Al-Juraisy print, which has 132 chapters and 267 items.

The two differ in structure:
- The primary source splits أذكار الصباح and أذكار المساء into two chapters, giving 133 chapters.
- It splits some book items into several entries, for example the 33/33/34 tasbih, giving 302 items.

Each item keeps its own chapter position and also records the book's chapter and item number where they could be matched.

## 4. Content counts

All counts are from the generated `hisn.json` and are not hand-typed.

| Count | Value |
|---|---|
| Chapters | **133** (they cover all **132** book chapters; the book's chapter 27 is split into morning and evening) |
| Items | **302** |
| Items matched to a book item number | 292. They cover 260 of the book's 267 numbers. |
| Items not matched to a book number | 10, flagged `ITEM_NOT_MATCHED_IN_BOOK` |
| Book numbers with no matched item | 2, 7, 16, 93, 110, 142, 267. These are wording or ordering differences between the two prints, which a reviewer must confirm. For example, 267 is the bundled `hisn-133-01`, a variant wording at 0.82 similarity. |
| Items with references | 302 (each has the source's takhrij text) |
| Items with Quran citations | 17, with 25 citations: 23 exact and 2 fuzzy |
| Unresolved Quran passages | 1 item (`hisn-029-14`, «ألم * تنزيل ...», which names surahs rather than quoting them), marked `PARTIAL` |
| Items with a structured `repeatCount` | 289 |
| Items with `repeatCount = nil` | 13: the source count and the book text disagree |
| `CONTENT_REVIEW_REQUIRED` | **302** |
| `REVIEWED` | **0** |
| Items with at least one review flag | 91 |

Review flags by type:

| Flag | Items |
|---|---|
| `SHORT_TEXT_MATCH` | 41 |
| `BOOK_TEXT_NOT_COVERED` | 41 |
| `REPEAT_CONFLICT` | 13 |
| `ITEM_NOT_MATCHED_IN_BOOK` | 10 |
| `REPEAT_UNVERIFIED` | 10 |
| `QURAN_FUZZY_MATCH` | 2 |
| `QURAN_UNBRACED_IN_SOURCE` | 1 |
| `QURAN_SEGMENT_UNRESOLVED` | 1 |

## 5. Domain model

`Sources/IslamicCore/Domain/Hisn.swift`:

- **`HisnBook`:** id, title, author, `HisnProvenance`, `HisnAttribution`, and chapters in canonical order. It is immutable and holds no user state.
- **`HisnChapter`:** id, number, Arabic title, `searchText`, `bookChapterNumber?`, items, `itemCount`.
- **`HisnItem`:** id, chapterId, order, `bookItemNumber?`, `arabicText` (the source verbatim), `searchText`, `HisnRepetition`, `[HisnReference]`, `[HisnQuranCitation]`, `HisnQuranStatus`, `reviewFlags`, `reviewStatus`.
- **`HisnRepetition`:** `count?`, `sourceCount`, `bookStatedCounts`, `reviewStatus`.
- **`HisnReference`:** `originalText` (complete and verbatim) and `collections` (the hadith collections it names, as a search index).
- **`HisnQuranCitation`:** a `QuranReference` pointing into Tanzil, `coversWholeVerses`, and `match` (`EXACT` / `FUZZY`).
- **`ContentRightsStatus`:** only `PENDING_PRE_RELEASE_REVIEW`. Any other value, such as `PUBLIC_DOMAIN`, fails decoding and is covered by a test.

`DhikrItem` and the Dhikr domain are untouched. The shared pieces reused are `ContentReviewStatus`, `QuranReference` and `SessionCursor`.

`HisnSession` (`Session/HisnSession.swift`):
- Its scope is a chapter or the whole book.
- It exposes the current item, current chapter id and title, `next`, `previous`, `restart`, `progress`, and `cursor.advance()` for repetitions.
- `HisnItem.repeatCount` is `repetition.count ?? 1`, so an unknown count never invents repetitions.

## 6. Repository

`Repositories/BundledHisnRepository.swift`:
- It defines a `HisnRepository` protocol (`loadBook`, `loadChapters`, `loadChapter(id:)`, `loadItem(id:)`).
- `BundledHisnRepository` is an actor over `BundledContentSource`, the same mechanism as Phase 2. It decodes lazily, caches, and rejects invalid content with `ContentError.invalidContent`.

Validation covers:
- empty book
- duplicate or out-of-order chapters and items
- empty chapters
- an item in the wrong chapter
- empty or non-Arabic or U+FFFD text
- empty search text
- non-positive repeat counts or book numbers
- empty references
- bad Quran ranges
- Quran status that contradicts the citations
- any Hisn item claiming `QURAN_VERBATIM_TANZIL`

## 7. JSON / content pipeline

```
Upstream/hisn/asellam/hisn.json  ──┐
tools/content/hisn.crosscheck.json ─┼─ build_content.py ──> Resources/Content/hisn.json
Upstream/tanzil/quran-uthmani.xml ──┘   (--check runs in CI)
```

- **`tools/content/hisn/extract_hisn.py`** parses the Shamela pages. It is used for cross-checking only.
- **`tools/content/hisn/prepare_crosscheck.py`** matches every primary item to the book, keeping book order and never matching backwards. It also locates Quran passages and compares repetition, then writes `hisn.crosscheck.json`. It needs the raw pages, which the runner fetches.
- **`build_content.py`** builds `hisn.json` from the verbatim upstream file plus the committed cross-check. It asserts that the cross-check is not stale and that every Quran range exists in Tanzil. `--check` runs in CI.

Replacing the content before release is a matter of swapping the upstream file (or adding the canonical edition), re-running both scripts, and updating the pinned hash.

## 8. Review-status strategy

- Every item and every repetition is `CONTENT_REVIEW_REQUIRED`. A test fails if any item is `REVIEWED` without that being true.
- `reviewFlags` lists each machine finding, so a reviewer can start with the 91 flagged items.

## 9. Quran reference strategy

- A passage the source marks with `{…}`, or one the book marks and the item visibly carries, is located in Tanzil on a letters-only skeleton. Marks are dropped and alef and hamza seats are ignored. This bridges Uthmani and ordinary spelling.
  - A match counts only when it is **exact and unique**.
  - Otherwise, a verse range from the book's footnote is accepted only if the letters agree to at least 85%. Such matches are flagged `QURAN_FUZZY_MATCH`; there are 2: Al Imran 190–200 and Al-Baqarah 285–286.
- The displayed text stays the source's text. Citations point to the canonical Tanzil verses; Quran text is not duplicated.
- `coversWholeVerses` is false when only part of a verse is quoted, for example Al-Muminun 14 («فتبارك الله أحسن الخالقين»).
- Unlocatable passages are not guessed. The item is marked `PARTIAL` or `UNRESOLVED` and flagged.
- One source defect was found this way: in the evening chapter, An-Nas is in round brackets instead of braces. It is cited and flagged `QURAN_UNBRACED_IN_SOURCE`.

## 10. Repetition strategy

- The wording in `arabicText` is never changed, so «(ثَلَاثًا)» stays as written.
- `sourceCount` is the primary source's own count, always kept.
- `bookStatedCounts` holds counts the cross-check book text states in words, such as ثلاثاً / ثلاث مرات / مائة مرة.
- `count` equals `sourceCount` unless the book text contradicts it. In that case it is `nil` and the item is flagged `REPEAT_CONFLICT`. This happened for 13 items, for example `hisn-025-01`, where «أستغفر الله (ثلاثاً)» is one item with source count 1.

## 11. Provenance / rights metadata

`book.provenance` records:
- the primary source: name, URL, licence statement, edition, upstream file, SHA-256 and retrieval date
- the cross-check sources and their counts
- the canonical edition: URL, PDF SHA-256, and `NOT_YET_COMPARED`

`book.attribution` holds `sourceTitle`, `author`, `edition` (null), `sourceURL`, `attributionText` (null, not final) and `rightsStatus` = `PENDING_PRE_RELEASE_REVIEW`.

`ATTRIBUTION.md` gained a Hisn section stating the MIT source and that rights are pending. Nothing claims the content is licensed by the rights holder or in the public domain.

## 12. Tests

`Tests/IslamicCoreTests/HisnTests.swift` contains 19 new tests.

Book:
- metadata and provenance
- upstream SHA-256
- bundled text equals upstream character for character, with counts and references, in upstream chapter order

Chapters:
- unique ids, sequential numbers, titles present
- all 132 book chapters present and in book order

Items:
- unique ids, sequential order, correct chapter, Arabic integrity
- search text without diacritics
- book numbers never go backwards
- loading by id, and not-found errors

References:
- verbatim reference text
- collections index consistent with the text

Quran:
- every citation resolves through `BundledQuranRepository`
- Ayat al-Kursi and the three Quls are cited correctly
- unresolved and fuzzy matches are flagged

Repetition:
- counts are positive or nil
- nil only with a conflict flag
- `repeatCount` falls back to 1
- `hisn-025-01` stays nil and keeps «(ثَلَاثًا)» in its text
- the sleep tasbih counts are 33/33/34

Review: every item is `CONTENT_REVIEW_REQUIRED`.

Session:
- chapter navigation, bounds, progress and restart
- a book session crossing chapters
- the three Quls counted three times

Invalid content (`HisnInvalidContentTests`):
- a minimal valid book loads
- 12 broken variants are each rejected as `invalidContent`
- `PUBLIC_DOMAIN` is rejected as a rights status

CI: see section 15.

## 13. Known uncertainties

1. **The bundled wording is one transcription of one print** (دار السجلات). It has not been compared with the author's official edition. The official PDF's text layer is unusable, so the comparison needs OCR or manual work.
2. **The two prints differ in structure:** split chapters and items, and 7 book numbers with no matched item. The 41 `BOOK_TEXT_NOT_COVERED` flags mostly mark parenthetical wording, such as repetition notes, that the book has and the primary source dropped. Each still needs a reviewer.
3. **41 short items** (for example «الحمد لله») were matched by order and similarity. They are flagged `SHORT_TEXT_MATCH`.
4. **Quran text inside items** is in ordinary spelling, not Tanzil Uthmani. The UI phase must decide whether to display the Tanzil text for citations.
5. **References** are the source's short takhrij, without hadith numbers or gradings. The book's fuller footnotes are not bundled.
6. **The book's front matter** (المقدمة، فضل الذكر) is not in the primary source and is not bundled.
7. **The primary source's `Audio` URLs** (islamway.net) were ignored. Audio is out of scope and its rights are separate.
8. **Rights:** pending the pre-release gate.

## 14. Files changed

Added:
```
Packages/IslamicCore/Sources/IslamicCore/Domain/Hisn.swift
Packages/IslamicCore/Sources/IslamicCore/Repositories/BundledHisnRepository.swift
Packages/IslamicCore/Sources/IslamicCore/Session/HisnSession.swift
Packages/IslamicCore/Sources/IslamicCore/Resources/Content/hisn.json
Packages/IslamicCore/Tests/IslamicCoreTests/HisnTests.swift
Packages/IslamicCore/Upstream/hisn/asellam/{hisn.json,LICENSE.md,README.md}   (verbatim, not bundled)
tools/content/hisn/extract_hisn.py
tools/content/hisn/prepare_crosscheck.py
tools/content/hisn.crosscheck.json
docs/phases/PHASE_2C_HISN_IMPLEMENTATION.md
```

Modified:
```
tools/content/build_content.py                                   (adds build_hisn; other outputs unchanged)
Packages/IslamicCore/Sources/IslamicCore/Resources/Content/ATTRIBUTION.md   (Hisn section appended)
```

Not touched: `Package.swift`, the Xcode project, PiP and renderer files, Quran, Dhikr and Dua content, CI workflows.

## 15. Commit

`feat(content): add Hisn Al-Muslim domain and bundled content`. The hash and CI run are listed in the PR.

## 16. Final gate

**PASS_WITH_CONTENT_REVIEW_REQUIRED**
