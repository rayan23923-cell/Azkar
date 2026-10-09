import Foundation

/// A place the times are for: the device's location or a city picked from the list.
public struct PrayerPlace: Equatable, Codable, Sendable {
    public let name: String
    public let coordinates: Coordinates
    /// The place's time zone identifier; nil: the device's.
    public let timeZoneID: String?
    /// From the device's location (not a picked city).
    public let isCurrentLocation: Bool

    public init(name: String, coordinates: Coordinates, timeZoneID: String? = nil, isCurrentLocation: Bool) {
        self.name = name
        self.coordinates = coordinates
        self.timeZoneID = timeZoneID
        self.isCurrentLocation = isCurrentLocation
    }

    public var timeZone: TimeZone { timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current }
}

/// The saved place and calculation settings, in UserDefaults on the device only.
public final class PrayerSettingsStore {
    public static let placeKey = "prayer.place"
    public static let methodKey = "prayer.method"
    public static let asrKey = "prayer.asr"
    public static let clockKey = "prayer.24h"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var place: PrayerPlace? {
        get { defaults.data(forKey: Self.placeKey).flatMap { try? JSONDecoder().decode(PrayerPlace.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.placeKey)
            } else {
                defaults.removeObject(forKey: Self.placeKey)
            }
        }
    }

    public var parameters: PrayerParameters {
        get {
            PrayerParameters(
                method: defaults.string(forKey: Self.methodKey).flatMap(CalculationMethod.init(rawValue:))
                    ?? .muslimWorldLeague,
                asr: defaults.string(forKey: Self.asrKey).flatMap(AsrSchool.init(rawValue:)) ?? .standard)
        }
        set {
            defaults.set(newValue.method.rawValue, forKey: Self.methodKey)
            defaults.set(newValue.asr.rawValue, forKey: Self.asrKey)
        }
    }

    /// Times as 13:05 rather than 1:05 م.
    public var twentyFourHour: Bool {
        get { defaults.bool(forKey: Self.clockKey) }
        set { defaults.set(newValue, forKey: Self.clockKey) }
    }

    /// The schedule for the saved place; nil until a place is set.
    public var schedule: PrayerSchedule? {
        guard let place else { return nil }
        return PrayerSchedule(coordinates: place.coordinates, timeZone: place.timeZone, parameters: parameters)
    }
}

/// Cities to pick from when the location is not shared.
public enum PrayerCities {
    public static let all: [PrayerPlace] = [
        city("مكة المكرمة", 21.4225, 39.8262, "Asia/Riyadh"),
        city("المدينة المنورة", 24.4672, 39.6112, "Asia/Riyadh"),
        city("الرياض", 24.7136, 46.6753, "Asia/Riyadh"),
        city("جدة", 21.5433, 39.1728, "Asia/Riyadh"),
        city("بغداد", 33.3152, 44.3661, "Asia/Baghdad"),
        city("البصرة", 30.5085, 47.7804, "Asia/Baghdad"),
        city("الموصل", 36.3350, 43.1189, "Asia/Baghdad"),
        city("أربيل", 36.1911, 44.0092, "Asia/Baghdad"),
        city("النجف", 32.0259, 44.3462, "Asia/Baghdad"),
        city("كربلاء", 32.6160, 44.0249, "Asia/Baghdad"),
        city("الكويت", 29.3759, 47.9774, "Asia/Kuwait"),
        city("الدوحة", 25.2854, 51.5310, "Asia/Qatar"),
        city("المنامة", 26.2285, 50.5860, "Asia/Bahrain"),
        city("دبي", 25.2048, 55.2708, "Asia/Dubai"),
        city("أبوظبي", 24.4539, 54.3773, "Asia/Dubai"),
        city("مسقط", 23.5880, 58.3829, "Asia/Muscat"),
        city("عمّان", 31.9454, 35.9284, "Asia/Amman"),
        city("القدس", 31.7683, 35.2137, "Asia/Jerusalem"),
        city("دمشق", 33.5138, 36.2765, "Asia/Damascus"),
        city("بيروت", 33.8938, 35.5018, "Asia/Beirut"),
        city("القاهرة", 30.0444, 31.2357, "Africa/Cairo"),
        city("الخرطوم", 15.5007, 32.5599, "Africa/Khartoum"),
        city("طرابلس", 32.8872, 13.1913, "Africa/Tripoli"),
        city("تونس", 36.8065, 10.1815, "Africa/Tunis"),
        city("الجزائر", 36.7538, 3.0588, "Africa/Algiers"),
        city("الرباط", 34.0209, -6.8416, "Africa/Casablanca"),
        city("صنعاء", 15.3694, 44.1910, "Asia/Aden"),
        city("إسطنبول", 41.0082, 28.9784, "Europe/Istanbul"),
        city("لندن", 51.5074, -0.1278, "Europe/London"),
    ]

    private static func city(_ name: String, _ lat: Double, _ lng: Double, _ zone: String) -> PrayerPlace {
        PrayerPlace(name: name, coordinates: Coordinates(latitude: lat, longitude: lng), timeZoneID: zone,
                    isCurrentLocation: false)
    }
}
