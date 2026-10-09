import XCTest
@testable import ContentKit

final class AppLinkTests: XCTestCase {
    func testEveryLinkRoundTrips() {
        let links: [AppLink] = [.home, .prayerTimes, .qibla, .resume, .quran,
                                .content(.dhikrGroup("morning")), .content(.hisnItem("hisn-017-03")),
                                .content(.quranVerse(surah: 2, ayah: 255)), .content(.duaCategory("quranic"))]
        for link in links {
            XCTAssertEqual(link.url.scheme, "azkarapp")
            XCTAssertEqual(AppLink(url: link.url), link, link.url.absoluteString)
        }
        XCTAssertEqual(AppLink.content(.dhikrGroup("morning")).url.absoluteString,
                       "azkarapp://open?ref=adhkar:group:morning")
        XCTAssertEqual(AppLink.qibla.url.absoluteString, "azkarapp://qibla")
    }

    func testParsesWhatWidgetsAndShortcutsSend() {
        XCTAssertEqual(AppLink(url: URL(string: "azkarapp://prayer")!), .prayerTimes)
        XCTAssertEqual(AppLink(url: URL(string: "AZKARAPP://Qibla/")!), .qibla, "scheme and host ignore case")
        XCTAssertEqual(AppLink(url: URL(string: "azkarapp://open?ref=hisn:hisn-001-01")!), .content(.hisnItem("hisn-001-01")))
        XCTAssertEqual(AppLink(url: URL(string: "azkarapp://open?ref=quran%3A2%3A255")!), .content(.quranVerse(surah: 2, ayah: 255)))
    }

    func testRefusesAnythingElse() {
        let refused = ["https://prayer", "azkarapp://", "azkarapp://settings", "azkarapp://prayer/today",
                       "azkarapp://qibla?x=1", "azkarapp://open", "azkarapp://open?ref=", "azkarapp://open?ref=unknown:1",
                       "azkarapp://open?ref=adhkar:", "azkarapp://open?ref=hisn:a&ref=hisn:b", "azkarapp://open?id=hisn:a",
                       "otherapp://prayer", "azkarapp://open?ref=hisn:" + String(repeating: "a", count: 400)]
        for raw in refused {
            XCTAssertNil(URL(string: raw).flatMap(AppLink.init(url:)), raw)
        }
    }
}

final class ResumePointTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_791_537_600)

    func testTheLastSavedPlaceWins() {
        let quran = ResumePoint(section: .quran, target: .quranVerse(surah: 18, ayah: 10), container: nil, savedAt: base)
        let hisn = ResumePoint(section: .hisn, target: .hisnItem("hisn-027-04"), container: .hisnSection("hisn-ch-027"),
                               savedAt: base.addingTimeInterval(60))
        let dua = ResumePoint(section: .dua, target: .dua("d-3"), container: .duaCategory("quranic"),
                              savedAt: base.addingTimeInterval(-60))
        XCTAssertEqual(ResumePoint.mostRecent([quran, hisn, dua]), hisn)
        XCTAssertEqual(ResumePoint.mostRecent([dua, quran]), quran)
        XCTAssertNil(ResumePoint.mostRecent([]))
    }

    func testTiesAreBrokenTheSameWayEveryTime() {
        let adhkar = ResumePoint(section: .adhkar, target: .dhikr("m-2"), container: .dhikrGroup("morning"), savedAt: base)
        let hisn = ResumePoint(section: .hisn, target: .hisnItem("hisn-001-01"), container: nil, savedAt: base)
        let adhkarB = ResumePoint(section: .adhkar, target: .dhikr("e-1"), container: .dhikrGroup("evening"), savedAt: base)
        for order in [[adhkar, hisn, adhkarB], [adhkarB, adhkar, hisn], [hisn, adhkarB, adhkar]] {
            XCTAssertEqual(ResumePoint.mostRecent(order), hisn, "the earlier section wins a tie")
        }
        XCTAssertEqual(ResumePoint.mostRecent([adhkar, adhkarB]), adhkarB, "then the smaller reference")
    }
}

