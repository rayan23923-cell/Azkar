# Daily companion: links, shortcuts, resume, routine, widgets

This covers the work on branch `claude/daily-companion` (stacked on the prayer times and Qibla
branch). Everything runs on the device. Nothing is fetched, and no permission, background mode
or tracking was added.

## 1. Audit before the work

| Area | Found | Done here |
|---|---|---|
| App Intents, WidgetKit, ActivityKit | none | App Shortcuts and a widget extension; Live Activity evaluated (section 9) |
| URL scheme and `onOpenURL` | none | `azkarapp://` with strict parsing |
| Targets | one app target | plus `AzkarWidgetsExtension`, embedded in the app |
| Saved positions | Quran, Hisn and adhkar/duas each save a position with `savedAt` | read together for «أكمل من حيث توقفت» |
| Bundle ID | placeholder `com.example.IslamicPiPPOC` | unchanged; the widgets and App Group derive from it |
| `project.yml` | missed the `PrayerTimes` dependency | fixed, and the widget target added |

## 2. Links (`AppLink`, ContentKit)

| URL | Opens |
|---|---|
| `azkarapp://home` | Home |
| `azkarapp://prayer` | Prayer times (on Home's stack) |
| `azkarapp://qibla` | The Qibla |
| `azkarapp://resume` | The most recent place read (section 4) |
| `azkarapp://quran` | The Quran at the saved verse, or its index |
| `azkarapp://open?ref=<ContentRef>` | One item or collection, e.g. `adhkar:group:morning`, `hisn:hisn-017-03`, `quran:2:255` |

Anything else opens nothing: another scheme, an unknown host, a path, an extra or repeated
query item, a ref that does not parse, or a URL longer than 300 characters. A ref that parses
but no longer exists is resolved by the same code as Favorites. Each case lands as follows:

- an adhkar or dua id that is not found opens the collection;
- an unknown collection shows «تعذّر فتح هذا القسم»;
- an unknown Hisn item opens nothing;
- a verse outside the Quran shows «تعذّر فتح هذه السورة».

**Opening a link never counts a repetition or marks anything done.** Package tests cover this:
`OpeningFromALinkTests` checks that nothing is counted, saved or completed on open. Reading
positions follow the rules the readers already had:

- An adhkar or dua opened at an item becomes that collection's place when its screen closes,
  as from search or Favorites.
- A Hisn item opened from a link becomes the Hisn cursor on open. This is the Phase 3F rule for
  search and Favorites ("the reader saves the cursor on open").
- A Quran verse opened from a link becomes the reading position, as from Favorites.
- Opening a collection (shortcut, routine) resumes it where it stopped.

These pre-existing rules were not changed here. The only automatic surface, the dhikr widget,
shows nothing until content is reviewed (section 8).

**Cold start.** A link that launches the app is queued on the router. Each tab opens it once
its content has loaded (`onChange(…, initial: true)` and the load handlers), so a widget tap
on a closed app lands in the same place as on an open one.

## 3. Shortcuts and Siri (`App/AppShortcuts.swift`)

| Shortcut | Behaviour |
|---|---|
| الصلاة القادمة | Says the next prayer, its time, the place and the time left, without opening the app. With no place saved it says so; it never asks for the location. |
| مواقيت الصلاة | Opens the prayer times |
| اتجاه القبلة | Opens the Qibla |
| أكمل من حيث توقفت | Opens the most recent place |
| فتح القرآن الكريم | The Quran at the saved verse |
| أذكار الصباح / أذكار المساء | Opens the collection at its saved item, counting nothing |
| فتح أذكار أو أدعية | Any adhkar group or dua category, picked in the Shortcuts app |

The phrases are in Arabic and English and include the app's name, as App Shortcuts require.

## 4. «أكمل من حيث توقفت»

Each reader already saves its position with the time it saved it:

- the Quran (`quran.position.v1`);
- Hisn (`hisn.reader.position.v1`, cleared when a chapter is finished);
- each adhkar and dua collection (`adhkar.positions.v1`, cleared when finished).

`ResumePoint.mostRecent` takes the latest `savedAt`. A tie (same instant) goes to Quran, then
Hisn, then adhkar, then duas, then the smaller reference, so the same saved state always gives
the same answer. A position whose chapter, collection or item no longer exists is skipped.
Hisn and the adhkar reopen with the repetitions already said; the Quran opens at the verse.

Home shows the place first in «متابعة», and the Quran row only when the Quran is not already
the one offered.

## 5. Optional daily routine («الورد اليومي»)

- Off until turned on in Settings › الورد اليومي. When off, Home shows nothing of it.
- Steps: أذكار الصباح، ورد القرآن، أذكار بعد الصلاة، أذكار المساء، أذكار النوم. Each can be
  turned off, and the order changed (تعديل, then drag).
- Home marks a step done only for today:
  - an adhkar step when its collection was completed today;
  - the Quran when a verse was reached today.
- No streaks, no count of days, no mention of a missed day, and nothing carried over.
- Reminders are not duplicated: the existing morning and evening reminders in Settings stay
  the only ones.
- Stored in `routine.v1`, versioned. Unreadable data or an unknown version turns the routine
  off rather than guessing; a step a later version adds is dropped.

## 6. Prayer times reliability

- **Day rollover.** The screen redraws every second and the Home row every minute from the
  schedule of the day the moment falls on in the place's time zone. After Isha the next prayer
  is tomorrow's Fajr, and from local midnight the list is the new day's. Tests cover midnight
  in Baghdad and both 2026 daylight-saving changes in London.
- **Saved place out of date.** If the device's clock differs from the saved place's
  (`PrayerPlaceNotice`), the screen says so:
  - a saved location may be from before travelling, so it offers «تحديث موقعي»;
  - a chosen city is shown in its own local time.

  The comparison is by UTC offset on the day, so Riyadh and Kuwait raise nothing. The place
  and the calculation method are never changed by themselves.
- **Denied or failed location.** The message says the saved place stays in use and names it.
- **Unreadable saved settings.** A setting written by another version, or damaged data, is
  listed on the prayer screen, for example «تعذّر قراءة بعض الإعدادات المحفوظة (طريقة الحساب)».
  - It is left as it is, and the default is used for display until the user chooses again.
  - The widget gets no place meanwhile.
  - Tests: `PrayerHardeningTests`.
- **Empty and loading.** With no place the setup appears. While locating, a spinner shows and
  the button is disabled. Where the sun does not rise or set, a message replaces the times.
- No city is assumed: until the user picks one or shares the location, there are no times.

## 7. Qibla: no false precision

`QiblaReadingQuality` grades the heading error iOS reports:

| Quality | Error |
|---|---|
| good | ≤ 10° |
| fair | ≤ 20° |
| poor | > 20° |
| unknown | not reported |

| magneticOnly | any, but from magnetic north (location not shared) |

Only good or fair readings measured from true north can say «أنت متّجه نحو القبلة» (with the
haptic) or give a turn in degrees.

- A poor or unknown reading says «استدر يميناً تقريباً، ثم عاير البوصلة».
- A magnetic-only reading says «استدر يميناً تقريباً». The difference from true north (the
  declination) is unknown here and can be several degrees, and the note says so.
- Without a compass, the bearing from north is shown for use with any compass.
- The screen says when the direction is computed from a chosen city rather than the user's
  exact position, and when the saved location may be from before travelling.

Quick access:

- Home's Qibla row;
- the «القبلة» link in the medium next-prayer widget;
- the Qibla shortcut;
- `azkarapp://qibla`.

## 8. Widgets (`AzkarWidgets/`, extension `AzkarWidgetsExtension`)

### Next prayer

| Family | Shows |
|---|---|
| Home small | Next prayer, its time, a countdown, the place |
| Home medium | The same plus the day's six times (next in bold) and a «القبلة» link |
| Lock Screen inline | «العصر 3:12 م» |
| Lock Screen circular | Name and time |
| Lock Screen rectangular | Name and time, countdown, place |

- **Timeline.** One entry each time what is shown changes: each prayer, sunrise and local
  midnight (`PrayerSchedule.moments`, 16 entries, reloaded at the end). The countdown is
  `Text(timerInterval:countsDown:)`, drawn by the system: nothing updates every second and no
  background work runs.
- **Opens.** A tap opens the prayer times (`azkarapp://prayer`).
- **Data.** The app copies only the place, method, Asr school, manual corrections and the
  24-hour setting into the App Group (`AZKAR_APP_GROUP`, by default
  `group.com.example.IslamicPiPPOC`), and reloads the widgets when they change.
  - The place includes the saved coordinates when the device location was used.
  - No reading position, favorite, count or routine is shared.
  - Settings saved before the update reach the widget at the first launch.
  - While a saved setting cannot be read, no place is copied, so the widget never shows times
    by a method the user did not choose.
- **Without the App Group.** The app and the widget both check that iOS gives a container for
  the group (`containerURL(forSecurityApplicationGroupIdentifier:)`). This fails on unsigned
  builds, and when the team has not registered the group.
  - The app then writes nothing.
  - The widget says «لا تصل الودجة إلى إعدادات التطبيق في هذا التثبيت. افتح التطبيق لعرض
    المواقيت», which is not the same as no place chosen.
  - A tap still opens the prayer times.
  - The entitlement in the source files is not proof the group is registered; only a signed
    install shows it (§12 step 2).
- **Out-of-date place.** When the saved device location is from another time zone, the widget
  adds «قد يكون الموقع قديماً» to the place line.

### Dhikr of the day: content gate

- **Policy.** Only items whose stored status is `REVIEWED` can be chosen automatically.
  `CONTENT_REVIEW_GATE.md` defines that status as "set only after a named qualified reviewer
  approves an item". `DailyDhikr.isEligible` also requires:
  - an adhkar item (not a dua);
  - no Quranic text, which stays in the readers with the Quran font;
  - at most 160 characters, so the text is never cut.

  `CONTENT_REVIEW_REQUIRED` and `QURAN_VERBATIM_TANZIL` items are never picked.
- **Today.** No bundled item is `REVIEWED`, so the pool is empty. The widget shows a neutral
  «افتح التطبيق لقراءة الأذكار» that opens Home; it never shows an unreviewed text.
- **Once items are reviewed.** One eligible dhikr a day, the same for everyone, in turn. The
  widget shows the text, its collection, its source as stored, and the repeat count when above
  one. A tap opens that exact item without counting it.
- **Nothing is hidden or changed.** No text, id, hash, repeat count or status is changed; the
  readers show every item as before. The gate only governs what is chosen without the user
  asking. No other automatic selection was added: the routine, shortcuts and resume open what
  the user chose or last read.
- **Tests.** `DailyDhikrTests` use a library with every review state: only `REVIEWED` adhkar
  are chosen, nothing is chosen when none is reviewed, and every bundled non-`REVIEWED` item
  is ineligible.
- **This is not review.** A code gate is not a substitute for scholarly review or for rights
  clearance; both remain release gates.

## 9. Live Activity: evaluated, not implemented

A next-prayer Live Activity was considered and not built:

- **The Lock Screen widget already covers it.** It shows the next prayer and a system-drawn
  countdown, all day, with no start or stop.
- **Its lifetime is too short.** A Live Activity stays active for at most 8 hours (then up to
  4 more on the Lock Screen). Following the day would need it restarted or updated.
  - Updates without the app open need push notifications, which means a server, against the
    app's offline design.
  - Or they need a new background mode, which this work must not add.
- **Simulated updates are ruled out.** A per-second simulation is excluded, and
  `Text(timerInterval:)` already gives the countdown without one.

What would justify it later is a manual "count down to this prayer" started by the user. It
would need `NSSupportsLiveActivities`, an explicit start button, `Text(timerInterval:)`, and an
end at the prayer time. It needs no push or background mode and can be added in the existing
extension if wanted.

## 10. Privacy, offline and security

- **Permissions.** No new permission or usage string. The location is still read once, when
  asked, while in use. The Qibla reads the heading only while its screen is shown.
- **Shared data.** The App Group holds only the prayer place and settings. Reading positions,
  favorites, counts and the routine stay in the app's own storage.
- **Network.** None: widgets, shortcuts and the dhikr of the day are computed from bundled
  data.
- **Privacy manifests.** The app's declares UserDefaults with reasons CA92.1 and 1C8F.1 (App
  Group). The extension has its own, with 1C8F.1.
