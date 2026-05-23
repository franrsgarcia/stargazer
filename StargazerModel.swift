import Foundation
import SwiftUI
import ARKit
import CoreLocation

enum SelectionSource {
    case none
    case tap
    case search
}

final class StargazerModel: ObservableObject {
    @Published var bodies: [CelestialBody] = []
    @Published var bodyOverlays: [UUID: CGPoint] = [:]
    @Published var pastTrajectoryPoints: [CGPoint] = []
    @Published var futureTrajectoryPoints: [CGPoint] = []
    @Published var horizonPoints: [CGPoint] = []
    @Published var showHorizon: Bool = true
    @Published var showCameraFeed: Bool = true
    @Published var showSun: Bool = true
    @Published var showMoon: Bool = true
    @Published var showPlanets: Bool = true
    @Published var showStars: Bool = true
    @Published var statusText = "Stargazer"
    @Published var summaryText = "Point your device at the sky to see planets and the moon."

    @Published private(set) var selectedBodyID: UUID?
    @Published private(set) var selectedBodyName: String?
    @Published private(set) var selectionSource: SelectionSource = .none
    @Published var selectedRiseText: String?
    @Published var selectedSetText: String?
    @Published var searchArrowOpacity: Double = 0
    @Published var searchInfoOpacity: Double = 0
    @Published var viewportSize: CGSize = UIScreen.main.bounds.size

    private var selectedTrajectorySamples: [(date: Date, az: Double, alt: Double, isFuture: Bool)] = []

    private let locationManager = LocationManager()
    private var currentLocation: CLLocation?
    private var currentHeading: CLHeading?
    private var updateTimer: Timer?

    static let searchableNames = ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn"]

    init() {
        locationManager.delegate = self
    }

    func isBodyTypeShown(_ body: CelestialBody) -> Bool {
        switch body.type {
        case .sun: return showSun
        case .moon: return showMoon
        case .planet: return showPlanets
        }
    }

    func shouldRenderMarker(for body: CelestialBody) -> Bool {
        isBodyTypeShown(body) && body.isVisible
    }

    var showInfoCard: Bool {
        guard selectedBodyName != nil else { return false }
        switch selectionSource {
        case .none: return false
        case .tap: return true
        case .search: return searchInfoOpacity > 0.35
        }
    }

