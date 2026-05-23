import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StargazerModel

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

            if !model.trajectoryPoints.isEmpty, let selected = model.bodies.first(where: { $0.id == model.selectedBodyID }) {
                Path { path in
                    let pts = model.trajectoryPoints
                    guard pts.count > 1 else { return }
                    path.move(to: pts[0])
                    for p in pts.dropFirst() { path.addLine(to: p) }
                }
                .stroke(selected.color, lineWidth: 2)

                ForEach(Array(model.trajectoryPoints.enumerated()), id: \.offset) { idx, p in
                    Circle()
                        .fill(selected.color.opacity(0.9))
                        .frame(width: 6, height: 6)
                        .position(p)
                }
            }

            // Draw horizon reference line
            if model.showHorizon, model.horizonPoints.count > 1 {
                let pts = model.horizonPoints
                smoothPath(from: pts)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

                // Horizon label placed at midpoint of the horizon samples, vertically centered on the line
                let midIndex = pts.count / 2
                if midIndex < pts.count {
                    let labelPoint = pts[midIndex]
                    Text("HORIZON")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.25))
                        .cornerRadius(10)
                        .position(x: labelPoint.x, y: labelPoint.y)
                }
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
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center) {
                            Circle()
                                .fill(selected.color)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selected.name)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(selected.typeName)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            Spacer()
                            Button(action: { model.toggleSelection(of: selected) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }

                        Text(selected.descriptionText)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))

                        Text(selected.distanceText)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.95))
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(14)
                    .padding([.horizontal, .bottom], 16)
                }
                .animation(.easeInOut, value: model.selectedBodyID)
            }
        }
    }
}
