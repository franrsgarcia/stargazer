import SwiftUI
import Combine
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject private var model: StargazerModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        guard ARWorldTrackingConfiguration.isSupported else {
            return arView
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.environmentTexturing = .none
        configuration.planeDetection = []

        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        context.coordinator.install(on: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if model.showCameraFeed {
            uiView.environment.background = .cameraFeed()
        } else {
            uiView.environment.background = .color(.black)
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.stopObserving()
        uiView.session.pause()
    }

    class Coordinator: NSObject, ARSessionDelegate {
        private let model: StargazerModel
        private var subscription: Cancellable?

        init(model: StargazerModel) {
            self.model = model
        }

        func install(on arView: ARView) {
            arView.session.delegate = self
            subscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self, weak arView] _ in
                guard let self = self, let arView = arView, let frame = arView.session.currentFrame else { return }
                let modelSize = self.model.viewportSize
                let viewSize: CGSize
                if modelSize.width > 0, modelSize.height > 0 {
                    viewSize = modelSize
                } else {
                    viewSize = arView.bounds.size
                }
                Task { @MainActor in
                    self.model.updateOverlays(from: frame, viewportSize: viewSize)
                }
            }
        }

        func stopObserving() {
            subscription?.cancel()
            subscription = nil
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            DispatchQueue.main.async {
                self.model.statusText = "AR session failed: \(error.localizedDescription)"
            }
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .normal:
                break
            case .notAvailable:
                DispatchQueue.main.async {
                    self.model.statusText = "AR camera not available"
                }
            case .limited(let reason):
                DispatchQueue.main.async {
                    self.model.statusText = "AR tracking limited: \(reason)"
                }
            }
        }
    }
}
