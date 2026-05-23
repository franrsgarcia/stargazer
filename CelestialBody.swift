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
        name
    }

    /// Subtle white-ish tint for sky markers, with hints of each body's real appearance.
    var markerTint: Color {
        switch type {
        case .sun:
            return Color.white
        case .moon:
            return Color(white: 0.96)
        case .planet:
            switch name {
            case "Mercury": return Color(red: 0.96, green: 0.94, blue: 0.90)
            case "Venus": return Color(red: 1.0, green: 0.97, blue: 0.86)
            case "Mars": return Color(red: 1.0, green: 0.90, blue: 0.86)
            case "Jupiter": return Color(red: 1.0, green: 0.93, blue: 0.80)
            case "Saturn": return Color(red: 1.0, green: 0.95, blue: 0.78)
            default: return Color(white: 0.94)
            }
        }
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
        guard let au = distanceAu else { return "—" }
        let km = au * 149597870.7
        if km >= 1_000_000 {
            return String(format: "%.1fM km", km / 1_000_000)
        } else if km >= 1000 {
            return String(format: "%.0fK km", km / 1000)
        } else {
            return String(format: "%.0f km", km)
        }
    }

    var magnitudeText: String {
        switch name {
        case "Sun": return "-26.7"
        case "Moon": return "-12.7"
        case "Mercury": return "-1.0"
        case "Venus": return "-4.4"
        case "Mars": return "-1.8"
        case "Jupiter": return "-2.2"
        case "Saturn": return "0.7"
        default: return "—"
        }
    }

    var visibleUntilText: String {
        if altitude > 0 {
            return "Visible now"
        }
        return "Below horizon"
    }
}