- **Links.** Parsed strictly (section 2); a link can only open a screen.
- **CI.** The Release check now also requires:
  - the extension;
  - its WidgetKit extension point;
  - no permission strings or background modes in it;
  - its privacy manifest;
  - the URL scheme.

  The existing checks are unchanged: one usage string, `UIBackgroundModes` exactly `[audio]`,
  no audio files, no test code.

## 11. Tests (Swift package, run in CI)

| File | Covers |
|---|---|
| `ContentKitTests/CompanionTests.swift` | Link round trips and refusals, the resume rule and its ties, the routine (default off, toggles, reorder, normalising, storage, bad data, unknown version) |
| `AdhkarReadingTests/DailyDhikrTests.swift` | Only `REVIEWED` adhkar are chosen (a library with every review state), nothing chosen when none is reviewed, the bundled content gated and unchanged, same dhikr all day and a new one the next day, day numbers across leap years, listing all saved positions; `OpeningFromALinkTests`: opening at an item or a collection counts nothing, saves nothing and completes nothing |
| `PrayerTimesTests/PrayerTimelineTests.swift` | Widget moments in order with the right next and current prayer, local midnight, DST days in London, the polar case, place notices, the Siri sentence, compass quality (magnetic north included), the App Group copy; `PrayerHardeningTests`: every next-prayer widget state (no shared settings, no place, no times, moments), the out-of-date location notice, unreadable settings reported and left unchanged, no place shared while a setting is unreadable |

