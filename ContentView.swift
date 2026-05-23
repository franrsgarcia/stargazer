import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StargazerModel
    @State private var showSearchSheet = false
    @State private var showVisibilitySheet = false
    @State private var searchQuery = ""

    var body: some View {
        ZStack {
            ARViewContainer()
                .ignoresSafeArea()

            skyOverlay
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            locationHeader
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomChrome
        }
        .sheet(isPresented: $showSearchSheet) {
            searchSheet
        }
        .sheet(isPresented: $showVisibilitySheet) {
            visibilitySheet
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 8) {
            if model.showInfoCard,
               let selected = model.bodies.first(where: { $0.name == model.selectedBodyName }) {
                infoCardContent(for: selected)
            }
            bottomMenuBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Sky overlay (AR annotations)

    @ViewBuilder
    private var skyOverlay: some View {
        ZStack {
            trajectoryView
                .allowsHitTesting(false)

            ForEach(model.bodies) { body in
                if model.shouldRenderMarker(for: body), let point = model.bodyOverlays[body.name] {
                    let isSelected = model.selectedBodyName == body.name

                    bodyMarker(for: body, isSelected: isSelected)
                        .position(point)
                        .onTapGesture {
                            model.toggleSelection(of: body)
                        }

                    if isSelected && model.showInfoCard {
                        bodyLabel(for: body)
                            .position(labelPosition(for: point, body: body, isSelected: isSelected))
                    }
                }
            }

            if model.showHorizon, model.horizonPoints.count > 1 {
                horizonOverlay
            }

            searchGuidanceArrow
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var horizonOverlay: some View {
        let pts = model.horizonPoints
        let screenCenterX = model.viewportSize.width / 2
        let labelY = horizonLabelYPosition(for: pts)
        let angle = horizonLineAngle(for: pts)

        smoothPath(from: pts)
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            .allowsHitTesting(false)

        Text("HORIZON")
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(Color(white: 0.78))
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(Color.white)
            .cornerRadius(3)
            .rotationEffect(.radians(angle))
            .position(x: screenCenterX, y: labelY)
            .allowsHitTesting(false)

        ForEach(model.cardinalMarkers) { marker in
            cardinalLabel(marker)
                .rotationEffect(.radians(marker.rotation))
                .position(marker.point)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Chrome (safe-area insets)

    private var locationHeader: some View {
        Text(model.locationLabel)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var bottomMenuBar: some View {
        HStack(spacing: 0) {
            bottomBarItem(title: "Search", systemImage: "magnifyingglass") {
                showSearchSheet = true
            }

            barDivider

            bottomBarItem(
                title: "AR",
                systemImage: model.showCameraFeed ? "camera.fill" : "circle.fill"
            ) {
                model.showCameraFeed.toggle()
            }

            barDivider

            bottomBarItem(title: "Hide/Show", systemImage: "eye") {
                showVisibilitySheet = true
            }
        }
        .modifier(FloatingMenuBarModifier())
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 26)
    }

    private func bottomBarItem(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            bottomBarLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func bottomBarLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
            Text(title)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Sheets

    private var visibilitySheet: some View {
        NavigationStack {
            List {
                visibilityRow(title: "Stars", isOn: $model.showStars)
                visibilityRow(title: "Planets", isOn: $model.showPlanets)
                visibilityRow(title: "Moon", isOn: $model.showMoon)
                visibilityRow(title: "Sun", isOn: $model.showSun)
                visibilityRow(title: "Horizon", isOn: $model.showHorizon)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Hide / Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showVisibilitySheet = false
                    }
                }
            }
        }
        .modifier(SheetGlassBackgroundModifier())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func visibilityRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
    }

    private var searchSheet: some View {
        NavigationStack {
            List {
                ForEach(filteredSearchNames, id: \.self) { name in
                    Button {
                        model.selectFromSearch(named: name)
                        showSearchSheet = false
                        searchQuery = ""
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            if let body = model.bodies.first(where: { $0.name == name }) {
                                Text(body.isVisible ? "Visible" : "Below horizon")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $searchQuery, prompt: "Find a celestial body")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSearchSheet = false
                    }
                }
            }
        }
        .modifier(SheetGlassBackgroundModifier())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var filteredSearchNames: [String] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return StargazerModel.searchableNames
        }
        return StargazerModel.searchableNames.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Info card

    @ViewBuilder
    private func infoCardContent(for selected: CelestialBody) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(selected.color)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(selected.name.prefix(1)))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(selected.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: true, vertical: true)
                        .lineLimit(1)
                    Text(selected.distanceText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: true, vertical: true)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: { /* info page navigation placeholder */ }) {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(8)
                }

                Button(action: { model.clearSelection() }) {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(8)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            }

            HStack(spacing: 10) {
                infoTile(iconName: "sunrise.fill", title: "Rise", value: model.selectedRiseText ?? "—")
                infoTile(iconName: "sunset.fill", title: "Set", value: model.selectedSetText ?? "—")
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .modifier(GlassPanelModifier(cornerRadius: 20))
    }

    private func infoTile(iconName: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: true, vertical: true)
                .lineLimit(1)
        }
        .padding(8)
        .modifier(GlassChipModifier(cornerRadius: 12))
    }

    // MARK: - Sky rendering helpers

    private func horizonLineAngle(for points: [CGPoint]) -> Double {
        let screenCenterX = model.viewportSize.width / 2

        for i in 0..<(points.count - 1) {
            if points[i].x <= screenCenterX && screenCenterX <= points[i + 1].x {
                let dx = points[i + 1].x - points[i].x
                let dy = points[i + 1].y - points[i].y
                return atan2(dy, dx)
            }
        }
        return 0.0
    }

    private func horizonLabelYPosition(for points: [CGPoint]) -> CGFloat {
        let screenCenterX = model.viewportSize.width / 2
        let defaultY = model.viewportSize.height / 2

        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max() else {
            return defaultY
        }

        guard screenCenterX >= minX && screenCenterX <= maxX else {
            return defaultY
        }

        for i in 0..<(points.count - 1) {
            if points[i].x <= screenCenterX && screenCenterX <= points[i + 1].x {
                let t = (screenCenterX - points[i].x) / (points[i + 1].x - points[i].x)
                return points[i].y + t * (points[i + 1].y - points[i].y)
            }
        }

        return defaultY
    }

    private func segmentOpacity(index: Int, totalCount: Int, baseOpacity: Double = 1.0) -> Double {
        let progress = Double(index) / Double(totalCount)
        let fadeInOpacity = progress < 0.2 ? progress / 0.2 : 1.0
        let fadeOutOpacity = (1.0 - progress) < 0.2 ? (1.0 - progress) / 0.2 : 1.0
        return min(fadeInOpacity, fadeOutOpacity) * baseOpacity
    }

    private func labelPosition(for markerPoint: CGPoint, body: CelestialBody, isSelected: Bool) -> CGPoint {
        let markerRadius = markerSize(for: body, isSelected: isSelected) / 2
        let horizontalOffset = markerRadius + 38

        let preferRight = markerPoint.x < model.viewportSize.width * 0.55
        let x = preferRight ? markerPoint.x + horizontalOffset : markerPoint.x - horizontalOffset
        return CGPoint(x: x, y: markerPoint.y)
    }

    @ViewBuilder
    private var trajectoryView: some View {
        if model.selectedBodyName != nil {
            ForEach(Array(model.pastTrajectorySegments.enumerated()), id: \.offset) { _, pts in
                trajectorySegments(pts, baseOpacity: 0.35, lineWidth: 1)
            }
            ForEach(Array(model.futureTrajectorySegments.enumerated()), id: \.offset) { _, pts in
                trajectorySegments(pts, baseOpacity: 1.0, lineWidth: 2)
            }
        }
    }

    @ViewBuilder
    private func trajectorySegments(_ pts: [CGPoint], baseOpacity: Double, lineWidth: CGFloat) -> some View {
        if pts.count > 1 {
            ForEach(0..<(pts.count - 1), id: \.self) { i in
                let start = pts[i]
                let end = pts[i + 1]
                let opacity = segmentOpacity(index: i, totalCount: pts.count, baseOpacity: baseOpacity)

                Path { path in
                    path.move(to: start)
                    path.addLine(to: end)
                }
                .stroke(Color.white.opacity(opacity), lineWidth: lineWidth)
            }
        }
    }

    private func markerSize(for body: CelestialBody, isSelected: Bool) -> CGFloat {
        switch body.type {
        case .sun: return isSelected ? 48 : 36
        case .moon: return isSelected ? 36 : 28
        case .planet: return isSelected ? 9 : 7
        }
    }

    @ViewBuilder
    private func bodyMarker(for body: CelestialBody, isSelected: Bool) -> some View {
        let isSun = body.type == .sun
        let isMoon = body.type == .moon
        let isPlanet = body.type == .planet
        let belowHorizon = !body.isAboveHorizon
        let size = markerSize(for: body, isSelected: isSelected)
        let tint = body.markerTint

        ZStack {
            if isPlanet {
                Circle()
                    .fill(tint.opacity(0.35))
                    .frame(width: size * 2.8, height: size * 2.8)
                    .blur(radius: 6)
            }

            Circle()
                .fill(tint.opacity(isSun || isMoon ? 0.95 : 0.92))
                .frame(width: size, height: size)
                .shadow(color: tint.opacity(isSun ? 0.9 : isMoon ? 0.75 : 0.65), radius: isSun ? 18 : isMoon ? 12 : 10)
                .shadow(color: tint.opacity(isPlanet ? 0.4 : 0.25), radius: isPlanet ? 16 : 8)
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .opacity(belowHorizon ? 0.55 : 1)
    }

    @ViewBuilder
    private func bodyLabel(for body: CelestialBody) -> some View {
        Text(body.displayLabel)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .fixedSize(horizontal: true, vertical: true)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .modifier(GlassChipModifier(cornerRadius: 8))
    }

    @ViewBuilder
    private var searchGuidanceArrow: some View {
        if model.searchArrow.isVisible {
            Image(systemName: "arrow.up")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.55), radius: 5)
                .rotationEffect(.radians(model.searchArrow.angle + .pi / 2))
                .position(model.searchArrow.position)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func cardinalLabel(_ marker: CardinalMarker) -> some View {
        Text(marker.label)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(marker.isNorth ? .white : Color(white: 0.82))
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, marker.isNorth ? 4 : 3)
            .padding(.vertical, 2)
            .background(marker.isNorth ? Color.red : Color.white.opacity(0.92))
            .cornerRadius(3)
    }

    private func smoothPath(from pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 0 else { return path }
        if pts.count == 1 {
            path.move(to: pts[0])
            return path
        }
        if pts.count == 2 {
            path.move(to: pts[0])
            path.addLine(to: pts[1])
            return path
        }

        path.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[i]
            let p1 = pts[i + 1]
            let mid = CGPoint(x: (p0.x + p1.x) / 2.0, y: (p0.y + p1.y) / 2.0)
            path.addQuadCurve(to: mid, control: p0)
        }
        if let last = pts.last, pts.count >= 2 {
            let penultimate = pts[pts.count - 2]
            path.addQuadCurve(to: last, control: penultimate)
        }
        return path
    }
}

// MARK: - Materials

private struct FloatingMenuBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
        }
    }
}

private struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        } else {
            content
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .cornerRadius(cornerRadius)
        }
    }
}

private struct GlassChipModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial)
                .cornerRadius(cornerRadius)
        }
    }
}

private struct SheetGlassBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect)
                        .ignoresSafeArea()
                }
        } else {
            content
                .background(.regularMaterial)
        }
    }
}
