# Phase 5: Adhkar and duas

## Content

The bundled `adhkar.json` and `duas.json` are unchanged.

| Group | Collection | Items |
|---|---|---|
| Adhkar | morning | 11 |
| Adhkar | evening | 11 |
| Adhkar | afterPrayer | 12 |
| Adhkar | sleep | 11 |
| Adhkar | general | 6 |
| Duas | quranic | 10 |
| Duas | prophetic | 7 |

That is 68 items in all.

- Quranic items are verbatim Tanzil text (`QURAN_VERBATIM_TANZIL`).
- The rest are `CONTENT_REVIEW_REQUIRED`.

## Package: `AdhkarReading`

- **`DevotionalItem` and `DevotionalCollection`:** one model for a dhikr or a dua.
  - Each has a content reference.
  - The text, source and repeat count are the stored ones.
  - Duas are said once.
- **`AdhkarLibrary`:** loads both files through the existing repositories, then looks up
  collections and items, and locates an item's collection.
- **`DevotionalReaderController`:** the counter reader, built on `SessionCursor`.
  - A tap counts one repetition; after the item's count the next item opens.
  - The last repetition completes the collection for today and clears the saved place.
  - Previous, next, jump and restart are available.
- **Resume:** each collection keeps its own place: the item and the repetitions said
  (`adhkar.positions.v1`, versioned JSON; bad data is removed).
  - A saved count never completes an item on open.
  - Opening at a search result or favorite keeps a saved count only for that same item.
- **`DevotionalSearchIndex`:** offline search of collection titles and every text.
  - Ordered by match strength, then titles before texts, then book order.
  - Uthmani spelling is handled as in the Quran search.
- **`DevotionalAccessibility`:** Arabic counts («مرة واحدة», «مرتان», «3 مرات», «33 مرة»)
  and labels.

## App (tab «الأذكار»)

- **Index:**
  - two sections, «الأذكار» and «الأدعية»;
  - a search field and a filter («الكل», «الأذكار», «الأدعية»);
  - each collection shows its count, its resume point («متابعة من 3 من 11») and today's
    completed mark.
- **Reader:**
  - the item's position;
  - the text: Quran items in the Quran font, others in the system font at the reader's size,
    scaled with Dynamic Type;
  - the source, and how many times the item is said;
  - a large counter button with its remaining count spoken;
  - previous and next.
- **Toolbar:**
  - a favorite star;
  - copy, share text, share as image (Quran items in the Quran font);
  - text size;
  - restart.
- **Completion:** «أتممت …», recorded for today, with «البدء من جديد».
- **Haptics:** follow the existing setting (a tick per count, success at item and collection
  end).
- **Audio:** the architecture is the shared queue (Phase 8). There are no recordings (rights
  gate).

## Tests

`AdhkarReadingTests` covers:

- collections and counts, with texts and sources equal to the repositories;
- lookup;
- counting and moving on;
- completion recorded for today;
- resume with repetitions, including clamping and stale items;
- opening at an item;
- navigation ends;
- UserDefaults persistence and recovery;
- search ranking, determinism and filters;
- Uthmani spelling;
- previews equal to the stored text;
- Arabic count agreement.

## Gate

PASS_WITH_KNOWN_LIMITATIONS: the non-Quranic texts await scholarly review; there is no audio.
