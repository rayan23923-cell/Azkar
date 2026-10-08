# Phase 3F: Hisn search, filtering and navigation

## Objective

Make search in Hisn Al-Muslim usable every day:

- search chapter titles and item texts, fully offline;
- rank the results in a clear order;
- filter them;
- open a result at its chapter or item;
- read all of it in Arabic with VoiceOver.

Out of scope: content, rights, audio, PiP, persistence schema, share, notifications, widgets,
volume counting, Quran features, and any network or cloud search.

- **Base:** `e72329f`, the head of `feature/v1-phase-3e-hisn-actions` (PR #13, not merged).
- **Branch:** `feature/v1-phase-3f-hisn-search`.

## Audit (before changes)

Phase 3A already had offline search: `HisnSearchKey` (the query normalizer), and
`HisnSearchIndex`, which held keys, ranked results and ran the search together. The ranking
had only two levels (exact phrase, then all words). It used the system `.searchable` field
and an overlay for "no results". There was no filter, the result model had no item id, and
there was no highlight. A search result opened its item with zero repetitions, overwriting
any saved count for that item.

The rules of `HisnSearchKey` are those of the content builder's `search_text`. They were kept
unchanged, so typed queries still compare with the bundled `searchText` fields. The phase
splits the existing code into separate layers instead of adding a second search.

## Architecture

All the search logic is in the `HisnReading` package. The UI only shows results and opens them.

| Layer | Type | Job |
|---|---|---|
| Normalization | `HisnSearchNormalizer` | text → key, plus a map from each key character back to the original text |
| Indexing | `HisnSearchIndex` (final class, immutable) | one entry per section title (133) and per display item (302), in book order, built once when the book loads |
| Ranking | `HisnSearchEngine` | normalizes the query, ranks entries, applies the filter, builds the preview and highlight |
| Result | `HisnSearchResult`, `HisnSearchFilter` | what the UI shows and opens |
| Navigation | `HisnSearchDestination.resolve` | result → chapter, item, repetitions and highlight, or nil if the result is stale |
| UI | `HisnSearchField`, `HisnSearchResultsSection`, `HisnIndexView` | field, filter, count, rows |

`HisnLibraryModel` builds the index once in `load()` and keeps the engine. The index view
searches only when the query or the filter changes. The results are kept in view state, so
other redraws do not search again.

## Normalization rules

Normalization is used only for keys; the stored text is never changed.

- Arabic marks (tashkeel, Quranic annotation signs, superscript alef) are removed.
- Tatweel «ـ» is removed.
- أ إ آ ٱ become ا.
- ى becomes ي.
- ة becomes ه. «صلاة» and «صلاه» find each other, because users type both. This is also the
  content builder's rule, so query keys stay equal to the bundled keys (tested over every
  title and item).
- Anything that is not an Arabic letter separates words: spaces, line breaks, punctuation,
  brackets, digits and Latin letters. Runs of separators become one space, with none at
  either end.
- Matching is by substring, so part of a word matches («احيان» finds «أحيانا»).

There is no stemming and no fuzzy matching.

## Ranking rules

Lower ranks come first:

| Rank | Case |
|---|---|
| 1 `chapterExact` | the chapter title is the query |
| 2 `chapterPrefix` | the chapter title starts with the query |
| 3 `textExact` | the item text is the query |
| 4 `textPrefix` | the item text starts with the query |
| 5 `chapterPartial` | every query word appears in the title |
| 6 `textPartial` | every query word appears in the text |

Results with the same rank keep book order, using the entry's position: sections in index
order, items in chapter order. Nothing is random, and the same query always gives the same
list (tested).

## Result types

`HisnSearchResult` has these fields:

- `kind`: `.chapter` or `.item`;
- `rank`;
- `order`;
- `chapterId`, `chapterTitle`, `chapterItemCount`;
- `itemId?`, `itemIndex?`;
- `matchedText`;
- `highlight` (a character range in `matchedText`).

`matchedText` is the chapter title, or the item's stored text. When the text is longer than
160 characters it is a run of it around the match, cut between words, with «… » or « …» at
a cut end. Characters are copied, never changed.

The highlight covers the whole words that contain the match. It is found in the key and
mapped back through the normalizer's offset map. It never splits a word into differently
styled parts, so Arabic letters stay joined and RTL is not affected. The row shows the
highlighted words bold in the accent colour.

Filters:

- «الكل»
- «الفصول»
- «النصوص»

The content has no reliable split between dhikr and dua, so none was invented.

## Navigation behaviour

The search field sits at the top of the Hisn index (`HisnRootView`), above «متابعة القراءة»
and the chapter list. When the query has an Arabic letter, the index is replaced by:

- the filter;
- the count («نتيجة واحدة», «نتيجتان», «7 نتائج», «23 نتيجة»);
- the results.

Clearing the query brings the index back.

- **Chapter result:** opens the chapter as the index does: at the saved place if the reading
  cursor is in that chapter, otherwise at item 1.
- **Item result:** opens the chapter at that item. The item's text gets a soft accent
  background that fades after about 1.5 s, with no animation when Reduce Motion is on.
- **Repetitions:** opening a result counts nothing and completes nothing. The item opens with
  zero repetitions, unless it is exactly the saved item, in which case its saved count is
  kept. This is a fix on 3A, which reset it.
- **Persistence:** the reader saves the cursor on open, as it already did (unchanged Phase 3D
  rule).
- **Stale result:** a result whose chapter or item no longer exists resolves to nothing, and
  its row is not shown. Nothing crashes.
