import Foundation

/// The direction of the Kaaba from a place, on the great circle (the shortest path), and the
/// distance to it.
public enum Qibla {
    /// The Kaaba, Makkah.
    public static let kaaba = Coordinates(latitude: 21.4225, longitude: 39.8262)

    /// Degrees clockwise from true north, 0..<360.
    public static func bearing(from place: Coordinates) -> Double {
        let lat = place.latitude * .pi / 180
        let kaabaLat = kaaba.latitude * .pi / 180
        let delta = (kaaba.longitude - place.longitude) * .pi / 180
        let angle = atan2(sin(delta), cos(lat) * tan(kaabaLat) - sin(lat) * cos(delta)) * 180 / .pi
        let bearing = angle.truncatingRemainder(dividingBy: 360)
        return bearing < 0 ? bearing + 360 : bearing
    }

    /// Great-circle distance to the Kaaba, in kilometres.
    public static func distance(from place: Coordinates) -> Double {
        let lat1 = place.latitude * .pi / 180
        let lat2 = kaaba.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLng = (kaaba.longitude - place.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 6371.0088 * 2 * asin(min(1, sqrt(a)))
    }

    /// How far to turn the phone (degrees, -180...180, positive clockwise) so that its top
    /// points at the Qibla, given the phone's heading from true north.
    public static func turn(bearing: Double, heading: Double) -> Double {
        var delta = (bearing - heading).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// The eight compass points, in Arabic, for a bearing.
    public static func compassPoint(_ bearing: Double) -> String {
        let names = ["الشمال", "الشمال الشرقي", "الشرق", "الجنوب الشرقي", "الجنوب", "الجنوب الغربي", "الغرب",
                     "الشمال الغربي"]
        let index = Int(((bearing.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return names[index]
    }
}

/// How far a compass reading can be trusted, from the error the system reports for it.
/// Only a good or fair reading confirms that the device faces the Qibla; otherwise the turn is
/// shown as approximate and the user is asked to calibrate, so no false precision is shown.
public enum QiblaReadingQuality: Equatable, Sendable {
    /// Within 10°.
    case good
    /// Within 20°.
    case fair
    /// Worse than 20°.
    case poor
    /// The system gives no error: the compass needs calibrating.
    case unknown

    public init(accuracy: Double?) {
        guard let accuracy, accuracy >= 0 else { self = .unknown; return }
        switch accuracy {
        case ...10: self = .good
        case ...20: self = .fair
        default: self = .poor
        }
    }

    public var confirmsFacing: Bool { self == .good || self == .fair }
}