final class DailyRoutineTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "DailyRoutineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testOffUntilTurnedOnAndShowsOnlyChosenSteps() {
        var routine = DailyRoutine.standard
        XCTAssertFalse(routine.isEnabled)
        XCTAssertEqual(routine.activeSteps, [], "nothing shows while off")
        routine.isEnabled = true
        XCTAssertEqual(routine.activeSteps, DailyRoutine.Step.allCases)
        routine.set(.quran, on: false)
        XCTAssertEqual(routine.activeSteps, [.morningAdhkar, .afterPrayerAdhkar, .eveningAdhkar, .sleepAdhkar])
    }

    func testReorderLikeAList() {
        var routine = DailyRoutine.standard
        routine.move(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        XCTAssertEqual(routine.entries.map(\.step), [.sleepAdhkar, .morningAdhkar, .quran, .afterPrayerAdhkar, .eveningAdhkar])
        routine.move(fromOffsets: IndexSet(integer: 0), toOffset: 5)
        XCTAssertEqual(routine.entries.map(\.step), DailyRoutine.Step.allCases)
        routine.move(fromOffsets: IndexSet([0, 1]), toOffset: 3)
        XCTAssertEqual(routine.entries.map(\.step), [.afterPrayerAdhkar, .morningAdhkar, .quran, .eveningAdhkar, .sleepAdhkar])
        routine.move(fromOffsets: IndexSet(integer: 9), toOffset: 0)
        XCTAssertEqual(routine.entries.count, 5, "an offset out of range changes nothing")
    }

    func testEveryStepOnceWhateverWasStored() {
        let routine = DailyRoutine(isEnabled: true, entries: [.init(step: .eveningAdhkar, isOn: true),
                                                              .init(step: .eveningAdhkar, isOn: false)])
        XCTAssertEqual(routine.entries.map(\.step), [.eveningAdhkar, .morningAdhkar, .quran, .afterPrayerAdhkar, .sleepAdhkar])
        XCTAssertEqual(routine.activeSteps, [.eveningAdhkar], "added steps start off")
    }

    func testStoreKeepsTheRoutineAndDropsBadData() throws {
        let defaults = defaults()
        let store = DailyRoutineStore(defaults: defaults)
        XCTAssertEqual(store.routine, .standard)
        var routine = DailyRoutine.standard
        routine.isEnabled = true
        routine.set(.sleepAdhkar, on: false)
        routine.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        store.routine = routine
        XCTAssertEqual(DailyRoutineStore(defaults: defaults).routine, routine)

        // A step this version does not know is dropped; the rest is kept.
        let later = #"{"entries":[{"isOn":true,"step":"tahajjud"},{"isOn":true,"step":"quran"}],"isEnabled":true,"version":1}"#
        defaults.set(Data(later.utf8), forKey: DailyRoutineStore.defaultKey)
        XCTAssertEqual(store.routine.activeSteps, [.quran])

        defaults.set(Data("{".utf8), forKey: DailyRoutineStore.defaultKey)
        XCTAssertEqual(store.routine, .standard)
        XCTAssertNil(defaults.data(forKey: DailyRoutineStore.defaultKey), "unreadable data is removed")
        defaults.set(Data(#"{"entries":[],"isEnabled":true,"version":2}"#.utf8), forKey: DailyRoutineStore.defaultKey)
        XCTAssertEqual(store.routine, .standard, "an unknown version is not guessed at")
    }

    func testStepsOpenTheirCollections() {
        XCTAssertEqual(DailyRoutine.Step.morningAdhkar.collection, .dhikrGroup("morning"))
        XCTAssertEqual(DailyRoutine.Step.sleepAdhkar.collection, .dhikrGroup("sleep"))
        XCTAssertNil(DailyRoutine.Step.quran.collection)
    }
}
