import Foundation
import SwiftUI
import ARKit
import CoreLocation
import simd

enum SelectionSource {
    case none
    case tap
    case search
}

enum SearchArrowMode {
    case edge
    case onBody
}

struct SearchArrowState {
    var isVisible: Bool = false
    var position: CGPoint = .zero
    var angle: Double = 0
    var mode: SearchArrowMode = .edge
}

struct CardinalMarker: Identifiable {
    var id: String { label }
    let label: String
    let point: CGPoint
    let rotation: Double
    let isNorth: Bool
}

@MainActor
final class StargazerModel: ObservableObject {
    @Published var bodies: [CelestialBody] = []
    @Published var bodyOverlays: [String: CGPoint] = [:]
    @Published var pastTrajectorySegments: [[CGPoint]] = []
    @Published var futureTrajectorySegments: [[CGPoint]] = []
    @Published var horizonPoints: [CGPoint] = []
    @Published var showHorizon: Bool = true
    @Published var showCameraFeed: Bool = true
    @Published var showSun: Bool = true
    @Published var showMoon: Bool = true
    @Published var showPlanets: Bool = true
    @Published var showStars: Bool = true
    @Published var statusText = "Stargazer"
    @Published var summaryText = "Point your device at the sky to see planets and the moon."

    @Published private(set) var selectedBodyName: String?
    @Published private(set) var selectionSource: SelectionSource = .none
    @Published var selectedRiseText: String?
    @Published var selectedSetText: String?
    @Published var searchArrow = SearchArrowState()
    @Published private(set) var searchInfoRevealed = false
    @Published var viewportSize: CGSize = UIScreen.main.bounds.size
    @Published var locationLabel = "Locating..."
    @Published var cardinalMarkers: [CardinalMarker] = []
    @Published private(set) var compassResetToken = UUID()

    private var selectedTrajectorySamples: [(date: Date, az: Double, alt: Double, isFuture: Bool)] = []
    private let geocoder = CLGeocoder()
    private var lastGeocodedCoordinate: CLLocationCoordinate2D?
    private var smoothedOverlays: [String: CGPoint] = [:]
    private var searchGuidanceComplete = false
    private var lastYawCorrection: Float = 0
    private var compassYawOffset: Float = 0
    private var shouldLatchCompassOffset = false
    private var lastProjectionViewport: CGSize = .zero
    private var lastScreenOffset: CGPoint = .zero

    private let locationManager = LocationManager()
    private var currentLocation: CLLocation?
    private var currentHeading: CLHeading?
    private var updateTimer: Timer?

    static let searchableNames = ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn"]

    private static let cardinalDirections: [(String, Double)] = [
        ("N", 0), ("NE", 45), ("E", 90), ("SE", 135),
        ("S", 180), ("SW", 225), ("W", 270), ("NW", 315)
    ]

    init() {
        locationManager.delegate = self
    }

