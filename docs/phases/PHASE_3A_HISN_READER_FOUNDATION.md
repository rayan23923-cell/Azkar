# Phase 3A: Hisn Al-Muslim reader foundation

Final gate: **PASS_WITH_KNOWN_LIMITATIONS** (section 12).

The first reading experience for Hisn Al-Muslim: chapter index, reader, repetition
counter, same-day resume and offline search, on top of the existing IslamicCore Hisn
domain. UI and reader interaction only. No content, audio or PiP change.

- Branch: `feature/v1-phase-3a-hisn-reader`
- Base: `feature/v1-phase-2f-hisn-editorial-review` at `5d694d2` (Phase 2F is not merged;
  its content is the baseline).
- Naming note: PR #3 also contains a document called "Phase 3A" (KFGQPC audio source
  verification). That is the audio research track; this document is the Hisn reader.

**7 editorial cases remain DEFERRED by decision. No Arabic source text was changed in Phase 3A.**

## 1. Architecture

```
IslamicCore (domain, BundledHisnRepository, HisnSession / SessionCursor)
  └─ HisnReading (new library target in the same package, Foundation only)
       HisnLibrary          index of the 133 presentation sections
       HisnReader           one open chapter: wraps HisnSession, names its states
       HisnSearchIndex      offline search over the domain searchText fields
       HisnReadingPosition  the one saved position + store adapter + same-day rule
       HisnItemPresentation the user-facing fields of an item (text, sources)
  └─ App (IslamicPiPPOC/Hisn/, SwiftUI)
       HisnLibraryModel / HisnReaderModel  @MainActor glue: load, save after each step
       HisnRootView, HisnReaderView, HisnSearchResultsSection
```

- The UI never parses JSON: content is loaded only through `BundledHisnRepository`.
- Titles, text and references come from the domain; nothing is typed into SwiftUI.
- Navigation and repetition are the domain `HisnSession` / `SessionCursor`
  (`next`, `previous`, `advance`, `restart`). `HisnReader` adds no second algorithm; it only
  names the states for the screen and records "next on the last item" as completion.
- No editorial logic in the UI. `HisnItemPresentation` exposes only `text` and `sources`
  (a test checks that it carries nothing else).

Project changes needed to use the package from the app:
- The app target now links the local package (`IslamicCore`, `HisnReading`):
  `XCLocalSwiftPackageReference` in `project.pbxproj`, mirrored in `project.yml`.
- The app's deployment target goes from iOS 16.0 to **iOS 17.0**, IslamicCore's minimum
  (set in Phase 2). The device used for testing runs iOS 26.

## 2. Screens

| Screen | Content |
|---|---|
| Entry | A «حصن المسلم» button on the existing app screen opens the reader full screen. |
| Index | «متابعة القراءة» (same day only), then the 133 sections in order with their item counts; search field «ابحث في الأذكار». |
| Reader | Progress bar, item text, «المصدر» (collapsed), the repetition button, «السابق» / «التالي» with "n / m". |
| Completion | «أتممت هذا الباب», «إعادة», «الفهرس», «الرجوع إلى آخر ذكر». |
| Search | Results (exact first), «لا توجد نتائج» when nothing matches. |
| Errors | «تعذّر تحميل حصن المسلم من التطبيق.» with «إعادة المحاولة»; «تعذّر فتح هذا الباب.» |

Visual language: the existing app is the PiP technical test screen (one ScrollView, system
buttons, no design system). The reader uses the same thing: system SwiftUI components and
text styles, the system tint, no custom colours or fonts. No second visual system and no
redesign of the shell.

Entry point: the request asked for an entry in the existing navigation. The app has a single
screen, so the entry is one button there, presenting the reader with `fullScreenCover`. The
PiP layer stays mounted underneath; `PiPEngine.swift`, `AzkarFrameRenderer.swift`,
`IslamicPiPPOCApp.swift` and `Info.plist` are untouched. This is the one change inside the PiP golden-path folder
(`ContentView.swift`, 15 lines added).

## 3. Navigation

- The index lists `book.chapters` in order: 133 presentation sections. Chapter 27 arrives
  from the domain as two sections titled «أذكار الصباح» and «أذكار المساء» (marked with a sun
  and a moon); no other chapter is split.
