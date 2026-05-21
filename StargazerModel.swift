import Foundation
import SwiftUI
import ARKit
import CoreLocation

final class StargazerModel: ObservableObject {
    @Published var bodies: [CelestialBody] = []
    @Published var bodyOverlays: [UUID: CGPoint] = [:]
    @Published var statusText = "Stargazer"
    @Published var summaryText = "Point your device at the sky to see planets and the moon."

    private let locationManager = LocationManager()
    private var currentLocation: CLLocation?
    private var currentHeading: CLHeading?
    private var updateTimer: Timer?

    init() {
        locationManager.delegate = self
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
        bodies = CelestialCalculator.bodies(at: date, location: location.coordinate)
        summaryText = String(format: "%.0f° N, %.0f° E • %@", location.coordinate.latitude, location.coordinate.longitude, DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
        statusText = "Sky model updated"
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

        DispatchQueue.main.async {
            self.bodyOverlays = overlays
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
