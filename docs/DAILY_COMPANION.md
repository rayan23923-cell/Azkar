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
but no longer exists is resolved by the same code as Favorites (it falls back to the
collection, or does nothing). **Opening a link never counts a repetition or marks anything
done.**

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

Only good or fair readings can say «أنت متّجه نحو القبلة» (with the haptic) or give a turn in
degrees. Otherwise the guidance is «استدر يميناً تقريباً، ثم عاير البوصلة» and the note asks to
calibrate. Magnetic north (location not shared) is still said, as before.

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
  `group.com.example.IslamicPiPPOC`), and reloads the widgets when they change. Settings saved
  before the update reach the widget at the first launch. Without the group the widget says
  «افتح التطبيق واختر مدينتك أو موقعك». That is the case for unsigned builds, or for a team that
  has not registered the group.

### Dhikr of the day

- **Choice.** One bundled dhikr a day, the same for everyone, taken in turn from the adhkar of
  at most 160 characters (26 today), so the text is always shown whole.
- **Quranic text.** It is left out; it is shown only in the readers, with the bundled Quran
  font.
- **Shows.** The text, its collection, its source as stored, and the repeat count when above
  one.
- **Opens.** A tap opens that exact item (`azkarapp://open?ref=…`) without counting it.
- **Data.** It reads the bundled content only and needs no shared data.
- **Content gate.** The content's review state is unchanged and remains a release gate
  (`CONTENT_REVIEW_GATE.md`).

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
| `AdhkarReadingTests/DailyDhikrTests.swift` | Same dhikr all day, a new one the next day, whole text only, no Quranic text, a full cycle, day numbers across leap years, listing all saved positions |
| `PrayerTimesTests/PrayerTimelineTests.swift` | Widget moments in order with the right next and current prayer, local midnight, DST days in London, the polar case, place notices, the Siri sentence, compass quality, the App Group copy |

The SwiftUI views, the App Intents and the widget views are compiled by CI. They are not unit
tested: their logic is in the package code above.

## 12. Physical device checklist

Each row is PASS, FAIL, BLOCKED or NOT_TESTED. Only a result seen on a device changes a row.
Run it on a build signed with a team that has registered the App Group (Signing &
Capabilities › App Groups on both targets, the same group). Without it, rows 6 to 9 are
BLOCKED and the widget asks to open the app.

| # | Check | Status |
|---|---|---|
| 1 | «أكمل من حيث توقفت» on Home opens the place read last (try Quran, then a Hisn item, then a dua) with its count | NOT_TESTED |
| 2 | «الورد اليومي»: off by default; on, reorder and turn steps off; Home marks only today's done steps | NOT_TESTED |
| 3 | Shortcuts app: each App Shortcut runs; «الصلاة القادمة» answers without opening the app | NOT_TESTED |
| 4 | Siri in Arabic and in English with the phrases in section 3 | NOT_TESTED |
| 5 | Morning adhkar shortcut opens the saved item and the count is unchanged | NOT_TESTED |
| 6 | Next-prayer widget, small and medium: times match the app (corrections included), the countdown runs | NOT_TESTED |
| 7 | Lock Screen inline, circular, rectangular: readable, right to left | NOT_TESTED |
| 8 | Change the city or method in the app: the widget follows | NOT_TESTED |
| 9 | Across a prayer time and midnight: the widget moves on without opening the app | NOT_TESTED |
| 10 | Widget tap opens the prayer times; the medium «القبلة» link opens the Qibla | NOT_TESTED |
| 11 | Dhikr widget: whole text, opens the same item, nothing counted | NOT_TESTED |
| 12 | Saved location, then change the device's time zone: the notice and «تحديث موقعي» | NOT_TESTED |
| 13 | Qibla near metal (poor accuracy): no degrees, no «متّجه نحو القبلة» | NOT_TESTED |
| 14 | VoiceOver on the new Home rows, routine settings and widgets | NOT_TESTED |
| 15 | Airplane mode: widgets, shortcuts and resume all work | NOT_TESTED |

## 13. Owner gates and risks

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