- Opening a section starts at its first display item (or at today's saved place in it).
- «التالي» / «السابق» move through the chapter's display items through `HisnSession`.
  «السابق» stops at the first item. «التالي» on the last item shows the completion state.
- The reader never moves into another chapter by itself. Completion offers «إعادة» (first
  item, nothing counted) and «الفهرس» (back to the index).
- Progress is over display items (`index / count`, 1 when complete), never
  `bookItemNumber`.

## 4. Search

- Offline only. The index is built once from the loaded book: chapter titles and item
  texts, through their domain `searchText` keys.
- The query is turned into a key with the same rules as the content builder's
  `search_text` (`HisnSearchKey`): marks and tatweel removed, أ/إ/آ/ٱ → ا, ى → ي, ة → ه,
  everything else that is not an Arabic letter becomes a space. A test checks that this
  gives exactly the bundled `searchText` for all 133 titles and 302 items.
- Exact: the query appears as whole words, in order. Partial: every query word appears,
  possibly inside a longer word. Exact results come first, then partial, each in book order.
- A result row shows the bundled text (three lines) and its chapter; tapping it opens that
  item. A title match opens the chapter at its first item.
- No Arabic letters in the query: no results. Nothing found: «لا توجد نتائج».

## 5. Session and resume

- The only persisted state is `HisnReadingPosition` (chapter id, item id, item index,
  repetitions counted, saved at), one JSON value in `UserDefaults`
  (`hisn.reader.position.v1`), behind the `HisnReadingPositionStore` protocol. It restores a
  `HisnReader`; it is not a second session model.
- Saved after every step (open, recitation, next, previous, restart). Cleared when a chapter
  is completed.
- Resumed only on the same calendar day (`Calendar.isDate(_:inSameDayAs:)`). From the next
  day the index opens without «متابعة القراءة».
- Restore finds the item by id (the index is only a check), rebuilds the cursor with
  `jump` + the counted `advance` steps, and starts the item again if the saved count is not
  below the item's count. Unknown chapter or item: nothing to resume.

## 6. Repetition

| Content | Shown | One tap |
|---|---|---|
| Count above 1 | "completed / total" (large), «اضغط بعد كل قراءة» | counts; the last count moves to the next item |
| Count 1 | «تمّ» | next item |
| No count (`nil`) | «تمّ», no number | next item (read once) |

- The count is the domain `repetition.count`. Nothing is inferred: a nil count shows no
  number (checked for every one of the 302 items).
- The last count of the last item shows the completion state.
- The button is the full width of the screen and at least 88 points high.
- Optional haptics: a light tap per count and a success tap on completion, on by default,
  switch «الاهتزاز عند العدّ» in the index menu.

## 7. Accessibility

- Arabic first: the reader forces right-to-left layout and the Arabic locale; directional
  icons follow the reading direction.
- Dynamic Type: system text styles only (`title2` for the text), no fixed sizes for text.
- Dark mode: system colours and materials only.
- VoiceOver, Arabic labels: counter «العدّ», value "n من m", hint «اضغط مرة بعد كل قراءة»;
  «تمّت القراءة» with «ينتقل إلى الذكر التالي» / «ينهي الباب»; progress «الذكر n من m»;
  index rows read the title and «عدد الأذكار n»; decorative icons hidden.
- Lists are SwiftUI `List` (lazy).

## 8. Not shown to users

Review flags, correction ids, editorial decision ids, hashes, internal ids, P0/P1,
`CONTENT_REVIEW_REQUIRED`, DEFER, `sourceCount`, `bookStatedCounts`, book item relations
(`SPLIT_PART`, `EVENING_VARIANT`, `DIRECT`), provenance and licence. References are shown as
the source prints them, under «المصدر»; no hadith number, grading, collection name, volume
or page is added.

## 9. Editorial status

Unchanged from Phase 2F. 15 P0 decisions: 2 KEEP_SOURCE, 3 KEEP_METADATA, 3 KEEP_NIL,
7 DEFER (016-01, 016-06, 017-04, 029-15, 037-02, 052-02, 112-01). `independentReviewer`
null, `editorialReviewComplete` false, every item `CONTENT_REVIEW_REQUIRED`. The reader shows
each item's bundled text in full, including the three `nonRecitationText` spans; it does
not hide or restyle them (a later recitation flow can). Rights stay
`PENDING_PRE_RELEASE_REVIEW`.

**7 editorial cases remain DEFERRED by decision. No Arabic source text was changed in Phase 3A.**

## 10. Tests

New target `HisnReadingTests` (runs in `swift test`), on the bundled content:

| Area | Tests |
|---|---|
| Structure | 132 canonical / 267 book items / 133 sections / 302 display items |
| Navigation | 133 sections in order with domain titles; 27 as morning/evening; each chapter opens at its first item; next/previous match `HisnSession`; previous stops at the start; next on the last item completes without leaving the chapter; restart; return from completion; out-of-range item |
| Repetition | known count (3 taps, then next); final count of the last item completes; count 1; nil counts (029-06, 130-02, 130-06, 025-02) read once; every item shows only its stated count |
| Search | query key equals every bundled key; marks and letter forms; exact; partial; exact before partial; title match; no results; every result opens a real item |
| Session | leave/return restores item and repetitions; restore after navigation; same day only; completion clears; boundaries (count at/over total, negative, stale index, unknown chapter/item); UserDefaults round trip and bad data |
| Presentation | text is the bundled text for all 302 items; only text and sources are exposed |

Regression, CI run 37753268076 on `c652316`:

| Check | Result |
|---|---|
| `python3 tools/content/build_content.py --check` | content up to date |
| `python3 tools/content/test_hisn_corrections.py` | OK |
| `python3 tools/content/test_hisn_editorial_review.py` | OK |
| `swift test` (CI) | 104 tests, 0 failures (75 existing + 29 new) |
| Full iOS app build, device and simulator (CI) | BUILD SUCCEEDED; `MinimumOSVersion` 17.0, `UIBackgroundModes` audio still present, unsigned IPA packaged |

## 11. Excluded

Audio, Quran audio, PiP changes, AVFoundation changes, background audio, notifications,
widgets, sharing as image, volume-button counting, external display, rights, content
corrections, new Quran / dhikr / dua content, CloudKit, login, network search.

## 12. Final gate

**PASS_WITH_KNOWN_LIMITATIONS**

Every requested reader feature is implemented and covered by tests, and the app builds.
Known limitations:
- Not run on a device or simulator by a person: VoiceOver reading, Dynamic Type at the
  largest sizes, dark mode and haptics are built with system components but not observed.
- The SwiftUI views have no UI tests (the app has no test target); the state they show is
  tested in `HisnReadingTests`.
- The app had no visual language beyond the PiP test screen, so the reader uses plain
  system styling.
- The entry point is a button on the PiP test screen until the app shell exists.
- The app's minimum iOS is now 17.0. With it, Xcode reports one new deprecation warning in
  the untouched `IslamicPiPPOCApp.swift` (`onChange(of:perform:)`); left as is, since that
  file is the PiP golden path.
- The first CI run of this branch failed to compile the new tests (an `await` inside
  `XCTUnwrap`); fixed in `c652316`.

Phase 3B is not started.