- **Query state:** the query and filter last while the Hisn index is alive, including going
  into a result and back. They are not saved between launches; no new persistence was added.

## Accessibility

- **Field:** «بحث في حصن المسلم», with its own clear button «مسح البحث». The custom field
  replaces the system search bar, whose clear and cancel buttons follow the app's English
  base localization.
- **Filter:** «نوع النتائج», with «الكل», «الفصول» and «النصوص».
- **Chapter row:**
  - label «فصل، ‹title›»;
  - value «عدد الأذكار n»;
  - hint «يفتح الفصل».
- **Item row:**
  - label «ذكر، الذكر n من m، ‹chapter›»;
  - value: the preview text;
  - hint «يفتح الذكر في موضعه».
- **Count:** spoken as section header text with Arabic number agreement.
- **Visuals:** rows use system text styles (Dynamic Type) and system colours (dark mode),
  right to left. No meaning relies on an icon or symbol alone.

The strings live in `HisnAccessibility` and are tested to contain no Latin letters.

## Tests

CI run 37771642528 (commit `8323967`): **229 Swift tests, 0 failures**, up from 209.
`HisnSearchTests` has grown from 8 to 28 tests:

- **Normalization:**
  - tashkeel;
  - alef forms;
  - ى / ة;
  - tatweel;
  - whitespace;
  - punctuation and brackets mixed with Arabic;
  - non-Arabic input;
  - offset map back to the source;
  - agreement with every bundled key.
- **Search:**
  - empty and whitespace queries;
  - no results;
  - exact chapter;
  - chapter prefix;
  - partial chapter in book order;
  - exact item before prefix;
  - partial item (part of a word);
  - multiple results ranked, then in book order, no duplicates;
  - deterministic results, including after rebuilding the index;
  - filters.
- **Results:**
  - every result points at a real chapter and item, and shows the stored text or a run of it;
  - the highlight covers whole matching words;
  - a long item shows an excerpt around a deep match.
- **Navigation:**
  - chapter result (with and without a cursor);
  - item result opens the right item, uncompleted, with zero repetitions;
  - repetitions are kept only for the saved item;
  - invalid results resolve to nothing.
- **Accessibility:** labels, values, hints, count agreement, filter names, Arabic only.
- **Content integrity:** 132 / 267 / 133 / 302; the index holds the stored text unchanged;
  reloading gives the same text.
- **Performance:** ten growing queries over all 435 entries reuse the one index (same
  instance), and results narrow as letters are added. There is no millisecond threshold;
  the whole suite ran in 0.54 s.

The Phase 3D and 3E tests all pass unchanged; one 3A test only renames `HisnSearchKey` to
`HisnSearchNormalizer`.

**UI tests:** the project has no UI test target, so none were added (see limitations).

**Build:** the device and simulator builds, the production IPA (checked free of fixture
code) and the fixture IPA are all green in the same run.

## Content integrity verification

`build_content.py --check`: content up to date.

- 132 canonical chapters;
- 267 numbered book items;
- 133 presentation sections;
- 302 display items.

Not changed in `git diff e72329f`:

- `hisn.json`;
- the upstream source;
- `hisn.corrections.json`;
- editorial decisions (7 DEFER);
- Quran content;
- review status (all `CONTENT_REVIEW_REQUIRED`).

Not touched: the PiP, audio, persistence, share-card and copy/share code.

## Rights status

`PENDING_PRE_RELEASE_REVIEW`, unchanged.

## Limitations

- No UI tests: there is no UI test target, and none was created for this phase.
- ة and ه are treated alike. A word ending in the pronoun ه (for example «رحمه») also matches
  the same letters ending in ة («رحمة»). This keeps queries equal to the bundled keys and
  never hides a correct result.
- Hamza on و or ي (ؤ, ئ) is not folded, following the content builder's rule.
- Multi-word partial matches need every word, but in any order and anywhere in the text.
  Within a rank, results are in book order, not by how close the words are.
- The highlight marks whole words, not the exact letters, and only the first occurrence.
- Search covers section titles and item texts, not sources or references.
- Not checked on a device or simulator by hand:
  - layout at accessibility text sizes;
  - VoiceOver order;
  - the arrival highlight.
  Physical device: NOT TESTED. Phase 3C device validation: NOT PERFORMED.

## Files changed

Added:

- `Packages/IslamicCore/Sources/HisnReading/HisnSearchNormalizer.swift`
- `Packages/IslamicCore/Sources/HisnReading/HisnSearchIndex.swift`
- `Packages/IslamicCore/Sources/HisnReading/HisnSearchEngine.swift`
- `Packages/IslamicCore/Sources/HisnReading/HisnSearchResult.swift`
- `Packages/IslamicCore/Sources/HisnReading/HisnSearchNavigation.swift`
- `docs/PHASE_3F_HISN_SEARCH.md`

Removed (split into the files above):

- `Packages/IslamicCore/Sources/HisnReading/HisnSearch.swift`

Modified:

- `Packages/IslamicCore/Sources/HisnReading/HisnAccessibility.swift`
- `Packages/IslamicCore/Tests/HisnReadingTests/HisnSearchTests.swift`
- `Packages/IslamicCore/Tests/HisnReadingTests/HisnReaderTests.swift`
- `IslamicPiPPOC/Hisn/HisnModels.swift`
- `IslamicPiPPOC/Hisn/HisnRootView.swift`
- `IslamicPiPPOC/Hisn/HisnSearchResultsView.swift`
- `IslamicPiPPOC/Hisn/HisnReaderView.swift`

## Gate

PASS_WITH_KNOWN_LIMITATIONS
