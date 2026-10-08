import XCTest
@testable import ContentKit

@MainActor
final class FakeReminderScheduler: ReminderScheduling {
    var status: ReminderAuthorization = .notDetermined
    var grant = true
    var permissionRequests = 0
    var scheduled: [String: ReminderRequest] = [:]
    var failAdd = false

    func authorization() async -> ReminderAuthorization { status }

    func requestAuthorization() async -> Bool {
        permissionRequests += 1
        status = grant ? .allowed : .denied
        return grant
    }

    func removeRequests(identifiers: [String]) async {
        for id in identifiers { scheduled[id] = nil }
    }

    func add(_ request: ReminderRequest) async throws {
        if failAdd { throw CocoaError(.featureUnsupported) }
        scheduled[request.identifier] = request
    }
}

@MainActor
final class ReminderTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "ReminderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaultsAreOffWithMorningAndEveningTimes() {
        let settings = ReminderSettings.defaults
        XCTAssertEqual(settings.reminders.map(\.kind), [.morning, .evening])
        XCTAssertFalse(settings.anyEnabled)
        XCTAssertEqual(settings[.morning].hour, 6)
        XCTAssertEqual(settings[.evening].hour, 17)
        XCTAssertTrue(ReminderPlanner.requests(for: settings).isEmpty)
    }

    func testArabicTextAndTargets() {
        var settings = ReminderSettings.defaults
        settings[.morning].isEnabled = true
        settings[.evening].isEnabled = true
        let requests = ReminderPlanner.requests(for: settings)
        XCTAssertEqual(requests.map(\.identifier), ["azkar.reminder.morning", "azkar.reminder.evening"])
        XCTAssertEqual(requests.map(\.title), ["أذكار الصباح", "أذكار المساء"])
        XCTAssertEqual(requests.map(\.body), ["حان وقت أذكار الصباح", "حان وقت أذكار المساء"])
        XCTAssertEqual(requests.map(\.target), [.dhikrGroup("morning"), .dhikrGroup("evening")])
    }

    func testTimesAreClamped() {
        let reminder = Reminder(kind: .morning, isEnabled: true, hour: 25, minute: -3)
        XCTAssertEqual(reminder.hour, 23)
        XCTAssertEqual(reminder.minute, 0)
    }

    func testStoreRoundTripAndBadData() {
        let defaults = defaults()
        let store = UserDefaultsReminderStore(defaults: defaults)
        XCTAssertEqual(store.load(), .defaults)
        var settings = ReminderSettings.defaults
        settings[.evening] = Reminder(kind: .evening, isEnabled: true, hour: 18, minute: 30)
        store.save(settings)
        XCTAssertEqual(UserDefaultsReminderStore(defaults: defaults).load(), settings)
        defaults.set(Data("{".utf8), forKey: UserDefaultsReminderStore.defaultKey)
        XCTAssertEqual(store.load(), .defaults)
        defaults.set(Data(#"{"version":9,"reminders":[]}"#.utf8), forKey: UserDefaultsReminderStore.defaultKey)
        XCTAssertEqual(store.load(), .defaults)
    }

    func testEnablingAsksPermissionOnceAndSchedules() async {
        let scheduler = FakeReminderScheduler()
        let controller = ReminderController(store: UserDefaultsReminderStore(defaults: defaults()), scheduler: scheduler)
        await controller.apply()
        XCTAssertEqual(scheduler.permissionRequests, 0, "never asked at launch")
        await controller.setEnabled(true, for: .morning)
        XCTAssertEqual(scheduler.permissionRequests, 1)
        XCTAssertEqual(controller.authorization, .allowed)
        XCTAssertEqual(Array(scheduler.scheduled.keys), ["azkar.reminder.morning"])
        await controller.setTime(hour: 7, minute: 15, for: .morning)
        XCTAssertEqual(scheduler.scheduled["azkar.reminder.morning"]?.hour, 7)
        XCTAssertEqual(scheduler.scheduled["azkar.reminder.morning"]?.minute, 15)
        XCTAssertEqual(scheduler.scheduled.count, 1, "rescheduling replaces")
        await controller.setEnabled(true, for: .evening)
        XCTAssertEqual(scheduler.permissionRequests, 1)
        XCTAssertEqual(scheduler.scheduled.count, 2)
        await controller.setEnabled(false, for: .morning)
        XCTAssertEqual(Array(scheduler.scheduled.keys), ["azkar.reminder.evening"])
    }

    func testDeniedPermissionSchedulesNothing() async {
        let scheduler = FakeReminderScheduler()
        scheduler.grant = false
        let controller = ReminderController(store: UserDefaultsReminderStore(defaults: defaults()), scheduler: scheduler)
        await controller.setEnabled(true, for: .evening)
        XCTAssertEqual(controller.authorization, .denied)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertTrue(controller.settings[.evening].isEnabled, "the choice is kept for when permission is given")
        scheduler.status = .allowed
        await controller.apply()
        XCTAssertEqual(Array(scheduler.scheduled.keys), ["azkar.reminder.evening"])
    }

    func testSchedulingFailureIsReported() async {
        let scheduler = FakeReminderScheduler()
        scheduler.status = .allowed
        scheduler.failAdd = true
        let controller = ReminderController(store: UserDefaultsReminderStore(defaults: defaults()), scheduler: scheduler)
        await controller.setEnabled(true, for: .morning)
        XCTAssertEqual(controller.lastError, "تعذّر جدولة التذكير")
        scheduler.failAdd = false
        await controller.apply()
        XCTAssertNil(controller.lastError)
    }

    func testSettingsPersistAcrossControllers() async {
        let defaults = defaults()
        let scheduler = FakeReminderScheduler()
        scheduler.status = .allowed
        let first = ReminderController(store: UserDefaultsReminderStore(defaults: defaults), scheduler: scheduler)
        await first.setEnabled(true, for: .morning)
        let second = ReminderController(store: UserDefaultsReminderStore(defaults: defaults), scheduler: scheduler)
        XCTAssertTrue(second.settings[.morning].isEnabled)
    }
}
