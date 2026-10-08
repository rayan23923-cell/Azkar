# Phase 3E: Hisn reader actions and interaction layer

## 1. Objective

Give the Hisn reader the actions of a finished consumer feature:

- copy the dhikr;
- share it as text;
- share it as a generated image;
- one item action menu;
- a testable haptic layer;
- clearer repetition feedback;
- Arabic accessibility for all of it.

No PiP, audio, rights or content work.

## 2. Base commit

`7e71d8b` (Phase 3D documentation commit, head of `feature/v1-phase-3d-hisn-product`, PR #12).
PR #12 was not merged, so the branch starts from that head.

## 3. Branch

`feature/v1-phase-3e-hisn-actions`

### Audit (before changes)

| Looked for | Found |
|---|---|
| Share infrastructure | none |
| Clipboard utilities | none (only the PiP test screen's log copy, `UIPasteboard` inline) |
| Image rendering for sharing | none. `HisnPiPFrameRenderer` / `AzkarFrameRenderer` draw PiP frames and are off-limits |
| Haptics | two `.sensoryFeedback` modifiers in `HisnReaderView` (light per recitation, success on completion) behind `@AppStorage("hisn.reader.haptics")`; no abstraction |
| Accessibility helpers | `HisnAccessibility` (Phase 3D) |
| Theme / typography | system styles and colours; no custom theme or Arabic font |
| `HisnItem` | `arabicText` (stored text), `nonRecitationText` annotations (narration, closing, label, instruction; each occurs once inside `arabicText`), references, review metadata |
| UI tests | no UI test target in the project |

Everything new extends what exists. `HisnAccessibility` and the haptics setting key are
reused, and the view-level haptics are replaced rather than duplicated.

## 4. Action menu

The reader's toolbar has «…» (`ellipsis.circle`), read by VoiceOver as «إجراءات الذكر». It is
shown while an item is on screen and holds three actions:

- «نسخ»
- «مشاركة»
- «مشاركة كصورة»

It is a system `Menu`, so it lays out right to left with the rest of Hisn. Nothing else in the
reader was redesigned.

## 5. Copy implementation

`HisnItemActions.copy(_:)` writes `HisnShareContent.text` to the clipboard. That text is
`HisnItem.arabicText`, unchanged, through the `HisnTextPasteboard` protocol (`UIPasteboard`
in the app). Success means the clipboard reads back exactly that text. Only then does it give
the copy haptic and the transient notice «تم النسخ», which is also announced to VoiceOver and
disappears after about 1.6 s.

No ids, chapter ids, review state, corrections, provenance, references, JSON or debug text
are added.

**Non-recitation text.** The source embeds narration, closing text and labels inside
`arabicText` for three items (`hisn-001-03`, `hisn-029-14`, `hisn-133-01`). The domain marks
those parts but keeps them in the text. Copy and share use the text exactly as the reader
shows it, so the marked parts stay where the source puts them. Stripping them would rewrite
the stored text, and no new classification was invented.

## 6. Text sharing

«مشاركة» opens the iOS share sheet (`UIActivityViewController`) with one item: the same text
as copy. There are no custom integrations, uploads, accounts or network.

## 7. Share card renderer

`HisnShareCard` is a new package target. It uses Core Text and Core Graphics only: no UIKit,
no network, no dependency. It is deterministic and runs in `swift test`.

- **Input:** `HisnShareContent` (the item's `arabicText` and its chapter title). The renderer
  holds no copy of any Hisn text.
- **Drawn, top to bottom:**
  - «حصن المسلم» (accent colour);
  - the chapter title;
  - a thin rule;
  - the whole text, bold 50 px, line height ×1.45, base direction right to left, natural
    (right) alignment, word wrapping.
- **Not drawn:** no author, attribution, ids, review or rights status.
- **Dimensions:** 1080 px wide; at least 1080 px tall, so short text gives a square with the
  text centred under the rule; taller as the text needs. 96 px side margins. The long item
  `hisn-001-04` (1864 characters) gives a card over 2000 px tall.
- **Long text:** the height comes from Core Text's measurement of the full text at the fixed
  size. After drawing, the renderer checks that Core Text placed every UTF-16 unit of the
  body. If not, it returns nil and the app shows «تعذّر إنشاء الصورة». It never shrinks,
  ellipsizes, truncates or splits the text.
- **Appearance:** light (warm off-white, dark text) or dark (deep green-black, light text),
  following the reader's colour scheme when generated.
- **Dynamic Type:** the image has a fixed pixel size, so it does not follow Dynamic Type.

The app wraps the `CGImage` in a `UIImage` and hands it to the share sheet.

## 8. Haptic abstraction

`HisnHaptics` is a `@MainActor` protocol with `play(_ event: HisnHapticEvent)`. Events:

- `itemCompleted`
- `chapterCompleted`
- `copied`
- `cardReady`

The app's `SystemHisnHaptics` plays:

- notification success for completion and copy;
- selection for the card.

It honours the existing haptics setting (now labelled «الاهتزاز») and does nothing on hardware
without haptics. `HisnReaderController` and `HisnItemActions` take it by injection; tests use
`FakeHaptics`. When something fails there is no feedback.

**Change from Phase 3A:** the light tap on every counting press is removed. Feedback now marks
only completing an item's count, completing the chapter, a successful copy and a generated
card, as the phase asks.

## 9. Repetition UX

The semantics are unchanged: `HisnSession` was not touched. In the counter button, items with
a stated count now show:

- a progress bar under «n / m»;
- «القراءة الأخيرة» before the final recitation.

The Phase 3D note «أتممت الذكر n، وهذا الذكر التالي» still marks completion.

Items without a count still show «تمّ» with no number. Audio completion and PiP do not count;
those paths were not touched, and the Phase 3B/3C tests still cover them.

## 10. Accessibility

New controls:

- «إجراءات الذكر» (the menu);
- «نسخ الذكر»;
- «مشاركة الذكر»;
- «مشاركة الذكر كصورة»;
- notices «تم النسخ» and «تعذّر إنشاء الصورة», spoken.

The counter value is now «التكرار n من m». Items without a stated count announce no value,
never a made-up total.

The image is never the only way to reach the text: the reader text, copy and text share all
remain.

## 11. Tests

CI run 37769844957 (head `b04eb70`): **209 Swift tests, 0 failures**, up from 191.

`HisnItemActionsTests` (11 tests) cover:

- copy is the exact stored text for short, long, multi-line, parenthesis, Quran-citation and
  non-recitation items;
- no metadata, and no appended references;
- non-recitation parts kept;
- a failed copy gives no feedback;
- text share payload;
- card feedback only on success;
- completion feedback without per-tap feedback;
- chapter feedback exactly once;
- the reader works without haptics;
- Arabic action labels;
- spoken progress, with no invented total.

`HisnShareCardRendererTests` (7 tests) cover:

- nine items (very short, medium, long, multi-line, parentheses, Quran citation, narration,
  labels, closing): width 1080, height ≥ 1080, every character laid out, body equals the
  domain text;
- only header, title and text are drawn;
- height grows with the text;
- every body line has right-to-left runs;
- non-empty image, light and dark backgrounds differ;
- deterministic pixels;
- no network or platform UI in the renderer.

Phase 3D's accessibility test now expects «التكرار n من m».

UI tests: the project has no UI test target, so none were added.

The content checks, both builds, the production IPA (checked free of fixture code) and the
fixture IPA all stayed green.

## 12. Content integrity

`build_content.py --check` reports the content up to date:

- 132 canonical chapters;
- 267 canonical items;
- 133 presentation sections;
- 302 display items.

Not changed:

- `hisn.json`;
- the upstream source;
- `hisn.corrections.json`;
- editorial decisions (7 DEFER).

Review status stays `CONTENT_REVIEW_REQUIRED` everywhere. The share layer reads
`HisnItem.arabicText` only.

## 13. Rights status

`PENDING_PRE_RELEASE_REVIEW`, unchanged. The card carries no attribution or licence claim. It
can be given one, or the feature can be gated, by the later rights decision without
architectural change.

## 14. Physical-device status

NOT TESTED. Haptic hardware, real share targets and on-device rendering of the menu and card
are unverified. Phase 3C physical-device validation also remains NOT PERFORMED.

## 15. Known limitations

- No UI tests: the project has no UI test target.
- The share card is not checked against an Arabic typographer's review. It uses the system
  Arabic font, chosen by Core Text from the system UI font for Arabic.
- Very long items make tall images; some apps may downscale them when sending.
- The per-recitation light tap from Phase 3A is gone. Counting without looking now relies on
  the visual counter and VoiceOver.
- The card follows the colour scheme at the moment it is generated, not the share target's.

## 16. Final gate

PASS_WITH_KNOWN_LIMITATIONS
