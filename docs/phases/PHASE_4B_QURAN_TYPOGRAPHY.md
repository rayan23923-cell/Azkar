# Phase 4B: Quran typography

## Decision

The Quran text is drawn in **Amiri Quran** (Khaled Hosny, SIL Open Font License 1.1), bundled
in the `QuranText` target. It replaces the system font, which does not shape Uthmani marks
reliably.

KFGQPC fonts were the first choice. They could not be fetched from this environment, and
their licence would need its own review.

- **File:** `AmiriQuran-Regular.ttf`, from `google/fonts`, `ofl/amiriquran`.
- **SHA-256:** `e2a47644762d16bdfb6d33e0d8db8c6ff30beae84150ef5a705316bbd829455c`.
- **Licence:** the OFL text ships beside the font (`AmiriQuran-OFL.txt`) and is shown in
  Settings, under About.

## Implementation

- `QuranFont.register()` registers the font for the process (Core Text) at launch. It reports
  missing glyphs for any text.
- `QuranTextLayout` lays out text with Core Text at a given width. Tests use it to prove
  nothing is dropped.
- SwiftUI uses `Font.custom("Amiri Quran", size:, relativeTo: .title2)`, so the Quran text
  also follows Dynamic Type. The reader adds its own size setting (18–44 pt) and generous
  line spacing.
- The verse share image uses the same font through the shared card renderer.
  - The renderer fails rather than fall back to another font.
  - The card checks that every character was drawn.

## Verification

- `fontTools`: all 70 distinct characters of the bundled Quran are in the font's cmap.
- `QuranTypographyTests` covers:
  - registration and the licence file;
  - full character coverage over the whole text;
  - Al-Baqarah 282, the longest verse, at widths 320, 390 and 700 with no missing glyph and
    every character laid out;
  - all of Al-Baqarah;
  - a larger size takes more lines.
- `QuranShareCardTests` checks that the verse 2:282 card draws every character in Amiri Quran
  and grows taller rather than cutting the text.

## Limitations

The visual quality of mark placement was not reviewed by a qualified reader on a device.

## Gate

PASS_WITH_KNOWN_LIMITATIONS
