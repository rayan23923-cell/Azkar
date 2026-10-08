# Phase 3J: Notifications and reminders

## Behaviour

- **Reminders.** Two daily reminders, «أذكار الصباح» and «أذكار المساء». Each can be turned
  on or off and has its own time. Both are off by default, at 06:00 and 17:00.
- **Where.** In «الإعدادات» (the gear on the Hisn screen until Phase 10).
- **Permission.**
  - Asked only when the user turns a reminder on; never at launch.
  - If denied, the screen says so and offers «فتح إعدادات النظام». The user's choice is kept,
    and scheduling resumes once permission is given.
- **Scheduling.**
  - Local notifications only: `UNCalendarNotificationTrigger` repeating daily at the
    wall-clock hour and minute.
  - It follows the device's time zone and daylight saving.
  - Fixed identifiers, so rescheduling replaces and never duplicates.
  - At every launch the scheduled requests are rebuilt from the saved settings.
- **Notification text.** Arabic. The notification carries the content it opens
  (`adhkar:group:morning` / `evening`); opening it is wired in Phase 10.
- **Storage.** `reminders.v1` JSON in UserDefaults; bad data reads as the defaults.
- **Network.** No network, no server, no remote push.

## Code

- **ContentKit:**
  - `ReminderKind`, `Reminder`, `ReminderSettings`, `ReminderPlanner`;
  - `UserDefaultsReminderStore`;
  - the `ReminderScheduling` protocol;
  - `ReminderController`.
- **App:**
  - `SystemReminderScheduler` (`UNUserNotificationCenter`);
  - `SettingsView`;
  - `AppServices`.

## Tests (`ReminderTests`)

- defaults;
- Arabic text and targets;
- time clamping;
- store round trip and bad data;
- permission asked once, only on enable;
- replace-on-reschedule;
- denied permission schedules nothing and keeps the choice;
- failure reported;
- persistence across launches.

Not checked on a device: delivery, the system permission sheet.