The SwiftUI views, the App Intents and the widget views are compiled by CI. They are not unit
tested: their logic is in the package code above.

## 12. Physical device test plan

Mark each step PASS, FAIL, BLOCKED or NOT_TESTED. Only a result seen on a device changes it;
automated tests and CI are not device tests. Record the iPhone model, iOS version, build and
date. No device or signing was available to this work, so every step is NOT_TESTED.

| # | Step | Needs | Status |
|---|---|---|---|
| 1 | Install a build signed by the owner's team (Release configuration) | Signing | NOT_TESTED |
| 2 | Check signing on both targets: in Xcode › Signing & Capabilities, the app and AzkarWidgetsExtension each show App Groups with the same group and a valid profile; on the device the next-prayer widget shows times after a place is chosen (not «لا تصل الودجة…») | App Group | BLOCKED until the group is registered |
| 3 | Add each widget: next prayer small and medium, Lock Screen inline, circular, rectangular; dhikr of the day medium and large | Signed install | NOT_TESTED |
| 4 | Next prayer: times equal the app's, corrections included; the countdown runs; it moves on at a prayer time and at midnight without opening the app; a city or method change in the app shows up | App Group | NOT_TESTED |
| 5 | Dhikr of the day: shows the neutral «افتح التطبيق لقراءة الأذكار» (no item is REVIEWED); the tap opens Home. Once items are reviewed, the text is whole and the tap opens that item, uncounted | Signed install | NOT_TESTED |
| 6 | Qibla outdoors away from metal (good accuracy, location shared): degrees and «أنت متّجه نحو القبلة»; near metal or uncalibrated: no degrees, calibration asked; location denied: «تقريباً» only, magnetic note | Device sensors | NOT_TESTED |
| 7 | Deny location, then allow it again in Settings: the saved place stays and is named; «تحديث موقعي» works after allowing | Device | NOT_TESTED |
| 8 | Saved and chosen location: choose a city, then the device location; change the device time zone: the notice and «تحديث موقعي»; the city is never changed by itself | Device | NOT_TESTED |
| 9 | Every shortcut (section 3) from the Shortcuts app, Siri in Arabic and English, and the links in section 2 from Notes or Safari, with the app closed and open | Signed install | NOT_TESTED |
| 10 | Resume: read in the Quran, a Hisn chapter and a dua; kill the app; «أكمل من حيث توقفت» opens the last one with its count | Device | NOT_TESTED |
| 11 | PiP in landscape (default) and portrait (experimental setting): `UNIFIED_PIP.md` §13 rows 1–17 | Device | NOT_TESTED |
| 12 | Background, lock, reopen; music and a phone call during PiP | Device | NOT_TESTED |
| 13 | RTL, VoiceOver (new Home rows, routine settings, prayer notices, widgets), the largest Dynamic Type size, dark mode | Device | NOT_TESTED |
| 14 | Stale or unavailable data: an unsigned install (widget says it cannot reach the settings), a polar place (no times message), airplane mode (everything works) | Device | NOT_TESTED |
| 15 | No unexpected counts or positions: after steps 3–10, counts and «متابعة» places are only what was read by hand | Device | NOT_TESTED |

