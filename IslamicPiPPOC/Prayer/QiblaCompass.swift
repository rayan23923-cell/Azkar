import CoreLocation
import Foundation

/// The device's heading for the Qibla compass, read only while the Qibla screen is shown.
/// Heading needs no permission; true north (preferred) needs the location permission, else
/// magnetic north is used and said so.
@MainActor
final class QiblaCompass: NSObject, ObservableObject {
    struct Reading: Equatable {
        /// Degrees clockwise from north.
        let degrees: Double
        let isTrueNorth: Bool
        /// Error in degrees; nil when unknown (the compass needs calibrating).
        let accuracy: Double?
    }

    @Published private(set) var reading: Reading?
    let isAvailable = CLLocationManager.headingAvailable()

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 1
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        guard isAvailable else { return }
        // True north needs location updates; only while this screen is shown, and only when
        // the location is already shared (no prompt from here).
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
        reading = nil
    }
}

extension QiblaCompass: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        let isTrue = heading.trueHeading >= 0
        let reading = Reading(degrees: isTrue ? heading.trueHeading : heading.magneticHeading, isTrueNorth: isTrue,
                              accuracy: heading.headingAccuracy >= 0 ? heading.headingAccuracy : nil)
        MainActor.assumeIsolated { self.reading = reading }
    }

    // Location updates only make true north available; the fix itself is not used here.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
