import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StargazerModel

    private func horizonLineAngle(for points: [CGPoint]) -> Double {
        let screenCenterX = UIScreen.main.bounds.midX
        
        // Find the two points that straddle the screen center
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
        let screenCenterX = UIScreen.main.bounds.midX
        let defaultY = UIScreen.main.bounds.midY
        
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max() else {
            return defaultY
        }
        
        guard screenCenterX >= minX && screenCenterX <= maxX else {
            return defaultY
        }
        
        // Find the segment that contains screenCenterX
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

    @ViewBuilder
    private var trajectoryView: some View {
        if model.bodies.first(where: { $0.id == model.selectedBodyID }) != nil {
            // Past trajectory with fade-out at both ends
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

            // Future trajectory with fade-out at both ends
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

            if isSelected {
                Text(body.displayLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }

    // Produce a smooth path from a series of points using quadratic segments
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
        // finish to last point
        if let last = pts.last, pts.count >= 2 {
            let penultimate = pts[pts.count - 2]
            path.addQuadCurve(to: last, control: penultimate)
        }
        return path
    }

    var body: some View {
        ZStack {
            ARViewContainer()
                .edgesIgnoringSafeArea(.all)

            // Top status box removed; AR content fills the view.

            trajectoryView
                .allowsHitTesting(false)

            ForEach(model.bodies) { body in
                if let point = model.bodyOverlays[body.id], body.isVisible {
                    let isSelected = model.selectedBodyID == body.id

                    bodyMarker(for: body, isSelected: isSelected)
                        .position(point)
                        .onTapGesture {
                            model.toggleSelection(of: body)
                        }
                }
            }

            // Draw horizon reference line
            if model.showHorizon, model.horizonPoints.count > 1 {
                let pts = model.horizonPoints
                smoothPath(from: pts)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)

                // Horizon label: centered horizontally, moves vertically with the horizon line, rotates with it
                let screenCenterX = UIScreen.main.bounds.midX
                let labelY = horizonLabelYPosition(for: pts)
                let angle = horizonLineAngle(for: pts)
                
                Text("HORIZON")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.78))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.white)
                    .cornerRadius(4)
                    .rotationEffect(.radians(angle))
                    .position(x: screenCenterX, y: labelY)
            }

            // Horizon toggle button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { model.showHorizon.toggle() }) {
                        Image(systemName: model.showHorizon ? "eye" : "eye.slash")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 14)
                }
                Spacer()
            }

            // Bottom info card for selected body
            if let selected = model.bodies.first(where: { $0.id == model.selectedBodyID }) {
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
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(selected.distanceText)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }

                            Spacer()

                            Button(action: { /* info page navigation placeholder */ }) {
                                Image(systemName: "info.circle")
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(8)
                            }

                            Button(action: { model.toggleSelection(of: selected) }) {
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
                    .padding(.bottom, 10)
                }
                .animation(.easeInOut, value: model.selectedBodyID)
            }
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(12)
    }
}
