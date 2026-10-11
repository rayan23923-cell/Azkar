import CoreLocation
import Foundation
import PiPProviders
import PrayerTimes
import WidgetKit

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
        didSet { store.parameters = parameters; refreshPiP(); publishToWidgets(); rescheduleAlerts() }
    }
    @Published var twentyFourHour: Bool {
        didSet { store.twentyFourHour = twentyFourHour; refreshPiP(); publishToWidgets() }
    }
    @Published private(set) var locationState: LocationState = .idle
    /// The notifications at each chosen prayer's time.
    let alerts = PrayerAlertController()

    private let store: PrayerSettingsStore
    /// The copy the next-prayer widget reads (App Group); nil when the build has none.
    private let widgetStore: PrayerSettingsStore?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    /// Made on first use and kept, so a running window follows place and settings changes.
    private var provider: PrayerPiPProvider?

    init(store: PrayerSettingsStore = PrayerSettingsStore(),
         widgetStore: PrayerSettingsStore? = SharedContainer.prayerStore()) {
        self.store = store
        self.widgetStore = widgetStore
        place = store.place
        parameters = store.parameters
        twentyFourHour = store.twentyFourHour
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        // Settings saved before the widgets existed reach them on the first launch.
        publishToWidgets()
    }

    /// Saved settings that are present but unreadable; shown, never overwritten by themselves.
    var unreadableSettings: [PrayerSettingsIssue] { store.unreadableSettings }

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
        // One time a line in a portrait window, whose text area is only its upper half.
        let made = PrayerPiPProvider(schedule: schedule, placeName: place.name, twentyFourHour: twentyFourHour,
                                     timesPerLine: AppServices.shared.pipLayout.isPortrait ? 1 : 2)
        provider = made
        return made
    }

    private func set(_ newPlace: PrayerPlace) {
        place = newPlace
        store.place = newPlace
        refreshPiP()
        publishToWidgets()
        rescheduleAlerts()
    }

    /// Turns the alert for one prayer on or off (asking for notification permission the first
    /// time one is turned on) and schedules again.
    func setAlert(_ enabled: Bool, for prayer: Prayer) async {
        await alerts.setEnabled(enabled, for: prayer, schedule: schedule, placeName: place?.name)
    }

    /// Schedules the adhan alerts again from now (at launch, on returning to the app, and when
    /// the place or the times change), so they keep running days ahead.
    func rescheduleAlerts() {
        alerts.apply(schedule: schedule, placeName: place?.name)
    }

    /// Copies the place and settings for the widgets and reloads them when anything changed.
    private func publishToWidgets() {
        guard let widgetStore, store.copy(to: widgetStore) else { return }
        WidgetCenter.shared.reloadAllTimelines()
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
        let place = PrayerPlace(name: "موقعي الحالي", coordinates: coordinates, timeZoneID: TimeZone.current.identifier,
                                isCurrentLocation: true)
        set(place)
        name(place, at: location)
    }

    /// Names a place read from the device's location after its city («كركوك»), from Apple's
    /// reverse geocoding: the location is sent to Apple once, when the user chooses it, and
    /// nothing else. Without a name (offline, no result) it stays «موقعي الحالي»; a place
    /// chosen meanwhile is never renamed.
    private func name(_ place: PrayerPlace, at location: CLLocation) {
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ar")) { [weak self] marks, _ in
            let mark = marks?.first
            guard let name = mark?.locality ?? mark?.subAdministrativeArea ?? mark?.administrativeArea,
                  !name.isEmpty else { return }
            Task { @MainActor in
                guard let self, self.place == place else { return }
                self.set(PrayerPlace(name: name, coordinates: place.coordinates, timeZoneID: place.timeZoneID,
                                     isCurrentLocation: true))
            }
        }
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
