import CoreLocation
import Foundation
import PiPProviders
import PrayerTimes

/// The prayer screens' state: the saved place and settings, the device location when shared,
/// and the PiP provider that shows the times over other apps.
///
/// Times and the Qibla are computed on the device. The location is read once when asked
/// (`requestLocation`, while in use), kept in UserDefaults and never sent anywhere; it is not
/// reverse-geocoded, since that would send it to a server.
@MainActor
final class PrayerModel: NSObject, ObservableObject {
    static let shared = PrayerModel()

    enum LocationState: Equatable {
        case idle
        case locating
        /// Denied or restricted: a city from the list instead.
        case denied
        case failed
    }

    @Published private(set) var place: PrayerPlace?
    @Published var parameters: PrayerParameters {
        didSet { store.parameters = parameters; refreshPiP() }
    }
    @Published var twentyFourHour: Bool {
        didSet { store.twentyFourHour = twentyFourHour; refreshPiP() }
    }
    @Published private(set) var locationState: LocationState = .idle

    private let store: PrayerSettingsStore
    private let manager = CLLocationManager()
    /// Made on first use and kept, so a running window follows place and settings changes.
    private var provider: PrayerPiPProvider?

    init(store: PrayerSettingsStore = PrayerSettingsStore()) {
        self.store = store
        place = store.place
        parameters = store.parameters
        twentyFourHour = store.twentyFourHour
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var schedule: PrayerSchedule? {
        place.map { PrayerSchedule(coordinates: $0.coordinates, timeZone: $0.timeZone, parameters: parameters) }
    }

    func choose(_ city: PrayerPlace) {
        set(city)
    }

    /// Asks for the location (the system prompt the first time), then reads it once.
    func useCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            locationState = .locating
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationState = .locating
            manager.requestLocation()
        default:
            locationState = .denied
        }
    }

    /// The window's provider for the saved place; nil until a place is set.
    func pipProvider() -> PrayerPiPProvider? {
        guard let schedule, let place else { return nil }
        if let provider { return provider }
        let made = PrayerPiPProvider(schedule: schedule, placeName: place.name, twentyFourHour: twentyFourHour)
        provider = made
        return made
    }

    private func set(_ newPlace: PrayerPlace) {
        place = newPlace
        store.place = newPlace
        refreshPiP()
    }

    private func refreshPiP() {
        guard let provider, let schedule, let place else { return }
        provider.update(schedule: schedule, placeName: place.name, twentyFourHour: twentyFourHour)
    }

    private func received(_ location: CLLocation) {
        let coordinates = Coordinates(latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude)
        guard coordinates.isValid else { locationState = .failed; return }
        locationState = .idle
        set(PrayerPlace(name: "موقعي الحالي", coordinates: coordinates, timeZoneID: TimeZone.current.identifier,
                        isCurrentLocation: true))
    }
}

// The manager is made on the main thread, so its delegate is called there.
extension PrayerModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard locationState == .locating || locationState == .denied else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                locationState = .locating
                self.manager.requestLocation()
            case .denied, .restricted:
                locationState = .denied
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated { received(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated { locationState = denied ? .denied : .failed }
    }
}
