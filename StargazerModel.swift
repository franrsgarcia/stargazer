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

struct SearchGuidanceDebugInfo {
    var isActive: Bool = false
    var branch: String = "—"
    var targetName: String = "—"
    var panDirection: String = "—"
    var compassHeading: String = "—"
    var bodyAzimuth: String = "—"
    var relativeBearing: String = "—"
    var adjustedRelative: String = "—"
    var frontArcLock: String = "no"
    var hasAROverlay: String = "no"
    var cameraZ: String = "—"
    var targetXY: String = "—"
    var targetOffsetX: String = "—"
    var strictOnScreen: String = "no"
    var expandedOnScreen: String = "no"
    var centerDistance: String = "—"
    var arrivalThreshold: String = "—"
    var rawArrowXY: String = "—"
    var rawAngleDeg: String = "—"
    var smoothArrowXY: String = "—"
    var smoothAngleDeg: String = "—"
    var arrowMode: String = "—"
    var arrowVisible: String = "no"
    var guidanceComplete: String = "no"

    static let inactive = SearchGuidanceDebugInfo()
}

struct CardinalMarker: Identifiable {
    var id: String { label }
    let label: String
    let point: CGPoint
    let rotation: Double
    let isNorth: Bool
}

private enum CoarseTurnDirection {
    case left
    case right
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
    @Published var searchTargetReached = false
    @Published var showSearchDebug = false
    @Published private(set) var searchGuidanceDebug = SearchGuidanceDebugInfo.inactive
    @Published private(set) var searchInfoRevealed = false
    @Published var viewportSize: CGSize = UIScreen.main.bounds.size
    @Published var locationLabel = "Locating..."
    @Published var cardinalMarkers: [CardinalMarker] = []

    private var selectedTrajectorySamples: [(date: Date, az: Double, alt: Double, isFuture: Bool)] = []
    private let geocoder = CLGeocoder()
    private var lastGeocodedCoordinate: CLLocationCoordinate2D?
    private var smoothedOverlays: [String: CGPoint] = [:]
    private var searchGuidanceComplete = false
    private var searchPanDirection: CoarseTurnDirection?
    private var smoothedSearchArrowPoint: CGPoint?
    private var smoothedSearchArrowAngle: Double?
    private var lastSelectedBodyCameraZ: Float?
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

        updateSearchGuidance()
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

    func toggleSearchDebug() {
        showSearchDebug.toggle()
        if showSearchDebug {
            updateSearchGuidance()
        } else {
            searchGuidanceDebug = .inactive
        }
    }

    func acknowledgeSearchTargetReached() {
        searchTargetReached = false
    }

