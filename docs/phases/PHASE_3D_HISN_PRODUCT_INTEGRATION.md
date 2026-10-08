# Phase 3D: Hisn reader product integration and persistence

## 1. Objective

Make Hisn Al-Muslim a real feature of the app: reachable from the normal app navigation,
with a persistent reading cursor, clear resume, safe handling of bad saved data, clearer
completion, a more informative index, and Arabic accessibility. This phase changes no PiP
code, no audio behaviour and no content.

## 2. Starting commit

`176c9b8` on `feature/v1-phase-3c-hisn-pip` (Phase 3C, whose device gate is still pending).
Branch: `feature/v1-phase-3d-hisn-product`.

## 3. Final commit

The head of `feature/v1-phase-3d-hisn-product` carrying this document. The code was last
verified at `f941a85`: CI run 37765493562 was green.

## 4. Architecture changes

### Audit (Part A, before any change)

| Question | Finding |
|---|---|
| 1. Navigation | `IslamicPiPPOCApp` → `ContentView` (the PiP technical test screen). No tab bar. Hisn opened as a full-screen cover from a temporary button on that screen; inside it a `NavigationStack` with `HisnRoute` values |
| 2. Screen state persistence | None besides the Hisn position |
| 3. Preferences abstraction | `@AppStorage` with keys in `HisnSettings` (one key: haptics) |
| 4. Session persistence | `HisnReadingPositionStore` (protocol), `UserDefaultsHisnReadingPositionStore` (JSON, key `hisn.reader.position.v1`), saved on each reader step; resume only on the same calendar day (`HisnResume`) |
| 5. Dynamic Type | System text styles everywhere; no shared type system |
| 6. Appearance | Follows the system; no global override |
| 7. Temporary Hisn entry | `ContentView` button → `.fullScreenCover { HisnRootView() }` with a «إغلاق» button |
| 8. Settings screen | None; Hisn has a gear menu with the haptics toggle |
| 9. Search UI | `.searchable` on the Hisn index with `HisnSearchIndex` (exact, then partial) |
| 10. Lifecycle handler | `scenePhase` observed in the app only to log for the PiP engine |

Decisions: reuse the existing store protocol, `UserDefaults`, `@AppStorage`, the search and
the navigation stack; add no new persistence framework and no new settings system.

### Changes

| Layer | Change |
|---|---|
| App | `AppRootView`: a tab bar with «حصن المسلم» (first, default) and «اختبار العرض العائم» (the unchanged PiP test screen). The temporary button and full-screen cover are removed |
| `HisnReadingPosition` | explicit `version` (1), validating decoder |
| `UserDefaultsHisnReadingPositionStore` | removes unreadable or unsupported data; sorted-keys JSON |
| `HisnResume` | cursor kept across days; repetitions only on the same day; invalid cursor cleared |
| `HisnReaderController` | `persist()`, saves on `close()`, `finishedItemNumber` cue |
| `HisnLibrary` / `HisnSectionEntry` | `section(after:)`, `bookChapterNumber` |
| `HisnAccessibility` (new) | Arabic VoiceOver text for the counter, item position and index rows |
| Reader view | «الفصل التالي» on completion, finished-item note and announcement, distinct previous/next labels, compact previous/next at accessibility sizes, save on background |
| Index view | chapter number, morning/evening marks, bookmark on the current section, richer «متابعة القراءة» |

Untouched: `PiPEngine` (beyond Phase 3C), `HisnPiPCoordinator`, `SampleBufferPiPSurface`,
`HisnPiPFrameRenderer`, the audio player and session, the fixture build, `HisnSession`,
search, content and tools.

## 5. Persistence model

**Two separate concepts:**

- **Persistent reading cursor** (`HisnReadingPosition` in `UserDefaults`): long-lived and
  survives termination. It records where the reader stopped.
- **Reading session** (`HisnReader` wrapping the domain `HisnSession`, held by
  `HisnReaderController`): in memory only while a chapter is open. It does navigation and
  repetition counting. It is built from the cursor when resuming, and it writes the cursor at
  each reading transition. It is never stored itself.

**Format, version 1** (one JSON value, key `hisn.reader.position.v1`):

```json
{"chapterId":"hisn-ch-017","completedRepetitions":2,"itemId":"hisn-017-01",
 "itemIndex":0,"savedAt":781506000,"version":1}
```

- `savedAt` is the time of the last reading activity, in seconds since 2001-01-01 (the
  Foundation default).
- Data without `version` (Phase 3A) reads as version 1.
- Any other version, a missing field, the wrong type, an empty id or a negative number makes
  the stored value invalid. It is removed and treated as "no cursor".

**Not stored:** PiP state, audio position or state, and audio completion.

**Writes happen only at reading transitions:**

- opening an item;
- counting a recitation;
- next, previous or restart;
- leaving the reader;
- the app moving to the background.

Nothing is written per frame, per audio tick or per scroll. Completing a chapter clears the
cursor, because nothing is left to resume.

## 6. Resume semantics

