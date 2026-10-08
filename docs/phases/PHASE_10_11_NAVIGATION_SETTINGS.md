# Phases 10–11: Navigation and settings

## Navigation

The app has five tabs, all Arabic and right to left:

1. «الرئيسية» (Home).
2. «القرآن».
3. «حصن المسلم».
4. «الأذكار» (adhkar and duas).
5. «الإعدادات».

The PiP technical test screen is a sixth tab, compiled into Debug builds only (`#if DEBUG`).

Favorites («المفضلة والعلامات») and global search are reached from Home.

**Home** shows:

- today's adhkar for the time of day (morning or evening, after prayer, sleep), with today's
  marks;
- «متابعة» for the Quran position and Hisn;
- Favorites, with a count;
- how many sections were finished today.

`AppRouter` moves between tabs:

- a search result, favorite, bookmark or reminder sets a target;
- the owning tab opens it once its content is loaded, and clears it.

A reminder notification opens its adhkar collection. One that arrives while the app is open
shows as a banner.

## Settings

| Setting | Detail |
|---|---|
| Reminders | Morning and evening, each on/off with its time; permission asked only when one is turned on; denied state with a button to system Settings (Phase 3J) |
| Appearance | System, light or dark (`app.appearance`) |
| Haptics | On/off |
| Quran text size | 18–44 pt, on top of Dynamic Type |
| Adhkar text size | 16–40 pt, on top of Dynamic Type |
| Audio and PiP | Status only: recitations are not available until their rights are settled, and PiP appears with a recitation. No switch for a feature that does not exist. |
| Reset reading positions and today's progress | Quran, Hisn and adhkar positions and daily progress; confirmation; favorites and reminders are kept |
| Clear favorites | Confirmation |
| About | Version, privacy statement, Tanzil notice and link, Hisn source and MIT notice (rights review pending), adhkar note, Amiri Quran OFL text |

Language: the app is Arabic only, so there is no language setting.

## Gate

PASS_WITH_KNOWN_LIMITATIONS: not checked by hand on a device.
