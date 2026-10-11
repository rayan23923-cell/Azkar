import XCTest
@testable import PrayerTimes

/// The city, method and Asr school chosen in the next-prayer widget itself («تعديل الودجة»),
/// for installations where the widget cannot read the app's settings.
final class WidgetChoiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_537_600) // 2026-10-09 12:20 in Baghdad
    private var names: [String] = []

    private func store() throws -> PrayerSettingsStore {
        let name = "WidgetChoice.\(UUID().uuidString)"
        names.append(name)
        return PrayerSettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: name)))
    }

    override func tearDown() {
        names.forEach { UserDefaults().removePersistentDomain(forName: $0) }
        names = []
    }

    private func city(_ name: String) throws -> PrayerPlace {
        try XCTUnwrap(PrayerCities.all.first { $0.name == name })
    }

    private func expected(_ place: PrayerPlace, _ parameters: PrayerParameters) -> [PrayerMoment] {
        PrayerSchedule(coordinates: place.coordinates, timeZone: place.timeZone, parameters: parameters).moments(from: now)
    }

    func testACityWithoutAMethodUsesTheAppsDefaults() throws {
        let mosul = try city("الموصل")
        // As the app shows before its settings are changed; an App Group with no place shared
        // does not supply a method either.
        for app in [nil, try store()] {
            guard case let .moments(moments, place, _, _, _) =
                    NextPrayerWidgetState.resolve(store: app, choice: NextPrayerWidgetChoice(place: mosul),
                                                  deviceTimeZone: .current, now: now) else {
                return XCTFail("times expected")
            }
            XCTAssertEqual(place, "الموصل")
            XCTAssertEqual(moments, expected(mosul, PrayerParameters()))
        }
    }

    func testACityAndMethodChosenInTheWidgetWorkWithoutTheAppGroup() throws {
        let mosul = try city("الموصل")
        let choice = NextPrayerWidgetChoice(place: mosul, method: .egyptian, asr: .hanafi)
        guard case let .moments(moments, place, zone, twentyFourHour, notice) =
                NextPrayerWidgetState.resolve(store: nil, choice: choice, deviceTimeZone: .current, now: now) else {
            return XCTFail("times expected")
        }
        XCTAssertEqual(place, "الموصل")
        XCTAssertEqual(zone.identifier, "Asia/Baghdad")
        XCTAssertFalse(twentyFourHour)
        XCTAssertNil(notice, "a city chosen by hand is not a location that can be out of date")
        XCTAssertEqual(moments, expected(mosul, PrayerParameters(method: .egyptian, asr: .hanafi)))
    }

    func testACityChosenInTheWidgetKeepsTheAppsMethodAndCorrections() throws {
        let app = try store()
        app.place = try city("بغداد")
        app.parameters = PrayerParameters(method: .ummAlQura, asr: .hanafi, adjustments: [.fajr: 3])
        app.twentyFourHour = true
        let basra = try city("البصرة")
        guard case let .moments(moments, place, _, twentyFourHour, _) =
                NextPrayerWidgetState.resolve(store: app, choice: NextPrayerWidgetChoice(place: basra),
                                              deviceTimeZone: .current, now: now) else {
            return XCTFail("times expected")
        }
        XCTAssertEqual(place, "البصرة", "the widget's city wins over the app's")
        XCTAssertTrue(twentyFourHour)
        XCTAssertEqual(moments, expected(basra, app.parameters))
    }

    func testTheWidgetsMethodWinsOverTheAppsAndNothingIsSaved() throws {
        let app = try store()
        app.place = try city("بغداد")
        app.parameters = PrayerParameters(method: .ummAlQura, asr: .standard, adjustments: [.isha: -2])
        let basra = try city("البصرة")
        guard case let .moments(moments, _, _, _, _) =
                NextPrayerWidgetState.resolve(store: app, choice: NextPrayerWidgetChoice(place: basra, method: .karachi),
                                              deviceTimeZone: .current, now: now) else {
            return XCTFail("times expected")
        }
        XCTAssertEqual(moments, expected(basra, PrayerParameters(method: .karachi, asr: .standard, adjustments: [.isha: -2])))
        XCTAssertEqual(app.parameters.method, .ummAlQura, "the widget never changes the app's settings")
        XCTAssertEqual(app.place?.name, "بغداد")
    }

    func testWithoutAChoiceTheWidgetFollowsTheAppAsBefore() throws {
        XCTAssertEqual(NextPrayerWidgetState.resolve(store: nil, choice: NextPrayerWidgetChoice(method: .egyptian),
                                                     deviceTimeZone: .current, now: now),
                       .sharedSettingsUnavailable)
        XCTAssertEqual(NextPrayerWidgetState.resolve(store: try store(), deviceTimeZone: .current, now: now), .noPlace)
    }

    func testEveryCityHasAUniqueNameAndATimeZone() {
        let names = PrayerCities.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "the widget identifies a city by its name")
        for place in PrayerCities.all {
            XCTAssertNotNil(place.timeZoneID.flatMap(TimeZone.init(identifier:)), place.name)
        }
    }
}

/// The App Group a re-signed installation really shares.
final class AppGroupLocatorTests: XCTestCase {
    private func profile(groups: [String]) -> Data {
        let entitlements: [String: Any] = ["com.apple.security.application-groups": groups,
                                           "application-identifier": "ABCDE12345.com.example.app"]
        let plist = try! PropertyListSerialization.data(fromPropertyList: ["Name": "test", "Entitlements": entitlements],
                                                        format: .xml, options: 0)
        // A provisioning profile wraps the property list in binary CMS data.
        return Data([0x30, 0x82, 0x01, 0x00, 0x06, 0x09]) + plist + Data([0xA0, 0x82, 0x00, 0x10])
    }

    func testGroupsAreReadFromTheProfile() {
        XCTAssertEqual(AppGroupLocator.profileGroups(profile(groups: ["group.com.signer.Azkar"])), ["group.com.signer.Azkar"])
        XCTAssertEqual(AppGroupLocator.profileGroups(Data("not a profile".utf8)), [])
    }

    func testTheBuildsGroupComesFirstThenTheProfiles() {
        let data = profile(groups: ["group.com.example.IslamicPiPPOC", "group.renamed", "group.*"])
        XCTAssertEqual(AppGroupLocator.candidates(infoPlistGroup: "group.com.example.IslamicPiPPOC", profile: data),
                       ["group.com.example.IslamicPiPPOC", "group.renamed"])
        XCTAssertEqual(AppGroupLocator.candidates(infoPlistGroup: "$(AZKAR_APP_GROUP)", profile: nil), [])
        XCTAssertEqual(AppGroupLocator.candidates(infoPlistGroup: nil, profile: data),
                       ["group.com.example.IslamicPiPPOC", "group.renamed"])
    }
}