    func startTracking() {
        locationManager.start()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshCelestialData()
        }
        refreshCelestialData()
    }

    func refreshCelestialData() {
        guard let location = currentLocation else {
            statusText = "Waiting for location permission..."
            return
        }

        let date = Date()
        let coordinate = location.coordinate
        let selectedName = selectedBodyName

        DispatchQueue.global(qos: .userInitiated).async {
            let bodies = CelestialCalculator.bodies(at: date, location: coordinate)
            var trajectorySamples: [(date: Date, az: Double, alt: Double, isFuture: Bool)] = []
            var riseText: String? = nil
            var setText: String? = nil

            if let selectedName = selectedName {
                trajectorySamples = CelestialCalculator.sampleTrajectory(name: selectedName, centerDate: date, location: coordinate, spanMinutes: 360, stepMinutes: 5)
                let riseSetSamples = CelestialCalculator.sampleTrajectory(name: selectedName, centerDate: date, location: coordinate, spanMinutes: 1440, stepMinutes: 15)
                let riseSet = self.deriveRiseSetStrings(from: riseSetSamples)
                riseText = riseSet.rise
                setText = riseSet.set
            }

            DispatchQueue.main.async {
                self.bodies = bodies
                self.summaryText = String(format: "%.0f° N, %.0f° E • %@", location.coordinate.latitude, location.coordinate.longitude, DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
                self.statusText = "Sky model updated"

                if let selectedName = selectedName, let matching = bodies.first(where: { $0.name == selectedName }) {
                    self.selectedBodyID = matching.id
                }
                self.selectedTrajectorySamples = trajectorySamples
                self.selectedRiseText = riseText
                self.selectedSetText = setText
            }
        }
    }

    func toggleSelection(of body: CelestialBody) {
        if selectedBodyID == body.id && selectionSource == .tap {
            clearSelection()
            return
        }
        selectionSource = .tap
        searchArrowOpacity = 0
        searchInfoOpacity = 1
        selectBody(named: body.name, matchingID: body.id)
    }

    func selectFromSearch(named name: String) {
        selectionSource = .search
        searchArrowOpacity = 1
        searchInfoOpacity = 0
        let matching = bodies.first(where: { $0.name == name })
        selectBody(named: name, matchingID: matching?.id)
    }

    func clearSelection() {
        selectedBodyID = nil
        selectedBodyName = nil
        selectionSource = .none
        selectedRiseText = nil
        selectedSetText = nil
        selectedTrajectorySamples = []
        searchArrowOpacity = 0
        searchInfoOpacity = 0
        DispatchQueue.main.async {
            self.pastTrajectoryPoints = []
            self.futureTrajectoryPoints = []
        }
    }

    private func selectBody(named name: String, matchingID: UUID?) {
        selectedBodyID = matchingID
        selectedBodyName = name
        guard let location = currentLocation else { return }
        selectedTrajectorySamples = []
        selectedRiseText = nil
        selectedSetText = nil

        let coordinate = location.coordinate
        let date = Date()

        DispatchQueue.global(qos: .userInitiated).async {
            let trajectory = CelestialCalculator.sampleTrajectory(name: name, centerDate: date, location: coordinate, spanMinutes: 360, stepMinutes: 5)
            let riseSetSamples = CelestialCalculator.sampleTrajectory(name: name, centerDate: date, location: coordinate, spanMinutes: 1440, stepMinutes: 15)
            let riseSet = self.deriveRiseSetStrings(from: riseSetSamples)

            DispatchQueue.main.async {
                self.selectedTrajectorySamples = trajectory
                self.selectedRiseText = riseSet.rise
                self.selectedSetText = riseSet.set
            }
        }
    }

    func updateSearchGuidance(for bodyName: String?) {
        guard selectionSource == .search, let bodyName = bodyName else { return }
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        guard let body = bodies.first(where: { $0.name == bodyName }),
              let point = bodyOverlays[body.id] else {
            searchArrowOpacity = 1
            searchInfoOpacity = 0
            return
        }

        let centerX = viewportSize.width / 2
        let centerY = viewportSize.height / 2
        let distance = hypot(point.x - centerX, point.y - centerY)
        let threshold = min(viewportSize.width, viewportSize.height) * 0.14
        let blend = max(0, min(1, (distance - threshold * 0.5) / (threshold * 0.9)))

        searchArrowOpacity = blend
        searchInfoOpacity = 1 - blend
    }

    private func deriveRiseSetStrings(from samples: [(date: Date, az: Double, alt: Double, isFuture: Bool)]) -> (rise: String, set: String) {
        var nextRise: Date?
        var nextSet: Date?

        for i in 1..<samples.count {
            let previous = samples[i - 1]
            let current = samples[i]

            if nextRise == nil, previous.alt <= 0, current.alt > 0 {
                nextRise = current.date
            }
            if nextSet == nil, previous.alt > 0, current.alt <= 0 {
                nextSet = current.date
            }

            if nextRise != nil, nextSet != nil {
                break
            }
        }

        let riseText = nextRise.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "Unknown"
        let setText = nextSet.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "Unknown"
        return (rise: riseText, set: setText)
    }

    func updateOverlays(from frame: ARFrame, viewportSize: CGSize) {
        let viewMatrix = frame.camera.viewMatrix(for: .portrait)
        let projectionMatrix = frame.camera.projectionMatrix(for: .portrait, viewportSize: viewportSize, zNear: 0.01, zFar: 1000)

        var overlays: [UUID: CGPoint] = [:]
        for body in bodies where body.isVisible {
            let direction = CelestialCalculator.directionVector(azimuth: body.azimuth, altitude: body.altitude)
            let cameraPoint = viewMatrix * SIMD4<Float>(direction, 0)
            guard cameraPoint.z < 0 else { continue }

            let clip = projectionMatrix * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1)
            guard clip.w != 0 else { continue }
            let ndc = clip / clip.w
            let x = CGFloat((ndc.x + 1) / 2) * viewportSize.width
            let y = CGFloat((1 - ndc.y) / 2) * viewportSize.height
            overlays[body.id] = CGPoint(x: x, y: y)
        }

        var pastPoints: [CGPoint] = []
        var futurePoints: [CGPoint] = []
        if selectedBodyName != nil, !selectedTrajectorySamples.isEmpty {
            for sample in selectedTrajectorySamples {
                let dir = CelestialCalculator.directionVector(azimuth: sample.az, altitude: sample.alt)
                let cameraPoint = viewMatrix * SIMD4<Float>(dir, 0)
                guard cameraPoint.z < 0 else { continue }
                let clip = projectionMatrix * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1)
                guard clip.w != 0 else { continue }
                let ndc = clip / clip.w
                let x = CGFloat((ndc.x + 1) / 2) * viewportSize.width
                let y = CGFloat((1 - ndc.y) / 2) * viewportSize.height
                let point = CGPoint(x: x, y: y)
                if sample.isFuture {
                    futurePoints.append(point)
                } else {
                    pastPoints.append(point)
                }
            }
        }

        var horizonPts: [CGPoint] = []
        for az in stride(from: 0.0, to: 360.0, by: 5.0) {
            let dir = CelestialCalculator.directionVector(azimuth: az, altitude: 0.0)
            let cameraPoint = viewMatrix * SIMD4<Float>(dir, 0)
            guard cameraPoint.z < 0 else { continue }
            let clip = projectionMatrix * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1)
            guard clip.w != 0 else { continue }
            let ndc = clip / clip.w
            let x = CGFloat((ndc.x + 1) / 2) * viewportSize.width
            let y = CGFloat((1 - ndc.y) / 2) * viewportSize.height
            horizonPts.append(CGPoint(x: x, y: y))
        }

        DispatchQueue.main.async {
            self.bodyOverlays = overlays
            self.pastTrajectoryPoints = pastPoints
            self.futureTrajectoryPoints = futurePoints
            self.horizonPoints = horizonPts
            self.updateSearchGuidance(for: self.selectedBodyName)
        }
    }
}

extension StargazerModel: LocationManagerDelegate {
    func locationManager(didUpdate location: CLLocation?, heading: CLHeading?) {
        currentLocation = location
        currentHeading = heading
        refreshCelestialData()
    }
}
