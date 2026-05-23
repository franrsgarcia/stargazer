import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StargazerModel

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
        if let selected = model.bodies.first(where: { $0.id == model.selectedBodyID }) {
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
                        .stroke(selected.color.opacity(opacity), lineWidth: 1)
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
                        .stroke(selected.color.opacity(opacity), lineWidth: 2)
                    }
                }
            }
        }
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

            ForEach(model.bodies) { body in
                if let point = model.bodyOverlays[body.id], body.isVisible {
                    let isSelected = model.selectedBodyID == body.id
                    ZStack {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(body.color)
                                .frame(width: isSelected ? 18 : 12, height: isSelected ? 18 : 12)
                                .shadow(radius: 3)
                            Text(body.displayLabel)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(body.color.opacity(0.24))
                                .cornerRadius(10)
                        }
                        .shadow(radius: 4)
                    }
                    .position(point)
                    .onTapGesture {
                        model.toggleSelection(of: body)
                    }
                }
            }

            trajectoryView

            // Draw horizon reference line
            if model.showHorizon, model.horizonPoints.count > 1 {
                let pts = model.horizonPoints
                smoothPath(from: pts)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

                // Horizon label: centered horizontally, moves vertically with the horizon line
                let screenCenterX = UIScreen.main.bounds.midX
                let labelY = horizonLabelYPosition(for: pts)
                
                Text("HORIZON")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.black.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(6)
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
                    VStack(spacing: 16) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)

                        HStack(alignment: .top, spacing: 16) {
                            Circle()
                                .fill(selected.color)
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Text(String(selected.name.prefix(1)))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 6) {
                                Text(selected.name)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(selected.descriptionText)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(2)
                            }

                            Spacer()

                            Button(action: { model.toggleSelection(of: selected) }) {
                                Image(systemName: "xmark")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(10)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Circle())
                            }
                        }

                        HStack(spacing: 12) {
                            infoTile(iconName: "arrow.up.right.circle", title: "Distance", value: selected.distanceText)
                            infoTile(iconName: "star.fill", title: "Magnitude", value: selected.magnitudeText)
                            infoTile(iconName: "eye", title: "Visible", value: selected.visibleUntilText)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(24)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .animation(.easeInOut, value: model.selectedBodyID)
            }
        }
    }

    private func infoTile(iconName: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.85))
                Text(title.uppercased())
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
            }
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(16)
    }
}