    private func resetSearchGuidance() {
        searchGuidanceComplete = false
        searchInfoRevealed = false
        searchPanDirection = nil
        smoothedSearchArrowPoint = nil
        smoothedSearchArrowAngle = nil
        searchArrow = SearchArrowState()
        searchTargetReached = false
        searchGuidanceDebug = .inactive
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

    private func compassHeadingDegrees(from heading: CLHeading) -> Double? {
        if heading.trueHeading >= 0 {
            return heading.trueHeading
        }
        if heading.magneticHeading >= 0 {
            return heading.magneticHeading
        }
        return nil
    }

    /// Degrees off-target before we show a simple turn-left/right hint.
    private static let fineGuidanceThresholdDegrees = 80.0
    private static let coarseUnlockThresholdDegrees = 60.0
    private static let frontArcLockDegrees = 38.0
    private static let panDirectionFlipDegrees = 18.0
    private static let searchArrowSmoothingFactor: CGFloat = 0.26
    /// Treat targets slightly off-screen as close enough to point at directly.
    private static let searchOnScreenExpansion: CGFloat = 88

    private func compassRelativeBearingDegrees(to body: CelestialBody) -> Double? {
        guard let heading = currentHeading,
              let deviceHeading = compassHeadingDegrees(from: heading) else {
            return nil
        }

        var relative = body.azimuth - deviceHeading
        while relative > 180 { relative -= 360 }
        while relative < -180 { relative += 360 }
        return relative
    }

    private func compassSide(for relativeDegrees: Double) -> CoarseTurnDirection {
        relativeDegrees >= 0 ? .right : .left
    }

    private func screenSide(for projectedTarget: CGPoint, centerX: CGFloat) -> CoarseTurnDirection? {
        let offset = projectedTarget.x - centerX
        let threshold = max(32, centerX * 0.07)
        guard abs(offset) >= threshold else { return nil }
        return offset > 0 ? .right : .left
    }

    private func syncSearchPanDirection(
        relativeDegrees: Double?,
        projectedTarget: CGPoint?,
        centerX: CGFloat
    ) {
        var candidate: CoarseTurnDirection?

        if let relativeDegrees, abs(relativeDegrees) >= 8 {
            candidate = compassSide(for: relativeDegrees)
        }
        if let projectedTarget, let screenSide = screenSide(for: projectedTarget, centerX: centerX) {
            candidate = screenSide
        }

        guard let candidate else { return }

        guard let current = searchPanDirection else {
            searchPanDirection = candidate
            return
        }

        guard current != candidate else { return }

        if let relativeDegrees, abs(relativeDegrees) >= Self.panDirectionFlipDegrees {
            searchPanDirection = candidate
            return
        }

        if let projectedTarget {
            let offset = projectedTarget.x - centerX
            if abs(offset) >= max(48, centerX * 0.1) {
                searchPanDirection = candidate
            }
        }
    }

    private func shouldApplyFrontArcLock(
        relativeDegrees: Double,
        projectedTarget: CGPoint?,
        centerX: CGFloat
    ) -> Bool {
        guard searchPanDirection != nil,
              abs(relativeDegrees) < Self.frontArcLockDegrees else {
            return false
        }

        if let projectedTarget, let side = screenSide(for: projectedTarget, centerX: centerX) {
            return side == searchPanDirection
        }

        if abs(relativeDegrees) < Self.panDirectionFlipDegrees {
            return true
        }

        return compassSide(for: relativeDegrees) == searchPanDirection
    }

    private func panLockedRelativeDegrees(
        _ relativeDegrees: Double,
        projectedTarget: CGPoint?,
        centerX: CGFloat
    ) -> Double {
        guard shouldApplyFrontArcLock(
            relativeDegrees: relativeDegrees,
            projectedTarget: projectedTarget,
            centerX: centerX
        ), let pan = searchPanDirection else {
            return relativeDegrees
        }
        let magnitude = max(abs(relativeDegrees), 12)
        return pan == .right ? magnitude : -magnitude
    }

    private func resolveCoarseTurn(relativeDegrees: Double) -> CoarseTurnDirection? {
        let absRelative = abs(relativeDegrees)

        if absRelative >= Self.fineGuidanceThresholdDegrees {
            return searchPanDirection ?? compassSide(for: relativeDegrees)
        }

        if let locked = searchPanDirection, absRelative > Self.coarseUnlockThresholdDegrees {
            return locked
        }

        return nil
    }

    private func edgeGuidancePlacement(
        toward target: CGPoint,
        in size: CGSize,
        margin: CGFloat = 44,
        pointAtTarget: Bool = false
    ) -> (point: CGPoint, angle: Double) {
        let cx = size.width / 2
        let cy = size.height / 2
        let dx = target.x - cx
        let dy = target.y - cy

        if abs(dx) < 0.001 && abs(dy) < 0.001 {
            let point = CGPoint(x: cx, y: margin)
            let angle = pointAtTarget ? atan2(target.y - point.y, target.x - point.x) : -.pi / 2
            return (point, angle)
        }

        let halfW = max(size.width / 2 - margin, 1)
        let halfH = max(size.height / 2 - margin, 1)
        let scaleX = dx != 0 ? abs(halfW / dx) : .infinity
        let scaleY = dy != 0 ? abs(halfH / dy) : .infinity
        let scale = min(scaleX, scaleY)
        let edgePoint = CGPoint(x: cx + dx * scale, y: cy + dy * scale)
        if pointAtTarget {
            let angle = atan2(target.y - edgePoint.y, target.x - edgePoint.x)
            return (edgePoint, angle)
        }
        let outward = atan2(edgePoint.y - cy, edgePoint.x - cx)
        return (edgePoint, outward)
    }

    private func fineGuidancePlacement(
        relativeDegrees: Double,
        in size: CGSize,
        margin: CGFloat = 44
    ) -> (point: CGPoint, angle: Double) {
        let radians = relativeDegrees * .pi / 180
        let cx = size.width / 2
        let cy = size.height / 2
        let syntheticTarget = CGPoint(
            x: cx + CGFloat(sin(radians)) * 1000,
            y: cy + CGFloat(-cos(radians)) * 1000
        )
        return edgeGuidancePlacement(toward: syntheticTarget, in: size, margin: margin, pointAtTarget: false)
    }

    private func coarseTurnPlacement(
        _ turn: CoarseTurnDirection,
        in size: CGSize,
        margin: CGFloat = 48
    ) -> (point: CGPoint, angle: Double) {
        let cy = size.height / 2

        switch turn {
        case .left:
            let point = CGPoint(x: margin, y: cy)
            return (point, .pi)
        case .right:
            let point = CGPoint(x: size.width - margin, y: cy)
            return (point, 0)
        }
    }

    private func project(
        azimuth: Double,
        altitude: Double,
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        viewportSize: CGSize,
        screenOffset: CGPoint = .zero
    ) -> (point: CGPoint, cameraZ: Float)? {
        let direction = CelestialCalculator.directionVector(azimuth: azimuth, altitude: altitude)
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

    private func smoothSearchArrowPlacement(
        _ target: (point: CGPoint, angle: Double)
    ) -> (point: CGPoint, angle: Double) {
        guard let previousPoint = smoothedSearchArrowPoint,
              let previousAngle = smoothedSearchArrowAngle else {
            smoothedSearchArrowPoint = target.point
            smoothedSearchArrowAngle = target.angle
            return target
        }

        let factor = Self.searchArrowSmoothingFactor
        let point = CGPoint(
            x: previousPoint.x + (target.point.x - previousPoint.x) * factor,
            y: previousPoint.y + (target.point.y - previousPoint.y) * factor
        )

        var delta = target.angle - previousAngle
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let angle = previousAngle + delta * Double(factor)

        smoothedSearchArrowPoint = point
        smoothedSearchArrowAngle = angle
        return (point, angle)
    }

    private func formatDegrees(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.1f°", value)
    }

    private func formatPoint(_ point: CGPoint?) -> String {
        guard let point else { return "—" }
        return String(format: "(%.0f, %.0f)", point.x, point.y)
    }

    private func formatFloat(_ value: Float?) -> String {
        guard let value else { return "—" }
        return String(format: "%.3f", value)
    }

    private func refreshSearchGuidanceDebug(
        bodyName: String,
        body: CelestialBody,
        branch: String,
        relativeDegrees: Double?,
        adjustedRelative: Double?,
        frontArcLockActive: Bool,
        projectedTarget: CGPoint?,
        strictOnScreen: Bool,
        expandedOnScreen: Bool,
        centerDistance: CGFloat?,
        arrivalThreshold: CGFloat,
        rawPlacement: (point: CGPoint, angle: Double)?,
        smoothedPlacement: (point: CGPoint, angle: Double)?,
        rawMode: SearchArrowMode?,
        arrowVisible: Bool,
        guidanceComplete: Bool
    ) {
        guard showSearchDebug else { return }

        let centerX = viewportSize.width / 2
        let heading = currentHeading.flatMap { compassHeadingDegrees(from: $0) }

        var offsetX: String = "—"
        if let projectedTarget {
            offsetX = String(format: "%+.0f pt", projectedTarget.x - centerX)
        }

        searchGuidanceDebug = SearchGuidanceDebugInfo(
            isActive: true,
            branch: branch,
            targetName: bodyName,
            panDirection: searchPanDirection.map { $0 == .left ? "L" : "R" } ?? "—",
            compassHeading: formatDegrees(heading),
            bodyAzimuth: formatDegrees(body.azimuth),
            relativeBearing: formatDegrees(relativeDegrees),
            adjustedRelative: formatDegrees(adjustedRelative),
            frontArcLock: frontArcLockActive ? "yes" : "no",
            hasAROverlay: projectedTarget == nil ? "no" : "yes",
            cameraZ: formatFloat(lastSelectedBodyCameraZ),
            targetXY: formatPoint(projectedTarget),
            targetOffsetX: offsetX,
            strictOnScreen: strictOnScreen ? "yes" : "no",
            expandedOnScreen: expandedOnScreen ? "yes" : "no",
            centerDistance: centerDistance.map { String(format: "%.0f pt", $0) } ?? "—",
            arrivalThreshold: String(format: "%.0f pt", arrivalThreshold),
            rawArrowXY: rawPlacement.map { formatPoint($0.point) } ?? "—",
            rawAngleDeg: rawPlacement.map { String(format: "%+.0f°", $0.angle * 180 / .pi) } ?? "—",
            smoothArrowXY: smoothedPlacement.map { formatPoint($0.point) } ?? formatPoint(searchArrow.position),
            smoothAngleDeg: smoothedPlacement.map { String(format: "%+.0f°", $0.angle * 180 / .pi) }
                ?? String(format: "%+.0f°", searchArrow.angle * 180 / .pi),
            arrowMode: rawMode.map { $0 == .onBody ? "onBody" : "edge" } ?? (searchArrow.mode == .onBody ? "onBody" : "edge"),
            arrowVisible: arrowVisible ? "yes" : "no",
            guidanceComplete: guidanceComplete ? "yes" : "no"
        )
    }

    func updateSearchGuidance() {
        guard selectionSource == .search else {
            if showSearchDebug {
                searchGuidanceDebug = .inactive
            }
            return
        }
        guard let bodyName = selectedBodyName,
              let body = bodies.first(where: { $0.name == bodyName }),
              viewportSize.width > 0, viewportSize.height > 0 else { return }

        let size = viewportSize
        let centerX = size.width / 2
        let centerY = size.height / 2
        let center = CGPoint(x: centerX, y: centerY)
        let arrivalThreshold = min(size.width, size.height) * 0.16
        let projectedTarget = bodyOverlays[bodyName]
        let relativeDegrees = compassRelativeBearingDegrees(to: body)

        if searchGuidanceComplete {
            let strictOnScreen = projectedTarget.map { isOnScreen($0, in: size) } ?? false
            let expandedOnScreen = projectedTarget.map { isOnScreen($0, in: size, margin: -Self.searchOnScreenExpansion) } ?? false
            let centerDistance = projectedTarget.map { hypot($0.x - centerX, $0.y - centerY) }
            refreshSearchGuidanceDebug(
                bodyName: bodyName,
                body: body,
                branch: "complete",
                relativeDegrees: relativeDegrees,
                adjustedRelative: nil,
                frontArcLockActive: false,
                projectedTarget: projectedTarget,
                strictOnScreen: strictOnScreen,
                expandedOnScreen: expandedOnScreen,
                centerDistance: centerDistance,
                arrivalThreshold: arrivalThreshold,
                rawPlacement: nil,
                smoothedPlacement: (searchArrow.position, searchArrow.angle),
                rawMode: searchArrow.mode,
                arrowVisible: searchArrow.isVisible,
                guidanceComplete: true
            )
            return
        }

        syncSearchPanDirection(
            relativeDegrees: relativeDegrees,
            projectedTarget: projectedTarget,
            centerX: centerX
        )

        let rawPlacement: (point: CGPoint, angle: Double)
        let rawMode: SearchArrowMode
        var shouldComplete = false
        var branch = "hidden"
        var adjustedRelative: Double?

        let strictOnScreen = projectedTarget.map { isOnScreen($0, in: size) } ?? false
        let expandedOnScreen = projectedTarget.map { isOnScreen($0, in: size, margin: -Self.searchOnScreenExpansion) } ?? false
        let centerDistance = projectedTarget.map { hypot($0.x - centerX, $0.y - centerY) }

        if let target = projectedTarget, expandedOnScreen {
            branch = "onBody"
            let distance = hypot(target.x - centerX, target.y - centerY)
            rawPlacement = offsetArrowPlacement(
                pointingTo: target,
                approachFrom: center,
                clearance: markerClearance(for: body)
            )
            rawMode = .onBody
            if distance < arrivalThreshold {
                shouldComplete = true
            }
        } else if let target = projectedTarget {
            branch = "arEdge"
            rawPlacement = edgeGuidancePlacement(toward: target, in: size, pointAtTarget: false)
            rawMode = .edge
        } else if let relativeDegrees {
            if let coarseTurn = resolveCoarseTurn(relativeDegrees: relativeDegrees) {
                branch = "compassCoarse(\(coarseTurn == .left ? "L" : "R"))"
                rawPlacement = coarseTurnPlacement(coarseTurn, in: size)
                rawMode = .edge
            } else {
                adjustedRelative = panLockedRelativeDegrees(
                    relativeDegrees,
                    projectedTarget: projectedTarget,
                    centerX: centerX
                )
                branch = "compassFine"
                rawPlacement = fineGuidancePlacement(relativeDegrees: adjustedRelative ?? relativeDegrees, in: size)
                rawMode = .edge
            }
        } else {
            searchArrow.isVisible = false
            refreshSearchGuidanceDebug(
                bodyName: bodyName,
                body: body,
                branch: "hidden (no heading)",
                relativeDegrees: nil,
                adjustedRelative: nil,
                frontArcLockActive: false,
                projectedTarget: projectedTarget,
                strictOnScreen: strictOnScreen,
                expandedOnScreen: expandedOnScreen,
                centerDistance: centerDistance,
                arrivalThreshold: arrivalThreshold,
                rawPlacement: nil,
                smoothedPlacement: nil,
                rawMode: nil,
                arrowVisible: false,
                guidanceComplete: false
            )
            return
        }

        let frontArcLockActive = relativeDegrees.map {
            shouldApplyFrontArcLock(
                relativeDegrees: $0,
                projectedTarget: projectedTarget,
                centerX: centerX
            )
        } ?? false

        let placement = smoothSearchArrowPlacement(rawPlacement)
        searchArrow.isVisible = !shouldComplete
        searchArrow.position = placement.point
        searchArrow.angle = placement.angle
        searchArrow.mode = rawMode

        refreshSearchGuidanceDebug(
            bodyName: bodyName,
            body: body,
            branch: branch,
            relativeDegrees: relativeDegrees,
            adjustedRelative: adjustedRelative,
            frontArcLockActive: frontArcLockActive,
            projectedTarget: projectedTarget,
            strictOnScreen: strictOnScreen,
            expandedOnScreen: expandedOnScreen,
            centerDistance: centerDistance,
            arrivalThreshold: arrivalThreshold,
            rawPlacement: rawPlacement,
            smoothedPlacement: placement,
            rawMode: rawMode,
            arrowVisible: !shouldComplete,
            guidanceComplete: shouldComplete
        )

        if shouldComplete {
            if !searchGuidanceComplete {
                searchTargetReached = true
            }
            searchGuidanceComplete = true
            searchInfoRevealed = true
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
                screenOffset: screenOffset
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
        lastViewMatrix = viewMatrix
        lastProjectionMatrix = projectionMatrix
        lastProjectionViewport = projectionViewport
        lastScreenOffset = projectionOffset

        lastSelectedBodyCameraZ = nil
        if selectionSource == .search,
           let bodyName = selectedBodyName,
           let body = bodies.first(where: { $0.name == bodyName }),
           let projection = project(
               azimuth: body.azimuth,
               altitude: body.altitude,
               viewMatrix: viewMatrix,
               projectionMatrix: projectionMatrix,
               viewportSize: projectionViewport,
               screenOffset: projectionOffset
           ) {
            lastSelectedBodyCameraZ = projection.cameraZ
        }

        var overlays: [String: CGPoint] = [:]

        for body in bodies where isBodyTypeShown(body) {
            guard let projection = project(
                azimuth: body.azimuth,
                altitude: body.altitude,
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                viewportSize: projectionViewport,
                screenOffset: projectionOffset
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
                maxJump: maxJump
            )
            futureSegments = buildTrajectorySegments(
                from: selectedTrajectorySamples.filter { $0.isFuture },
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                projectionViewport: projectionViewport,
                visibleViewport: viewportSize,
                screenOffset: projectionOffset,
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
                screenOffset: projectionOffset
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
                    screenOffset: projectionOffset
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

        updateSearchGuidance()
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
            if heading != nil, selectionSource == .search {
                updateSearchGuidance()
            }
        }
    }
}
