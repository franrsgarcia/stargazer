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

    var typeName: String {
        switch type {
        case .sun: return "Star"
        case .moon: return "Moon"
        case .planet: return "Planet"
        }
    }

    var descriptionText: String {
        switch type {
        case .sun:
            return "The Sun — the star at the center of our Solar System."
        case .moon:
            return "Earth's natural satellite. Phases and apparent brightness change over the month."
        case .planet:
            switch name {
            case "Mercury": return "Closest planet to the Sun; visible near sunrise/sunset."
            case "Venus": return "Bright inner planet often visible at dusk or dawn."
            case "Earth": return "Our home planet."
            case "Mars": return "The red planet; noticeable color and brightness changes."
            case "Jupiter": return "The largest planet; often bright with visible bands through a telescope."
            case "Saturn": return "Ringed planet; rings visible with modest telescopes."
            default: return "A planet in the Solar System."
            }
        }
    }

    var distanceText: String {
        guard let au = distanceAu else { return "Distance: —" }
        let km = au * 149597870.7
        if km >= 1_000_000 {
            return String(format: "%.2f AU (%.1fM km)", au, km / 1_000_000)
        } else if km >= 1000 {
            return String(format: "%.2f AU (%.0fk km)", au, km / 1000)
        } else {
            return String(format: "%.2f AU (%.0f km)", au, km)
        }
    }
}
