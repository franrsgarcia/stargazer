import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StargazerModel

    var body: some View {
        ZStack {
            ARViewContainer()
                .edgesIgnoringSafeArea(.all)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.statusText)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(model.summaryText)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.88))
                    }
                    Spacer()
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding([.horizontal, .top], 16)

                Spacer()

                if model.bodies.isEmpty {
                    Text("Finding the sky... allow location access and point the camera at the sky.")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .padding(.horizontal, 16)
                }
            }

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

                ForEach(Array(model.trajectoryPoints.enumerated()), id: \.(offset)) { idx, p in
                    Circle()
                        .fill(selected.color.opacity(0.9))
                        .frame(width: 6, height: 6)
                        .position(p)
                }
            }
        }
    }
}