## 13. Owner gates and risks

### Registering the App Group (owner, Apple Developer account)

Nothing here can be done from the repository, and no credential belongs in it.

1. In Certificates, Identifiers & Profiles › Identifiers, add an **App Groups** identifier,
   for example `group.<your bundle ID>`.
2. Open the app's App ID (your production bundle ID) and enable **App Groups**. Under
   Configure, tick the group, then save.
3. Create or open the widget's App ID, `<your bundle ID>.Widgets`, enable **App Groups** and
   tick the same group.
4. Set `AZKAR_APP_GROUP` in the project (both configurations, project level) to that group, and
   replace `com.example.IslamicPiPPOC` with your bundle ID in both targets. Keep these values
   out of commits if they are private.
5. With automatic signing, Xcode regenerates the profiles. With manual signing, regenerate
   both profiles (app and extension) so they include the group.
6. Build, install and run step 2 of §12. CI checks that both targets name the same group
   through `AZKAR_APP_GROUP`; it cannot check registration.

### Gates and risks

- **App Group.** It must be registered for the production Bundle ID, on both targets.
  - The CI IPA renames the bundle to `com.azkar.pippoc`; the group then reads
    `group.com.azkar.pippoc`.
  - Unsigned IPAs carry no entitlements, so their next-prayer widget cannot see the app's
    settings.
- **Signing.** The widget extension needs its own provisioning profile under the same team
  (`<bundle>.Widgets`).
- **Siri phrases.** They are untested on a device. Arabic Siri support depends on the device's
  Siri language.
- **Content.** The dhikr widget shows `CONTENT_REVIEW_REQUIRED` items, as the app does. The
  review gate is unchanged.
- **Widget reloads.** iOS budgets them. The timeline needs no reload during the day; a change
  in the app reloads it once.
