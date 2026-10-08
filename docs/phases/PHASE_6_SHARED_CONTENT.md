# Phase 6: Shared content architecture

Only what more than one section actually uses was shared, in `ContentKit`:

| Type | Used by |
|---|---|
| `ArabicSearchNormalizer` (key + offset map, optional dagger-alef reading) | Hisn, Quran, adhkar/dua and global search |
| `SearchMatcher` (exact / prefix / every word, whole-word excerpt and highlight) | Quran, adhkar/dua search (Hisn keeps its tested engine) |
| `ContentRef` («kind:id», Codable as a string) | favorites, bookmarks, daily progress, reminders, audio pack item ids, routing |
| `DailyProgressStore` (`content.daily.v1`, 30 days) | Hisn sections, Quran surahs, adhkar/dua collections, Home |
| `FavoritesStore` / `FavoritesModel` (`favorites.v1`) | Quran bookmarks, adhkar/dua favorites, Favorites screen |
| `ReminderController` and friends (`reminders.v1`) | Settings, notifications |

Each section keeps its own reader and position store, because their rules differ:

- Hisn: chapter cursor with repetitions;
- Quran: verse position;
- adhkar: per-collection counter.

No generic «content provider» protocol was introduced for reading; audio and PiP share the
player and surface protocols instead (Phases 8 and 9).

Every persisted value is a versioned JSON blob in UserDefaults, on the device only. Unreadable
data is removed, and the screen falls back to its default.
