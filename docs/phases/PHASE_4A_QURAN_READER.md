# Phase 4A: Quran production reader

## Scope

A Quran reader over the bundled Tanzil Uthmani text (114 surahs, 6236 verses), offline. The
text is never edited; `quran.json` and its upstream files did not change in this phase.

## Package: `QuranReading`

| Type | Job |
|---|---|
| `QuranLibrary` | Loads the bundled Quran once and refuses incomplete content (exactly 114 / 6236). Provides surah and verse lookup, the juz and page of a verse, the first verse of a juz, and the previous and next verse across surahs. |
| `QuranMetadata` | 30 juz starts and 604 page starts, generated from Tanzil `quran-data.xml` and tested against it. |
| `QuranVerseRef` | A verse reference, ordered in mushaf order, convertible to and from a `ContentRef` («quran:2:255»). |
| `QuranReadingPosition`, `UserDefaultsQuranPositionStore` | The resume point (key `quran.position.v1`, versioned JSON). Bad data is removed; a position outside the Quran is ignored. |
| `QuranReaderController` | The reader state: surah, current verse, juz, page and progress; go to a verse; previous and next surah. Scrolling updates the verse without writing; the position is saved on open, on a jump, when leaving and when going to the background. Reaching the last verse records the surah as read today. |
| `QuranSearchIndex`, `QuranSearchEngine` | Offline search of surah names and every verse, ranked surah exact, surah prefix, verse exact, verse prefix, surah partial, verse partial, then mushaf order. Each verse is indexed twice (dagger alef dropped, and read as alef), so standard spelling finds Uthmani words («العالمين», «الرحمن»). |
| `QuranShareContent`, `QuranAccessibility` | Copy and share text (the verse, then «سورة X، الآية n»), and the Arabic VoiceOver strings. |

## App

- **Index:** the surah list (number, name, Meccan/Medinan, verse count, today's mark), the juz
  list, the bookmarks, «متابعة القراءة», and search with filters («الكل», «السور», «الآيات»)
  and highlighted whole words.
- **Reader:**
  - one surah, verse by verse, with the basmala header (none for At-Tawba; Al-Fatiha's is
    verse 1);
  - ayah numbers in Arabic-Indic digits;
  - the bottom bar shows the verse, juz and page, with a progress bar.
- **Per verse** (menu, context menu or VoiceOver actions): copy, share text, share as image,
  add or remove a bookmark.
- **Toolbar:** go to an ayah, and text size.
- **Footer:** previous and next surah.
- **Arrivals:** a search result or bookmark opens at its verse and marks it briefly (no
  animation with Reduce Motion).
- **Bookmarks:** these are Favorites entries (`favorites.v1`) with a Quran reference, so they
  also appear in the Favorites screen.

## Tests

`QuranReadingTests` covers:

- the whole Quran loads, and incomplete content is refused;
- metadata against Tanzil;
- juz and page lookup (2:255 is in juz 3, page 42);
- neighbours across surahs;
- the position format and recovery from bad data;
- controller behaviour (scrolling does not save, jumps do);
- daily completion;
- search ranking and determinism, and Uthmani spelling;
- share text equals the stored verse;
- accessibility strings.

`QuranShareCardTests` covers the share image (next phase). The suite passes in CI.

## Limitations

- Mushaf words written differently from standard spelling in other ways (for example
  «الصلوٰة») match only in their Uthmani form.
- The reader is a verse list, not a page-faithful mushaf layout.
- Not checked by hand on a device.

## Gate

PASS_WITH_KNOWN_LIMITATIONS
