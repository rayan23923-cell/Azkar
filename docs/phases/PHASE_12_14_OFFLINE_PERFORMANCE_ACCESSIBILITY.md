# Phases 12–14: Offline, performance, accessibility

## 12. Offline reliability

**Network.** A source scan of the app and the package (`URLSession`, `URLRequest`,
`NWConnection`, web views, `dataTask`) finds no networking code. The only outbound actions are:

- the «tanzil.net» link in About (required by the Tanzil terms, opened only on tap);
- «فتح إعدادات النظام» (system Settings).

**Content.** Everything ships in the app bundle:

- Quran, Hisn, adhkar and duas JSON;
- the audio manifests;
- the Quran font.

The Release bundle contents are listed by CI.

**Persistence.** All local, in UserDefaults:

| Key | Holds |
|---|---|
| `quran.position.v1` | Quran reading position |
| `hisn.reader.position.v1` | Hisn reading position |
| `adhkar.positions.v1` | adhkar and dua positions |
| `content.daily.v1` | daily progress |
| `favorites.v1` | favorites and bookmarks |
| `reminders.v1` | reminder settings |
| `hisn.reader.haptics` | haptics setting |
| `quran.textSize`, `adhkar.textSize` | reader text sizes |
| `app.appearance` | appearance |

Each structured value is versioned JSON. Unreadable or unsupported data is removed and the
screen starts from its default (tested per store).

**Failure paths.** A content file that fails validation shows an Arabic error with
«إعادة المحاولة» instead of crashing. A stale saved position or favorite is ignored, not shown.

**Reminders** are local notifications scheduled on the device, in local time.

## 13. Performance

**Build once.** Search indexes are built once, off the main thread, and shared:

- Quran: 6236 verses, each indexed twice;
- Hisn: 435 entries;
- adhkar and duas: 75 entries;
- the global vocabulary.

`ContentStore` caches the loaded Quran and adhkar for every screen, so two tabs never load
twice.

**Measured in CI.** The whole package suite (303+ tests, including several full-Quran index
builds and searches) runs in about 8 s on the CI runner. No test has a millisecond threshold,
because timings on shared runners are not stable.

**Lists.** The Quran reader uses a lazy stack (one surah at a time). The surah list and search
results are plain lists, and searches run only when the query or the filter changes.

**Size.** The Release app is 7.1 MB uncompressed. The largest parts are the Quran JSON (1.4 MB)
and the Amiri Quran font.

**Not measured:** device launch time, memory and scrolling smoothness. That needs a device and
Instruments.

## 14. Accessibility audit

- **Labels.** Every icon-only control has an Arabic label:
  - toolbar buttons and menus;
  - the counter;
  - the clear-search button.
  Rows combine into one element with a label and value; verses and items expose
  copy / share / image / bookmark as VoiceOver actions.
- **Strings.** All user-facing VoiceOver strings in the packages are tested to be Arabic
  (no Latin letters), with number agreement:
  - Hisn and Quran;
  - adhkar counts;
  - result counts.
- **Dynamic Type.**
  - System text styles everywhere.
  - Quran text uses `relativeTo: .title2`.
  - Adhkar text uses `@ScaledMetric`, on top of the reader's own size.
- **Reduce Motion.** Arrival highlights and scroll jumps are not animated.
- **Colour.** System colours with an accent that has light and dark variants. A completed
  state is a symbol with a spoken value, not colour alone.
- **Direction.** Right to left on every tab. Arabic-Indic digits for ayah markers; spoken
  numbers come from the label.
- **Not done:**
  - a full VoiceOver pass on a device;
  - checking layout at the largest accessibility sizes by hand;
  - an automated UI test target (the project has none).
