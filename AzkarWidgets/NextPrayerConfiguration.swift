import AppIntents
import CoreLocation
import WidgetKit
import PrayerTimes

/// The next-prayer widget's own settings («تعديل الودجة»). Left empty, the widget follows the
/// app. A city chosen here lets the widget work where it cannot read the app's settings, as in
/// a build signed without the App Group. Nothing here changes the app's settings.
struct NextPrayerConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "الصلاة القادمة"
    static var description = IntentDescription("اترك الحقول فارغة لتتبع الودجة التطبيق، أو اختر مدينة وطريقة حساب لهذه الودجة.")

    @Parameter(title: "المدينة")
    var city: WidgetCity?

    @Parameter(title: "طريقة الحساب")
    var method: WidgetCalculationMethod?

    @Parameter(title: "صلاة العصر")
    var asr: WidgetAsrSchool?

    var usesCurrentLocation: Bool { city?.id == WidgetCity.currentLocationID }

    /// The choice, with `place` set to the given location when «موقعي الحالي» is chosen.
    func choice(currentLocation: CLLocation? = nil) -> NextPrayerWidgetChoice {
        let place: PrayerPlace?
        if usesCurrentLocation {
            place = currentLocation.map {
                PrayerPlace(name: WidgetCity.currentLocationID,
                            coordinates: Coordinates(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude),
                            timeZoneID: TimeZone.current.identifier, isCurrentLocation: true)
            }
        } else {
            place = city?.place
        }
        return NextPrayerWidgetChoice(place: place, method: method?.method, asr: asr?.school)
    }
}

/// «موقعي الحالي», or one of the app's bundled cities (`PrayerCities`), identified by its name.
struct WidgetCity: AppEntity {
    static let currentLocationID = "موقعي الحالي"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "المدينة"
    static var defaultQuery = WidgetCityQuery()

    let id: String

    var place: PrayerPlace? { PrayerCities.all.first { $0.name == id } }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct WidgetCityQuery: EntityQuery {
    func entities(for identifiers: [WidgetCity.ID]) async throws -> [WidgetCity] {
        identifiers.filter { id in id == WidgetCity.currentLocationID || PrayerCities.all.contains { $0.name == id } }
            .map(WidgetCity.init(id:))
    }

    func suggestedEntities() async throws -> [WidgetCity] {
        [WidgetCity(id: WidgetCity.currentLocationID)] + PrayerCities.all.map { WidgetCity(id: $0.name) }
    }
}

enum WidgetCalculationMethod: String, AppEnum {
    case muslimWorldLeague, ummAlQura, egyptian, karachi, northAmerica, tehran, jafari

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "طريقة الحساب"
    static var caseDisplayRepresentations: [WidgetCalculationMethod: DisplayRepresentation] = [
        .muslimWorldLeague: "رابطة العالم الإسلامي",
        .ummAlQura: "أم القرى (مكة المكرمة)",
        .egyptian: "الهيئة المصرية العامة للمساحة",
        .karachi: "جامعة العلوم الإسلامية، كراتشي",
        .northAmerica: "الجمعية الإسلامية لأمريكا الشمالية",
        .tehran: "معهد الجيوفيزياء، جامعة طهران",
        .jafari: "الشيعة الإثنا عشرية (مؤسسة ليفا، قم)",
    ]

    var method: CalculationMethod? { CalculationMethod(rawValue: rawValue) }
}

enum WidgetAsrSchool: String, AppEnum {
    case standard, hanafi

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "صلاة العصر"
    static var caseDisplayRepresentations: [WidgetAsrSchool: DisplayRepresentation] = [
        .standard: "الجمهور (الشافعي والمالكي والحنبلي)",
        .hanafi: "الحنفي",
    ]

    var school: AsrSchool? { AsrSchool(rawValue: rawValue) }
}

/// The device's location for «موقعي الحالي». It uses the app's "when in use" permission, which
/// iOS extends to widgets (NSWidgetWantsLocation): the user allows it in Settings › أذكار ›
/// الموقع («أثناء استخدام التطبيق أو الودجات»). Read once per timeline, kilometre accuracy.
enum WidgetLocation {
    enum Reading {
        case location(CLLocation)
        case notAllowed
        case unavailable
    }

    static func read() async -> Reading {
        let finder = await MainActor.run { OneShotLocation() }
        return await finder.read()
    }
}

private final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<WidgetLocation.Reading, Never>?

    func read() async -> WidgetLocation.Reading {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard self.manager.isAuthorizedForWidgetUpdates else {
                    return continuation.resume(returning: .notAllowed)
                }
                // A recent fix is enough for prayer times; otherwise ask for one, briefly.
                if let recent = self.manager.location, recent.timestamp.timeIntervalSinceNow > -30 * 60 {
                    return continuation.resume(returning: .location(recent))
                }
                self.continuation = continuation
                self.manager.delegate = self
                self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
                self.manager.requestLocation()
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    self.finish(self.manager.location.map { .location($0) } ?? .unavailable)
                }
            }
        }
    }

    private func finish(_ reading: WidgetLocation.Reading) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: reading)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async { self.finish(locations.last.map { .location($0) } ?? .unavailable) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.finish(self.manager.location.map { .location($0) } ?? .unavailable) }
    }
}
