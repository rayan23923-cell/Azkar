# Phase 3K: Hisn final UX review

## What was reviewed

The Hisn screens as a user reads them, end to end:

- the index and its sections;
- search and filters;
- the reader with its counter, audio row, copy, share and share image;
- the completion state and «next»;
- the settings that apply to Hisn (haptics, reminders);
- the VoiceOver strings.

## Finding and change

The interface called a section both «فصل» and «باب». The book itself, and the way readers
refer to it, uses «باب». Every interface string now says «باب» / «الأبواب»:

- «الباب التالي»;
- the filter «الأبواب»;
- the result row «باب · عدد الأذكار n»;
- the VoiceOver label «باب، …» and the hint «يفتح الباب»;
- the field prompt «ابحث في الأبواب والأذكار».

The tests that assert these strings were updated with them.

No content text changed. Chapter titles and item texts are read from `hisn.json` as before.

## Other checks (no change needed)

- Every control has an Arabic VoiceOver label.
- No meaning relies on colour alone: the completed mark is a symbol with a spoken value.
- Text uses system text styles, so it follows Dynamic Type.
- Layout is right to left, and the system colours give dark mode.

Settings moved from the Hisn gear to their own tab (Phase 10), so the gear was removed.

## Gate

PASS. Not checked on a device by hand (see the release report).
