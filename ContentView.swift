import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StargazerModel
    @State private var showSearchSheet = false
    @State private var searchQuery = ""

    private let bottomBarHeight: CGFloat = 56

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

    private func labelPosition(for markerPoint: CGPoint) -> CGPoint {
        let sideOffset: CGFloat = 30
        let preferRight = markerPoint.x < model.viewportSize.width * 0.62
        let x = preferRight ? markerPoint.x + sideOffset : markerPoint.x - sideOffset
        return CGPoint(x: x, y: markerPoint.y)
    }

    private func edgeArrowPlacement(toward target: CGPoint) -> (point: CGPoint, angle: Double) {
        let size = model.viewportSize
        let cx = size.width / 2
        let cy = size.height / 2
        let margin: CGFloat = 36
        var dx = target.x - cx
        var dy = target.y - cy

        if dx == 0 && dy == 0 {
            return (CGPoint(x: cx, y: margin), .pi / 2)
        }

        let halfW = max(size.width / 2 - margin, 1)
        let halfH = max(size.height / 2 - margin, 1)
        let scaleX = dx != 0 ? abs(halfW / dx) : .infinity
        let scaleY = dy != 0 ? abs(halfH / dy) : .infinity
        let scale = min(scaleX, scaleY)
        let edgeX = cx + dx * scale
        let edgeY = cy + dy * scale
        return (CGPoint(x: edgeX, y: edgeY), atan2(dy, dx))
    }

    @ViewBuilder
    private var trajectoryView: some View {
        if model.selectedBodyName != nil {
            if !model.pastTrajectoryPoints.isEmpty {
                let pts = model.pastTrajectoryPoints
                if pts.count > 1 {
                    ForEach(0..<(pts.count - 1), id: \.self) { i in
                        let start = pts[i]
                        let end = pts[i + 1]
                        let opacity = segmentOpacity(index: i, totalCount: pts.count, baseOpacity: 0.35)

                        Path { path in
                            path.move(to: start)
                            path.addLine(to: end)
                        }
                        .stroke(Color.white.opacity(opacity), lineWidth: 1)
                    }
                }
            }

            if !model.futureTrajectoryPoints.isEmpty {
                let pts = model.futureTrajectoryPoints
                if pts.count > 1 {
                    ForEach(0..<(pts.count - 1), id: \.self) { i in
                        let start = pts[i]
                        let end = pts[i + 1]
                        let opacity = segmentOpacity(index: i, totalCount: pts.count, baseOpacity: 1.0)

                        Path { path in
                            path.move(to: start)
                            path.addLine(to: end)
                        }
                        .stroke(Color.white.opacity(opacity), lineWidth: 2)
                    }
                }
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
            .background(.ultraThinMaterial)
            .cornerRadius(8)
    }

    @ViewBuilder
    private var searchGuidanceArrow: some View {
        if model.selectionSource == .search,
           let name = model.selectedBodyName,
           let body = model.bodies.first(where: { $0.name == name }),
           let target = model.bodyOverlays[body.id],
           model.searchArrowOpacity > 0.02 {
            let placement = edgeArrowPlacement(toward: target)

            Image(systemName: "arrow.up")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .rotationEffect(.radians(placement.angle + .pi / 2))
                .position(placement.point)
                .opacity(model.searchArrowOpacity)
                .animation(.easeInOut(duration: 0.25), value: model.searchArrowOpacity)
                .allowsHitTesting(false)
        }
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

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                ARViewContainer()
                    .edgesIgnoringSafeArea(.all)

                trajectoryView
                    .allowsHitTesting(false)

                ForEach(model.bodies) { body in
                    if model.shouldRenderMarker(for: body), let point = model.bodyOverlays[body.id] {
                        let isSelected = model.selectedBodyID == body.id

                        bodyMarker(for: body, isSelected: isSelected)
                            .position(point)
                            .onTapGesture {
                                model.toggleSelection(of: body)
                            }

                        if isSelected && (model.selectionSource == .tap || model.searchInfoOpacity > 0.35) {
                            bodyLabel(for: body)
                                .position(labelPosition(for: point))
                        }
                    }
                }

                if model.showHorizon, model.horizonPoints.count > 1 {
                    let pts = model.horizonPoints
                    smoothPath(from: pts)
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)

                    let screenCenterX = size.width / 2
                    let labelY = horizonLabelYPosition(for: pts)
                    let angle = horizonLineAngle(for: pts)

                    Text("HORIZON")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(white: 0.78))
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.white)
                        .cornerRadius(4)
                        .rotationEffect(.radians(angle))
                        .position(x: screenCenterX, y: labelY)
                        .allowsHitTesting(false)
                }

                searchGuidanceArrow

                if model.showInfoCard,
                   let selected = model.bodies.first(where: { $0.name == model.selectedBodyName }) {
                    infoCard(for: selected, bottomInset: bottomBarHeight + geometry.safeAreaInsets.bottom)
                        .opacity(model.selectionSource == .search ? model.searchInfoOpacity : 1)
                        .animation(.easeInOut(duration: 0.25), value: model.searchInfoOpacity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomMenuBar
            }
            .onAppear {
                model.viewportSize = size
            }
            .onChange(of: size) { newSize in
                model.viewportSize = newSize
            }
        }
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showSearchSheet) {
            searchSheet
        }
    }

    private var bottomMenuBar: some View {
        HStack(spacing: 0) {
            bottomBarItem(title: "Search", systemImage: "magnifyingglass") {
                showSearchSheet = true
            }

            Divider()
                .frame(height: 28)
                .background(Color.white.opacity(0.2))

            bottomBarItem(
                title: "AR",
                systemImage: model.showCameraFeed ? "camera.fill" : "circle.fill"
            ) {
                model.showCameraFeed.toggle()
            }

            Divider()
                .frame(height: 28)
                .background(Color.white.opacity(0.2))

            Menu {
                Toggle("Stars", isOn: $model.showStars)
                Toggle("Planets", isOn: $model.showPlanets)
                Toggle("Moon", isOn: $model.showMoon)
                Toggle("Sun", isOn: $model.showSun)
                Toggle("Horizon", isOn: $model.showHorizon)
            } label: {
                bottomBarLabel(title: "Hide/Show", systemImage: "eye")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.white.opacity(0.12)), alignment: .top)
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
                .font(.system(size: 18, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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
        .presentationDetents([.medium, .large])
    }

    private var filteredSearchNames: [String] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return StargazerModel.searchableNames
        }
        return StargazerModel.searchableNames.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private func infoCard(for selected: CelestialBody, bottomInset: CGFloat) -> some View {
        VStack {
            Spacer()
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
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.06), lineWidth: 1))
            .cornerRadius(20)
            .padding(.horizontal, 12)
            .padding(.bottom, bottomInset + 12)
        }
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
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(12)
    }
}