When Hisn opens (or the index reappears), `HisnResume.position` decides:

| Saved state | Result |
|---|---|
| none | index only |
| valid | «متابعة القراءة» (chapter, «الذكر n من m», last read time) above the full index |
| valid, same calendar day | resumes the item with its counted repetitions |
| valid, earlier day | resumes the item with repetitions back to zero |
| chapter or item no longer exists | cursor cleared, index only |
| corrupted / incomplete / unsupported version | cursor cleared, index only |

A stale item index is corrected by item id. Opening a chapter from the index resumes the
saved item when the cursor is in that chapter, otherwise it starts at item 1.

## 7. Navigation integration

The app opens on the «حصن المسلم» tab: index, search, and reader in one navigation stack,
right to left. The selected tab is kept per scene. The PiP technical test screen is the
second tab, unchanged. Its Hisn button is gone, and Hisn no longer depends on it.

Completion offers:

- «إعادة»;
- «الفصل التالي» with the next section's title. This replaces the finished chapter, so back
  returns to the index;
- «الفهرس»;
- «الرجوع إلى آخر ذكر».

Nothing changes chapter automatically.

When the last required recitation of an item moves the reader on, the reader says so. This
is the existing session rule, kept unchanged. The reader shows «أتممت الذكر n، وهذا الذكر
التالي» and VoiceOver announces it. The user then continues with «التالي» or goes back with
«السابق».

Chapter 27 stays as two presentation sections. Both show the canonical number 27, with a sun
or moon mark, and VoiceOver reads «الباب 27، …، قسم الصباح / قسم المساء». No domain data
changed.

## 8. Accessibility changes

All labels are Arabic:

- Previous and next are read as «الذكر السابق» and «الذكر التالي» («إنهاء الباب» on the
  last item).
- The counter reads «العدّ، n من m» with a hint that changes on the last recitation.
- Items without a count read «تمّت القراءة» with no invented number.
- The item position reads «الذكر n من m».
- Index rows read the number, the title, the half of chapter 27, the item count, and
  «موضع القراءة الحالي» where the cursor is.
- «متابعة القراءة» is one element.
- The search field uses the prompt «ابحث في الأذكار».
- The audio and PiP controls already had Arabic labels (Phase 3B/3C).

At accessibility text sizes, previous and next show icons only (their spoken labels stay) so
the count button is not squeezed.

The labels are built in `HisnAccessibility` and tested. Their layout on a device at large
sizes was not checked.

Settings (Part L): Dynamic Type, dark mode, RTL and VoiceOver come from the system, and no
new setting was needed. The gear menu keeps the haptics toggle.

## 9. Tests

CI run 37765493562: 191 Swift tests, 0 failures (171 before). New tests:

- `HisnPersistenceTests`:
  - save, load, update, clear;
  - version 1 format, deterministic encoding;
  - Phase 3A data;
  - unsupported version, corrupted and incomplete data, invalid values;
  - valid, missing, invalid-chapter and invalid-item resume;
  - stale index.
- `HisnReaderControllerTests`:
  - save on open, next, previous, close, chapter change and recitation;
  - `persist()`;
  - completion clears the cursor;
  - finished-item cue without skipping ahead;
  - restart.
- `HisnIndexAccessibilityTests`:
  - chapter 27 numbering;
  - `section(after:)`;
  - index and counter VoiceOver text, Arabic only.
- `HisnResumeTests`: the same-day test was updated to the new rule. The cursor is kept on a
  later day and repetitions reset.

Unchanged and green:

- search, reader, structure, audio and PiP coordinator tests;
- content check, corrections and editorial tests;
- device and simulator builds;
- the production IPA (checked free of fixture code) and the fixture IPA.

## 10. Content integrity

`build_content.py --check`: content up to date. 132 canonical chapters, 267 canonical items,
133 presentation sections, 302 display items. No change to `hisn.json`, the upstream source,
`hisn.corrections.json`, editorial decisions (7 DEFER unchanged), Quran content, or review
status (all items `CONTENT_REVIEW_REQUIRED`).

## 11. Rights status

`PENDING_PRE_RELEASE_REVIEW`, unchanged. No audio added.

## 12. Physical-device status

Phase 3D was not tested on a physical device. Phase 3C physical-device validation: **NOT
PERFORMED**, so its gate stays BLOCKED, separately from this phase.

## 13. Known limitations

- Tab bar labels follow the system language. The Hisn tab content is forced right to left;
  the PiP test tab is left as it was (English).
- Leaving the app saves the cursor time again, so the last read time can be the moment the
  app went to the background.
- Completing a chapter clears the cursor, so «متابعة القراءة» disappears until another
  chapter is opened.
- The finished-item note appears after the session moves on by itself (existing rule). The
  user is told, but the move itself was not changed.
- Accessibility sizes, VoiceOver order and dark mode were not checked on a device or
  simulator by hand.

## 14. Final gate

PASS_WITH_KNOWN_LIMITATIONS: the implementation is complete and CI is green with content
unchanged. The limitations above are non-blocking.
