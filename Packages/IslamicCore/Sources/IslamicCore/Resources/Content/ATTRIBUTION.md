# Content attribution

## Quran text — Tanzil Project

`quran.json` contains the Tanzil Quran Text (Uthmani, Version 1.1), copied verbatim
from `quran-uthmani.xml`, with surah names and metadata from Tanzil `quran-data.xml`.
Source: https://tanzil.net

```
#  Tanzil Quran Text (Uthmani, Version 1.1)
#  Copyright (C) 2007-2026 Tanzil Project
#  License: Creative Commons Attribution 3.0
#
#  This copy of the Quran text is carefully produced, highly
#  verified and continuously monitored by a group of specialists
#  at Tanzil Project.
#
#  TERMS OF USE:
#
#  - Permission is granted to copy and distribute verbatim copies
#    of this text, but CHANGING IT IS NOT ALLOWED.
#
#  - This Quran text can be used in any website or application,
#    provided that its source (Tanzil Project) is clearly indicated,
#    and a link is made to tanzil.net to enable users to keep
#    track of changes.
#
#  - This copyright notice shall be included in all verbatim copies
#    of the text, and shall be reproduced appropriately in all files
#    derived from or containing substantial portion of this text.
#
#  Please check updates at: http://tanzil.net/updates/
```

The verse text is not normalized or edited. The basmala that Tanzil stores as a separate
`bismillah` attribute on verse 1 is kept in the surah's `bismillah` field.

## Adhkar and duas

`adhkar.json` and `duas.json` are a curated selection. Items whose `quranRef` is set take
their text from the Tanzil Quran text above, as whole verses joined by a single space.
All other items were transcribed by the project and carry
`reviewStatus = CONTENT_REVIEW_REQUIRED` until a qualified reviewer checks the wording,
diacritics, source and repeat count.
