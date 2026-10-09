# Physical device release checklist

**Status: NOT_TESTED.** No device or signing exists in the build environment. Run this on a
signed **Release** build (TestFlight) on at least one iPhone. Add an iPad too, since the app
supports iPad.

Record for each run:

- device;
- iOS version;
- build number;
- date;
- PASS / FAIL with a note for each line.

## Launch

- [ ] Fresh install launches to «الرئيسية», Arabic, right to left, with no permission prompt.
- [ ] The five tabs: الرئيسية، القرآن، حصن المسلم، الأذكار، الإعدادات. No test or PiP tab.
- [ ] The home screen icon and the name «أذكار».

## Quran

- [ ] Open a surah from the list, from the juz list, and from search.
- [ ] Scrolling Al-Baqarah is smooth; the verse, juz and page in the bottom bar follow the
      scroll.
- [ ] Search «الرحمن» and «العالمين»: results appear, and a tap opens the verse with a brief
      highlight.
- [ ] Copy a verse and paste it in Notes: the text plus «سورة …، الآية n».
- [ ] Share the text, and share as an image (light and dark). In the image, the marks are
      placed correctly and nothing is cut.
- [ ] Add a bookmark; it appears under «العلامات» and in Favorites. Remove it.
- [ ] Go to an ayah (valid and invalid numbers). Use previous and next surah.
- [ ] Resume: leave mid-surah, kill the app, relaunch. «متابعة القراءة» opens the same verse.

## Hisn Al-Muslim

- [ ] Open a section; count an item with repetitions to its end; check the move to the next
      item.
- [ ] Complete a section: completion message, «الباب التالي», and the green mark in the index.
- [ ] Search an item, open it: highlight, and the repetitions are not changed.
- [ ] Copy, share, share as image.
- [ ] Resume after a kill and relaunch.

## Adhkar and duas

- [ ] Morning adhkar: count through to «أتممت أذكار الصباح». Check the Home mark.
- [ ] Haptics on and off (Settings).
- [ ] Favorite an item; open it from Favorites.
- [ ] Resume mid-item after a relaunch: the same item and the remaining count.

## Search across the app

- [ ] «الحمد لله» gives results from several sources; each opens in its tab.
- [ ] A misspelling such as «الرخيم» shows «النتائج لـ «الرحيم»».

## Audio

**N/A.** No production recordings ship. The Release build declares the audio background mode
only for PiP and has no in-app audio controls. Verify:

- [ ] No play button in the readers (PiP's own window has the system play/pause).
- [ ] Settings shows «التلاوات الصوتية: غير متاحة».

## Picture in Picture

Run the checklist in `UNIFIED_PIP.md` §13 on this Release IPA: «نافذة عائمة» in Hisn, adhkar
and duas, «تشغيل في نافذة عائمة» in the Quran, the window in front of another app, previous and
next, the long Hisn item, and closing the window.

- [ ] Another app's music: note whether it pauses when PiP starts (known limitation).

When licensed audio is added:

- play and pause;
- a phone call interruption (stays paused);
- unplugging headphones (pauses);
- the lock screen;
- background play.

## PiP

**N/A in Release** (PiP requires a recording). Verify:

- [ ] No PiP control anywhere.

With the **fixture IPA (Debug, device testing only)**, run the Phase 3C list:

- start;
- go to the background;
- open another app;
- system controls;
- close;
- return;
- lifecycle after a lock.

## Prayer times, Qibla, widgets and shortcuts

Run the 15 rows in `DAILY_COMPANION.md` §12. The next-prayer widget needs a build signed with
the App Group registered on both targets; otherwise mark its rows BLOCKED, not FAIL.

- [ ] Prayer times for a chosen city and for the shared location, with a manual correction.
- [ ] The Qibla outdoors, away from metal: the turn and «أنت متّجه نحو القبلة».
- [ ] Location denied: the saved place stays and the message names it.

## Settings and reminders

- [ ] Appearance: system, light, dark.
- [ ] Quran and adhkar text sizes.
- [ ] Turn on the morning reminder: the permission prompt appears now, not at launch. Set a
      time two minutes ahead; the notification arrives, and a tap opens morning adhkar.
- [ ] Deny permission: the notice and «فتح إعدادات النظام».
- [ ] Reset positions (confirmation; favorites kept). Clear favorites.
- [ ] «حول التطبيق»: the Tanzil notice and link, the MIT notice, the OFL licence, privacy.

## Accessibility

- [ ] VoiceOver through each tab: Arabic labels, the counter's remaining count, verse actions
      (copy, share, image, bookmark), search result labels.
- [ ] Largest accessibility text size: nothing is cut or overlapping; the counter is
      reachable.
- [ ] Reduce Motion: no animated jumps.
- [ ] Dark mode contrast on every screen.

## Offline

- [ ] Airplane mode from a fresh launch: the Quran, Hisn, adhkar, duas, every search,
      progress, favorites and counters all work.
- [ ] No network error appears anywhere.

## iPad (if kept)

- [ ] Every tab in portrait and landscape, and in Split View.
