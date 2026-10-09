import AppIntents
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

    var choice: NextPrayerWidgetChoice {
        NextPrayerWidgetChoice(place: city?.place, method: method?.method, asr: asr?.school)
    }
}

/// One of the app's bundled cities (`PrayerCities`), identified by its name.
struct WidgetCity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "المدينة"
    static var defaultQuery = WidgetCityQuery()

    let id: String

    var place: PrayerPlace? { PrayerCities.all.first { $0.name == id } }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct WidgetCityQuery: EntityQuery {
    func entities(for identifiers: [WidgetCity.ID]) async throws -> [WidgetCity] {
        identifiers.filter { id in PrayerCities.all.contains { $0.name == id } }.map(WidgetCity.init(id:))
    }

    func suggestedEntities() async throws -> [WidgetCity] {
        PrayerCities.all.map { WidgetCity(id: $0.name) }
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
