# Phase 3G: Hisn counter and daily reading

## What changed

- **Daily reading state.** Finishing a chapter (counting its last item, or «إنهاء الباب»)
  records it for today in `DailyProgressStore`.
  - The index marks those chapters with a green check, and VoiceOver reads «أُتمّ اليوم».
  - Opening, counting, navigating and search record nothing.
- **Day.** A day is the user's local calendar day (`DayKey`), so it follows time zones and
  daylight-saving changes.
- **Storage.** One JSON value in UserDefaults:
  `{"version":1,"days":{"2026-10-08":["hisn:hisn-ch-027"]}}`.
  - Only the last 30 days are kept.
  - Unreadable or unsupported data is removed.
- **Shared ContentKit target.** New package target holding:
  - `ArabicSearchNormalizer`, which `HisnSearchNormalizer` now uses, with the same rules;
  - `ContentRef` ("kind:id");
  - the daily progress store.

## Already in place and kept

These were checked and not changed:

- repetition counter («n / m», progress bar, «القراءة الأخيرة»);
- chapter progress;
- same-day repetition resume (Phase 3D);
- versioned reading cursor;
- completion haptics (Phase 3E);
- chapter completion screen;
- items without a stated count («تمّ», no invented number);
- Arabic VoiceOver text, Dynamic Type, RTL and dark mode through system styles.

## Volume-button counting: not implemented

iOS has no public API for hardware volume-button presses. The known workarounds are:

- observing `AVAudioSession.outputVolume` with a hidden `MPVolumeView`;
- resetting the volume after each press.

They change the user's system volume, need an active audio session, miss presses at minimum
and maximum volume, and behave differently with headphones and in the background. App Review
has rejected apps for this (Guideline 2.5.9, altering standard switches). The phase forbids a
fragile workaround, so none was added.

## Tests

- `DailyProgressTests`:
  - day keys in UTC, Riyadh and Los Angeles;
  - leap years;
  - daylight saving;
  - mark and read;
  - the documented format;
  - pruning;
  - corrupt, unsupported and invalid data.
- `ContentRefTests`, `ArabicSearchNormalizerTests` (including Uthmani marks).
- `HisnDailyProgressTests`:
  - completion by counting is recorded once;
  - counted taps and navigation record nothing;
  - «إنهاء الباب» records;
  - no store means no change;
  - the VoiceOver value.

Content: unchanged (132 / 267 / 133 / 302). Rights: PENDING_PRE_RELEASE_REVIEW.
