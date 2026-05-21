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
                    VStack(spacing: 4) {
                        Circle()
                            .fill(body.color)
                            .frame(width: 12, height: 12)
                            .shadow(radius: 3)
                        Text(body.displayLabel)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(body.color.opacity(0.24))
                            .cornerRadius(10)
                    }
                    .position(point)
                    .shadow(radius: 4)
                }
            }
        }
    }
}
