# Phase 7: Global search

`GlobalSearch` searches the Quran, Hisn Al-Muslim, the adhkar and the duas together, offline.
It runs each section's own engine, so the results and highlights are the ones those sections
show.

## Normalization

`ArabicSearchNormalizer` folds the following, the same rules as the content builder:

- marks and tatweel are removed;
- أ إ آ ٱ become ا;
- ى becomes ي;
- ة becomes ه;
- anything that is not an Arabic letter separates words.

The Quran and Uthmani adhkar texts are also matched with the dagger alef read as alef.

## Ranking (deterministic)

1. Match strength: exact, then prefix, then every word present.
2. Titles (surah, باب, collection) before texts.
3. Source order: Quran, Hisn, adhkar, duas.
4. Book order.

Each source's list is capped (50 by default). The header gives the full counts («312 نتيجة،
يُعرض أفضل 120»). A source filter restricts to one section.

## Typo tolerance (safe)

A correction is used only when the query, as typed, found nothing.

- Each query word of four letters or more that is not a content word may be replaced by a
  content word exactly one edit away: one letter changed, added or removed, or two neighbours
  swapped.
- The most frequent candidate wins, then the alphabetically first.
- Words under four letters are never changed.
- If any word has no candidate, nothing is suggested.

The screen says «لا نتائج لما كُتب. النتائج لـ «…»». So a correction is always a real word of
the content, never replaces a query that matched, and is shown to the user.

## UI

Home has «البحث في القرآن والأذكار والأدعية». The search screen has a field, a source picker,
and rows labelled by source. A tap opens the result in its own tab:

- a Quran verse is highlighted;
- a Hisn item opens at its item, without changing repetitions (the 3F rule);
- an adhkar or dua item opens at that item.

## Tests

`GlobalSearchTests` covers:

- empty and non-Arabic queries;
- results from several sources with the ranking order checked pair by pair;
- no duplicates;
- equal results with and without tashkeel;
- titles first, and destinations;
- source filter and limits;
- typo correction only when nothing matched, short words untouched, determinism;
- the edit-distance rules;
- previews are slices of the stored verse.

## Gate

PASS
