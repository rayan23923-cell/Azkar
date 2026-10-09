import AppIntents
import ContentKit
import AdhkarReading
import PrayerTimes

// Shortcuts and Siri. Each intent only opens a place in the app (or, for the next prayer,
// says it): none counts a repetition, marks anything done or changes a setting.

struct OpenPrayerTimesIntent: AppIntent {
    static var title: LocalizedStringResource = "مواقيت الصلاة"
    static var description = IntentDescription("يفتح مواقيت الصلاة لليوم.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.router.handle(.prayerTimes)
        return .result()
    }
}

struct OpenQiblaIntent: AppIntent {
    static var title: LocalizedStringResource = "اتجاه القبلة"
    static var description = IntentDescription("يفتح بوصلة القبلة للمكان المحفوظ.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.router.handle(.qibla)
        return .result()
    }
}

struct ResumeReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "أكمل من حيث توقفت"
    static var description = IntentDescription("يفتح آخر موضع قرأته في القرآن أو حصن المسلم أو الأذكار أو الأدعية.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.router.handle(.resume)
        return .result()
    }
}

struct OpenQuranIntent: AppIntent {
    static var title: LocalizedStringResource = "فتح القرآن الكريم"
    static var description = IntentDescription("يفتح القرآن عند آخر آية قرأتها.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.router.handle(.quran)
        return .result()
    }
}

struct OpenMorningAdhkarIntent: AppIntent {
    static var title: LocalizedStringResource = "أذكار الصباح"
    static var description = IntentDescription("يفتح أذكار الصباح من حيث توقفت، دون أن يعدّ شيئاً.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.router.handle(.content(.dhikrGroup("morning")))
        return .result()
    }
}

struct OpenEveningAdhkarIntent: AppIntent {
    static var title: LocalizedStringResource = "أذكار المساء"
    static var description = IntentDescription("يفتح أذكار المساء من حيث توقفت، دون أن يعدّ شيئاً.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.router.handle(.content(.dhikrGroup("evening")))
        return .result()
    }
}

/// Any adhkar group or dua category, chosen in the Shortcuts app.
struct OpenCollectionIntent: AppIntent {
    static var title: LocalizedStringResource = "فتح أذكار أو أدعية"
    static var description = IntentDescription("يفتح مجموعة أذكار أو أدعية تختارها.")
    static var openAppWhenRun = true

    @Parameter(title: "المجموعة")
    var collection: CollectionEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        if let ref = ContentRef(string: collection.id) { AppServices.shared.router.handle(.content(ref)) }
        return .result()
    }
}

struct CollectionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "أذكار أو أدعية"
    static var defaultQuery = CollectionQuery()

    /// The collection's `ContentRef` string.
    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct CollectionQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [CollectionEntity.ID]) async throws -> [CollectionEntity] {
        try await all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [CollectionEntity] {
        try await all()
    }

    @MainActor
    private func all() async throws -> [CollectionEntity] {
        let library = try await AppServices.shared.content.adhkar().library
        return library.collections.map { CollectionEntity(id: $0.ref.string, title: $0.title) }
    }
}

/// Says the next prayer for the saved place without opening the app. Nothing is asked for:
/// with no place saved it says so.
struct NextPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "الصلاة القادمة"
    static var description = IntentDescription("يخبرك بالصلاة القادمة ووقتها للمكان المحفوظ في التطبيق.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = PrayerSettingsStore().nextPrayerSentence(now: Date())
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct AzkarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextPrayerIntent(),
                    phrases: ["الصلاة القادمة في \(.applicationName)", "Next prayer in \(.applicationName)"],
                    shortTitle: "الصلاة القادمة", systemImageName: "clock")
        AppShortcut(intent: OpenPrayerTimesIntent(),
                    phrases: ["مواقيت الصلاة في \(.applicationName)", "Prayer times in \(.applicationName)"],
                    shortTitle: "مواقيت الصلاة", systemImageName: "calendar")
        AppShortcut(intent: OpenQiblaIntent(),
                    phrases: ["اتجاه القبلة في \(.applicationName)", "Qibla in \(.applicationName)"],
                    shortTitle: "اتجاه القبلة", systemImageName: "location.north.line")
        AppShortcut(intent: ResumeReadingIntent(),
                    phrases: ["أكمل القراءة في \(.applicationName)", "Resume reading in \(.applicationName)"],
                    shortTitle: "أكمل من حيث توقفت", systemImageName: "bookmark")
        AppShortcut(intent: OpenQuranIntent(),
                    phrases: ["افتح القرآن في \(.applicationName)", "Open Quran in \(.applicationName)"],
                    shortTitle: "القرآن الكريم", systemImageName: "book")
        AppShortcut(intent: OpenMorningAdhkarIntent(),
                    phrases: ["أذكار الصباح في \(.applicationName)", "Morning adhkar in \(.applicationName)"],
                    shortTitle: "أذكار الصباح", systemImageName: "sunrise")
        AppShortcut(intent: OpenEveningAdhkarIntent(),
                    phrases: ["أذكار المساء في \(.applicationName)", "Evening adhkar in \(.applicationName)"],
                    shortTitle: "أذكار المساء", systemImageName: "sunset")
    }
}