    private func updateLocationLabel(for location: CLLocation) {
        let coordinate = location.coordinate
        if let last = lastGeocodedCoordinate {
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            if location.distance(from: previous) < 200 { return }
        }
        lastGeocodedCoordinate = coordinate

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            let place = placemarks?.first
            let city = place?.locality ?? place?.subAdministrativeArea ?? place?.name ?? ""
            let country = place?.country ?? ""
            let label = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")

            Task { @MainActor in
                if !label.isEmpty {
                    self.locationLabel = label
                } else {
                    self.locationLabel = String(format: "%.2f°, %.2f°", coordinate.latitude, coordinate.longitude)
                }
            }
        }
    }

    func isBodyTypeShown(_ body: CelestialBody) -> Bool {
        switch body.type {
        case .sun: return showSun
        case .moon: return showMoon
        case .planet: return showPlanets
        }
    }

    func shouldRenderMarker(for body: CelestialBody) -> Bool {
        isBodyTypeShown(body) && bodyOverlays[body.name] != nil
    }

    var showInfoCard: Bool {
        guard selectedBodyName != nil else { return false }
        switch selectionSource {
        case .none: return false
        case .tap: return true
        case .search: return searchInfoRevealed
        }
    }

    func startTracking() {
        locationManager.start()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCelestialData()
            }
        }
        refreshCelestialData()
    }

    /// Re-sync sky alignment to the device compass (no manual calibration targets).
    func resetCompassAlignment() {
        locationManager.resetHeading()
        compassResetToken = UUID()
        compassYawOffset = 0
        shouldLatchCompassOffset = true
        statusText = "Compass realigned"
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
                let riseSet = Self.deriveRiseSetStrings(from: riseSetSamples)
                riseText = riseSet.rise
                setText = riseSet.set
            }

            Task { @MainActor in
                self.bodies = bodies
                self.summaryText = String(format: "%.0f° N, %.0f° E • %@", location.coordinate.latitude, location.coordinate.longitude, DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
                self.statusText = "Sky model updated"
                self.selectedTrajectorySamples = trajectorySamples
                self.selectedRiseText = riseText
                self.selectedSetText = setText
            }
        }
    }

    func toggleSelection(of body: CelestialBody) {
        if selectedBodyName == body.name && selectionSource == .tap {
            clearSelection()
            return
        }
        searchGuidanceComplete = true
        searchArrow.isVisible = false
        selectionSource = .tap
        searchInfoRevealed = true
        selectBody(named: body.name)
    }

    func selectFromSearch(named name: String) {
        resetSearchGuidance()
        selectionSource = .search
        searchInfoRevealed = false
        searchGuidanceComplete = false
        selectBody(named: name)

        guard let body = bodies.first(where: { $0.name == name }) else {
            searchArrow.isVisible = true
            return
        }

        updateSearchGuidance(projectedPoint: searchGuidanceTarget(for: body))
    }

    func clearSelection() {
        selectedBodyName = nil
        selectionSource = .none
        selectedRiseText = nil
        selectedSetText = nil
        selectedTrajectorySamples = []
        resetSearchGuidance()
        pastTrajectorySegments = []
        futureTrajectorySegments = []
    }

    private func resetSearchGuidance() {
        searchGuidanceComplete = false
        searchInfoRevealed = false
        searchArrow = SearchArrowState()
    }

    private func selectBody(named name: String) {
        selectedBodyName = name
        pastTrajectorySegments = []
        futureTrajectorySegments = []
        guard let location = currentLocation else { return }
        selectedTrajectorySamples = []
        selectedRiseText = nil
        selectedSetText = nil

        let coordinate = location.coordinate
        let date = Date()

        DispatchQueue.global(qos: .userInitiated).async {
            let trajectory = CelestialCalculator.sampleTrajectory(name: name, centerDate: date, location: coordinate, spanMinutes: 360, stepMinutes: 5)
            let riseSetSamples = CelestialCalculator.sampleTrajectory(name: name, centerDate: date, location: coordinate, spanMinutes: 1440, stepMinutes: 15)
            let riseSet = Self.deriveRiseSetStrings(from: riseSetSamples)

            Task { @MainActor in
                self.selectedTrajectorySamples = trajectory
                self.selectedRiseText = riseSet.rise
                self.selectedSetText = riseSet.set
            }
        }
    }

    private static func deriveRiseSetStrings(from samples: [(date: Date, az: Double, alt: Double, isFuture: Bool)]) -> (rise: String, set: String) {
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

    private func projectedPoint(for name: String) -> CGPoint? {
        bodyOverlays[name]
    }

    private func cameraDirection(for body: CelestialBody, yawCorrection: Float) -> SIMD3<Float> {
        var direction = CelestialCalculator.directionVector(azimuth: body.azimuth, altitude: body.altitude)
        if abs(yawCorrection) > 0.0001 {
            direction = rotateAroundY(direction, by: yawCorrection)
        }
        return direction
    }

    private func cameraSpaceGuidanceHint(cameraPoint: SIMD3<Float>, viewportSize: CGSize) -> CGPoint {
        let centerX = viewportSize.width / 2
        let centerY = viewportSize.height / 2
        let scale: CGFloat = 140

        // Horizontal bearing in camera space — valid even when the target is behind the viewer.
        let horizontalX = cameraPoint.x
        let horizontalY = -cameraPoint.y
        let horizontalLength = hypot(Double(horizontalX), Double(horizontalY))

        if horizontalLength > 0.02 {
            let nx = CGFloat(horizontalX / Float(horizontalLength))
            let ny = CGFloat(horizontalY / Float(horizontalLength))
            return CGPoint(x: centerX + nx * scale, y: centerY + ny * scale)
        }

        if cameraPoint.y > 0.1 {
            return CGPoint(x: centerX, y: centerY - scale)
        }
        if cameraPoint.y < -0.1 {
            return CGPoint(x: centerX, y: centerY + scale)
        }
        return CGPoint(x: centerX, y: centerY + (cameraPoint.z > 0 ? scale : -scale))
    }

    private func searchGuidanceTarget(for body: CelestialBody) -> CGPoint? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let projectionViewport = lastProjectionViewport.width > 0 ? lastProjectionViewport : viewportSize
        let direction = cameraDirection(for: body, yawCorrection: lastYawCorrection)
        let cameraPoint = (lastViewMatrix * SIMD4<Float>(direction, 0)).xyz

        if isInFront(cameraZ: cameraPoint.z, altitude: body.altitude),
           let projection = project(
               azimuth: body.azimuth,
               altitude: body.altitude,
               viewMatrix: lastViewMatrix,
               projectionMatrix: lastProjectionMatrix,
               viewportSize: projectionViewport,
               screenOffset: lastScreenOffset,
               yawCorrection: lastYawCorrection
           ) {
            return projection.point
        }

        return cameraSpaceGuidanceHint(cameraPoint: cameraPoint, viewportSize: viewportSize)
    }

    private func compassHeadingDegrees(from heading: CLHeading) -> Double? {
        if heading.trueHeading >= 0 {
            return heading.trueHeading
        }
        if heading.magneticHeading >= 0 {
            return heading.magneticHeading
        }
        return nil
    }

    /// Horizontal camera heading in ARKit world space (0 = north, π/2 = east).
    private func cameraHeadingRadians(from frame: ARFrame) -> Float {
        let transform = frame.camera.transform
        let forward = SIMD3<Float>(-transform.columns.2.x, 0, -transform.columns.2.z)
        let length = simd_length(forward)
        guard length > 0.001 else { return 0 }
        let normalized = forward / length
        return atan2(normalized.x, -normalized.z)
    }

    /// Snap a fixed north offset when the user resets — device rotation stays in the AR view matrix.
    private func latchCompassOffsetIfNeeded(for frame: ARFrame) {
        guard shouldLatchCompassOffset else { return }
        guard let heading = currentHeading,
              let compassDegrees = compassHeadingDegrees(from: heading) else {
            return
        }

        let compassRadians = Float(compassDegrees * .pi / 180)
        let arkitHeading = cameraHeadingRadians(from: frame)
        compassYawOffset = compassRadians - arkitHeading
        shouldLatchCompassOffset = false
    }

    private func rotateAroundY(_ vector: SIMD3<Float>, by angle: Float) -> SIMD3<Float> {
        guard abs(angle) > 0.0001 else { return vector }
        let q = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        return simd_act(q, vector)
    }

    private func project(
        azimuth: Double,
        altitude: Double,
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        viewportSize: CGSize,
        screenOffset: CGPoint = .zero,
        yawCorrection: Float = 0
    ) -> (point: CGPoint, cameraZ: Float)? {
        var direction = CelestialCalculator.directionVector(azimuth: azimuth, altitude: altitude)
        if abs(yawCorrection) > 0.0001 {
            direction = rotateAroundY(direction, by: yawCorrection)
        }
        let cameraPoint = viewMatrix * SIMD4<Float>(direction, 0)
        let cameraZ = cameraPoint.z

        let clip = projectionMatrix * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1)
        guard clip.w != 0 else { return nil }

        let ndc = clip / clip.w
        let x = CGFloat((ndc.x + 1) / 2) * viewportSize.width - screenOffset.x
        let y = CGFloat((1 - ndc.y) / 2) * viewportSize.height - screenOffset.y
        return (CGPoint(x: x, y: y), cameraZ)
    }

    private func isInFront(cameraZ: Float, altitude: Double) -> Bool {
        // Below-horizon bodies sit on the far side of the globe; use a looser threshold when panning down.
        let threshold: Float = altitude < 0 ? 0.35 : 0.05
        return cameraZ < threshold
    }

    private func smooth(point: CGPoint, for bodyName: String, factor: CGFloat = 0.35) -> CGPoint {
        guard let previous = smoothedOverlays[bodyName] else {
            return point
        }
        return CGPoint(
            x: previous.x + (point.x - previous.x) * factor,
            y: previous.y + (point.y - previous.y) * factor
        )
    }

    private func isOnScreen(_ point: CGPoint, in size: CGSize, margin: CGFloat = 24) -> Bool {
        point.x >= margin && point.x <= size.width - margin &&
        point.y >= margin && point.y <= size.height - margin
    }

    private func markerClearance(for body: CelestialBody) -> CGFloat {
        switch body.type {
        case .sun: return 58
        case .moon: return 46
        case .planet: return 34
        }
    }

    private func offsetArrowPlacement(
        pointingTo target: CGPoint,
        approachFrom origin: CGPoint,
        clearance: CGFloat
    ) -> (point: CGPoint, angle: Double) {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let distance = max(hypot(dx, dy), 1)
        let ux = dx / distance
        let uy = dy / distance
        let angle = atan2(dy, dx)
        let point = CGPoint(x: target.x - ux * clearance, y: target.y - uy * clearance)
        return (point, angle)
    }

    private func edgePlacement(toward target: CGPoint, in size: CGSize, margin: CGFloat = 44) -> (point: CGPoint, angle: Double) {
        let cx = size.width / 2
        let cy = size.height / 2
        let dx = target.x - cx
        let dy = target.y - cy

        if dx == 0 && dy == 0 {
            let point = CGPoint(x: cx, y: margin)
            return (point, atan2(target.y - point.y, target.x - point.x))
        }

        let halfW = max(size.width / 2 - margin, 1)
        let halfH = max(size.height / 2 - margin, 1)
        let scaleX = dx != 0 ? abs(halfW / dx) : .infinity
        let scaleY = dy != 0 ? abs(halfH / dy) : .infinity
        let scale = min(scaleX, scaleY)
        let edgePoint = CGPoint(x: cx + dx * scale, y: cy + dy * scale)
        let angle = atan2(target.y - edgePoint.y, target.x - edgePoint.x)
        return (edgePoint, angle)
    }

    private func isSearchTargetInFront(for body: CelestialBody) -> Bool {
        let direction = cameraDirection(for: body, yawCorrection: lastYawCorrection)
        let cameraPoint = (lastViewMatrix * SIMD4<Float>(direction, 0)).xyz
        return isInFront(cameraZ: cameraPoint.z, altitude: body.altitude)
    }

    func updateSearchGuidance(projectedPoint: CGPoint?) {
        guard selectionSource == .search, !searchGuidanceComplete else { return }
        guard let bodyName = selectedBodyName,
              let body = bodies.first(where: { $0.name == bodyName }),
              viewportSize.width > 0, viewportSize.height > 0 else { return }

        let size = viewportSize
        let centerX = size.width / 2
        let centerY = size.height / 2
        let threshold = min(size.width, size.height) * 0.14
        let inFront = isSearchTargetInFront(for: body)

        guard let target = projectedPoint ?? bodyOverlays[bodyName] ?? searchGuidanceTarget(for: body) else {
            searchArrow.isVisible = false
            return
        }

        let distance = hypot(target.x - centerX, target.y - centerY)
        let onScreen = isOnScreen(target, in: size)

        let viewportCenter = CGPoint(x: centerX, y: centerY)

        if inFront && onScreen {
            let clearance = markerClearance(for: body)
            let placement = offsetArrowPlacement(
                pointingTo: target,
                approachFrom: viewportCenter,
                clearance: clearance
            )
            searchArrow.isVisible = true
            searchArrow.position = placement.point
            searchArrow.angle = placement.angle
            searchArrow.mode = .onBody

            if distance < threshold {
                searchGuidanceComplete = true
                searchInfoRevealed = true
                searchArrow.isVisible = false
            }
        } else {
            let edge = edgePlacement(toward: target, in: size)
            searchArrow.isVisible = true
            searchArrow.position = edge.point
            searchArrow.angle = edge.angle
            searchArrow.mode = .edge
        }
    }

    private var lastViewMatrix: simd_float4x4 = matrix_identity_float4x4
    private var lastProjectionMatrix: simd_float4x4 = matrix_identity_float4x4

    private func buildTrajectorySegments(
        from samples: [(date: Date, az: Double, alt: Double, isFuture: Bool)],
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        projectionViewport: CGSize,
        visibleViewport: CGSize,
        screenOffset: CGPoint,
        yawCorrection: Float,
        maxJump: CGFloat
    ) -> [[CGPoint]] {
        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []

        func flush() {
            if current.count > 1 {
                segments.append(current)
            }
            current = []
        }

        for sample in samples {
            let inFrontThreshold: Float = sample.alt < 0 ? 0.35 : 0.2
            guard let projection = project(
                azimuth: sample.az,
                altitude: sample.alt,
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                viewportSize: projectionViewport,
                screenOffset: screenOffset,
                yawCorrection: yawCorrection
            ), projection.cameraZ < inFrontThreshold else {
                flush()
                continue
            }

            let point = projection.point
            let margin: CGFloat = 120
            let onScreen = point.x >= -margin && point.x <= visibleViewport.width + margin &&
                point.y >= -margin && point.y <= visibleViewport.height + margin
            guard onScreen else {
                flush()
                continue
            }

            if let last = current.last {
                let distance = hypot(point.x - last.x, point.y - last.y)
                if distance > maxJump {
                    flush()
                }
            }
            current.append(point)
        }

        flush()
        return segments
    }

    private func horizonY(at x: CGFloat, in points: [CGPoint]) -> CGFloat? {
        guard points.count >= 2 else { return nil }

        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let minX = min(p0.x, p1.x)
            let maxX = max(p0.x, p1.x)
            guard x >= minX && x <= maxX else { continue }

            if abs(p1.x - p0.x) < 0.001 {
                return (p0.y + p1.y) / 2
            }
            let t = (x - p0.x) / (p1.x - p0.x)
            return p0.y + t * (p1.y - p0.y)
        }
        return nil
    }

    private func horizonTangentAngle(at x: CGFloat, in horizonPts: [CGPoint]) -> Double {
        guard horizonPts.count >= 2 else { return 0 }
        let y = horizonY(at: x, in: horizonPts) ?? horizonPts[0].y
        let point = CGPoint(x: x, y: y)
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for i in 0..<horizonPts.count {
            let distance = hypot(horizonPts[i].x - point.x, horizonPts[i].y - point.y)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
            }
        }
        let start = max(0, bestIndex - 1)
        let end = min(horizonPts.count - 1, bestIndex + 1)
        let dx = horizonPts[end].x - horizonPts[start].x
        let dy = horizonPts[end].y - horizonPts[start].y
        return atan2(dy, dx)
    }

    func updateOverlays(from frame: ARFrame, viewportSize: CGSize, arViewFrame: CGRect? = nil) {
        let projectionViewport = arViewFrame?.size ?? viewportSize
        let projectionOffset = CGPoint(x: arViewFrame?.origin.x ?? 0, y: arViewFrame?.origin.y ?? 0)
        let viewMatrix = frame.camera.viewMatrix(for: .portrait)
        let projectionMatrix = frame.camera.projectionMatrix(for: .portrait, viewportSize: projectionViewport, zNear: 0.01, zFar: 1000)
        latchCompassOffsetIfNeeded(for: frame)
        let yawCorrection = compassYawOffset
        lastViewMatrix = viewMatrix
        lastProjectionMatrix = projectionMatrix
        lastYawCorrection = yawCorrection
        lastProjectionViewport = projectionViewport
        lastScreenOffset = projectionOffset

        var overlays: [String: CGPoint] = [:]

        for body in bodies where isBodyTypeShown(body) {
            guard let projection = project(
                azimuth: body.azimuth,
                altitude: body.altitude,
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                viewportSize: projectionViewport,
                screenOffset: projectionOffset,
                yawCorrection: yawCorrection
            ), isInFront(cameraZ: projection.cameraZ, altitude: body.altitude) else {
                continue
            }

            let smoothed = smooth(point: projection.point, for: body.name)
            smoothedOverlays[body.name] = smoothed
            overlays[body.name] = smoothed
        }

        for name in smoothedOverlays.keys where overlays[name] == nil {
            smoothedOverlays.removeValue(forKey: name)
        }

        var pastSegments: [[CGPoint]] = []
        var futureSegments: [[CGPoint]] = []
        if selectedBodyName != nil, !selectedTrajectorySamples.isEmpty {
            let maxJump = min(viewportSize.width, viewportSize.height) * 0.18
            pastSegments = buildTrajectorySegments(
                from: selectedTrajectorySamples.filter { !$0.isFuture },
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                projectionViewport: projectionViewport,
                visibleViewport: viewportSize,
                screenOffset: projectionOffset,
                yawCorrection: yawCorrection,
                maxJump: maxJump
            )
            futureSegments = buildTrajectorySegments(
                from: selectedTrajectorySamples.filter { $0.isFuture },
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                projectionViewport: projectionViewport,
                visibleViewport: viewportSize,
                screenOffset: projectionOffset,
                yawCorrection: yawCorrection,
                maxJump: maxJump
            )
        }

        var horizonPts: [CGPoint] = []
        for az in stride(from: 0.0, to: 360.0, by: 5.0) {
            guard let projection = project(
                azimuth: az,
                altitude: 0.0,
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                viewportSize: projectionViewport,
                screenOffset: projectionOffset,
                yawCorrection: yawCorrection
            ), projection.cameraZ < 0.05 else { continue }
            horizonPts.append(projection.point)
        }

        var cardinals: [CardinalMarker] = []
        if showHorizon {
            for (label, azimuth) in Self.cardinalDirections {
                guard let projection = project(
                    azimuth: azimuth,
                    altitude: 0,
                    viewMatrix: viewMatrix,
                    projectionMatrix: projectionMatrix,
                    viewportSize: projectionViewport,
                    screenOffset: projectionOffset,
                    yawCorrection: yawCorrection
                ), projection.cameraZ < 0.05 else { continue }

                let x = projection.point.x
                guard let y = horizonY(at: x, in: horizonPts) else { continue }
                let tangent = horizonTangentAngle(at: x, in: horizonPts)
                cardinals.append(CardinalMarker(
                    label: label,
                    point: CGPoint(x: x, y: y),
                    rotation: tangent,
                    isNorth: label == "N"
                ))
            }
        }

        bodyOverlays = overlays
        pastTrajectorySegments = pastSegments
        futureTrajectorySegments = futureSegments
        horizonPoints = horizonPts
        cardinalMarkers = cardinals

        let searchPoint = selectedBodyName.flatMap { name in
            if let overlay = bodyOverlays[name] {
                return overlay
            }
            return bodies.first(where: { $0.name == name }).flatMap { body in
                searchGuidanceTarget(for: body)
            }
        }
        updateSearchGuidance(projectedPoint: searchPoint)
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}

extension StargazerModel: LocationManagerDelegate {
    nonisolated func locationManager(didUpdate location: CLLocation?, heading: CLHeading?) {
        Task { @MainActor in
            let locationChanged: Bool
            if let location {
                locationChanged = currentLocation.map {
                    $0.coordinate.latitude != location.coordinate.latitude ||
                    $0.coordinate.longitude != location.coordinate.longitude
                } ?? true
            } else {
                locationChanged = false
            }

            currentLocation = location ?? currentLocation
            currentHeading = heading ?? currentHeading

            if let location {
                updateLocationLabel(for: location)
            }
            if locationChanged {
                refreshCelestialData()
            }
        }
    }
}
