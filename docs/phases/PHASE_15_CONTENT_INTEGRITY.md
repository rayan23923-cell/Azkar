# Phase 15: Content integrity

## Counts (verified by tests and `build_content.py --check`)

| Content | Count |
|---|---|
| Quran surahs / verses | 114 / 6236 |
| Hisn canonical chapters / book items | 132 / 267 |
| Hisn presentation sections / display items | 133 / 302 |
| Adhkar collections / items | 5 / 51 |
| Dua categories / items | 2 / 17 |

## Hashes (SHA-256 at `feature/v1-release`)

| File | SHA-256 |
|---|---|
| `Content/quran.json` | `88fa18cc7101fcbb6a3571f215d70c0bbbaba29187c71e7d90d0b0169ea7a5a6` |
| `Content/hisn.json` | `a1a15f92cad28bcbb22f339484484c2ecf3b86013761918f543303e0f491323d` |
| `Content/adhkar.json` | `671a9ce5602143fc98132e915bd691ecae630398f48fc0b851399dd86c9481f7` |
| `Content/duas.json` | `df596bad80e2d6f407d9dbc6d1fec980a89aae2f709230900e29b40060334dff` |
| `Content/hisn_audio.json`, `Content/content_audio.json` | `416ab232d37b667f5cb66eddb2c3ff2252127881ea8e77f4029dd147835a160a` (identical empty packs) |
| `Upstream/tanzil/quran-uthmani.xml` | `c5052534d63d3856ce25413ff464d0b609f90169a202a1615aa8707efec81244` |
| `Upstream/tanzil/quran-uthmani.txt` | `7f30c647331a61100ebf24a80507dc0fcdd9f2df97f1312b5b2dfcb982a7f326` |
| `Upstream/tanzil/quran-data.xml` | `8867c1d88191472adec9db694b3cd9f135b1a2ef580574d32cf888dcb22c5c7a` |
| `Upstream/hisn/asellam/hisn.json` | `b30a448ef40184b0422c40bd3c372bf2b25bfb5b0539fd3699e6b4fba9459d80` |
| `QuranText/AmiriQuran-Regular.ttf` | `e2a47644762d16bdfb6d33e0d8db8c6ff30beae84150ef5a705316bbd829455c` |

## What guarantees them

- **Tanzil.** `TanzilFidelityTests` pins the upstream Tanzil hashes and compares every verse of
  `quran.json` with the upstream XML, character for character.
- **Rebuild check.** `build_content.py --check` (CI) rebuilds every content file from its
  sources, corrections and editorial manifests, and fails on any difference. Hisn corrections
  and editorial decisions are hash-pinned in `hisn.json` provenance.
- **Quranic adhkar.** Adhkar and duas with a `quranRef` must equal those Tanzil verses joined
  by a space (repository tests).
- **Screens.**
  - Readers, search previews, copy, share and share images use the stored text. Previews are
    slices, tested to be substrings of the stored text.
  - Share images check that every character was drawn.

## Changes in this release branch

Since the 3F head `50b5d6e`, the only content file added is `content_audio.json`, an empty
pack. No Quran, Hisn, adhkar or dua text changed. Review status is unchanged:

- Hisn items are all `CONTENT_REVIEW_REQUIRED`;
- 7 editorial decisions are DEFER.

## Gate

PASS
