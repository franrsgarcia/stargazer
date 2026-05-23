import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StargazerModel

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
            if model.horizonPoints.count > 1 {
                Path { path in
                    let pts = model.horizonPoints
                    path.move(to: pts[0])
                    for p in pts.dropFirst() { path.addLine(to: p) }
                }
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 1)
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
