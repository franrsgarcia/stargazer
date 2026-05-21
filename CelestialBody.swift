import SwiftUI
import CoreLocation

enum CelestialObjectType {
    case sun, moon, planet
}

struct CelestialBody: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let type: CelestialObjectType
    let azimuth: Double
    let altitude: Double
    let distanceAu: Double?
    let color: Color

    var isVisible: Bool {
        altitude > 0
    }

    var displayLabel: String {
        let altitudeText = String(format: "%.0f°", altitude)
        return "\(name) · \(altitudeText)"
    }
}
