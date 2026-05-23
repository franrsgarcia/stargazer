import SwiftUI
import Combine
import RealityKit
import ARKit

/// Fullscreen camera host — ARView fills edge-to-edge with aspect-fill cropping (no letterboxing).
final class FullscreenARContainerView: UIView {
    let arView: ARView
    var onViewportChange: ((CGSize) -> Void)?

    override init(frame: CGRect) {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .black
        addSubview(arView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutAspectFillCamera()
        onViewportChange?(bounds.size)
    }

    func setShowsCameraFeed(_ shows: Bool) {
        if shows {
            arView.environment.background = .cameraFeed()
        } else {
            arView.environment.background = .color(.black)
        }
    }

    /// Sizes ARView larger than bounds when needed so the camera feed crops like `.resizeAspectFill`.
    private func layoutAspectFillCamera() {
        guard bounds.width > 0, bounds.height > 0 else {
            arView.frame = bounds
            return
        }

        guard let frame = arView.session.currentFrame else {
            arView.frame = bounds
            return
        }

        // Camera buffer is landscape; portrait display swaps width/height for aspect ratio.
        let imageWidth = CGFloat(frame.camera.imageResolution.height)
        let imageHeight = CGFloat(frame.camera.imageResolution.width)
        guard imageWidth > 0, imageHeight > 0 else {
            arView.frame = bounds
            return
        }

        let contentAspect = imageWidth / imageHeight
        let viewAspect = bounds.width / bounds.height

        if viewAspect > contentAspect {
            let height = bounds.width / contentAspect
            arView.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        } else {
            let width = bounds.height * contentAspect
            arView.frame = CGRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject private var model: StargazerModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> FullscreenARContainerView {
        let container = FullscreenARContainerView(frame: .zero)
        container.onViewportChange = { [weak model] size in
            Task { @MainActor in
                model?.viewportSize = size
            }
        }

        guard ARWorldTrackingConfiguration.isSupported else {
            return container
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.environmentTexturing = .none
        configuration.planeDetection = []

        container.arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        context.coordinator.install(on: container)
        context.coordinator.lastCompassResetToken = model.compassResetToken
        return container
    }

    func updateUIView(_ uiView: FullscreenARContainerView, context: Context) {
        uiView.setShowsCameraFeed(model.showCameraFeed)
        if context.coordinator.lastCompassResetToken != model.compassResetToken {
            context.coordinator.lastCompassResetToken = model.compassResetToken
            context.coordinator.resetARSession(on: uiView)
        }
        uiView.setNeedsLayout()
    }

    static func dismantleUIView(_ uiView: FullscreenARContainerView, coordinator: Coordinator) {
        coordinator.stopObserving()
        uiView.arView.session.pause()
    }

    class Coordinator: NSObject, ARSessionDelegate {
        private let model: StargazerModel
        private var subscription: Cancellable?
        private weak var container: FullscreenARContainerView?
        private var lastCompassResetToken: UUID?

        init(model: StargazerModel) {
            self.model = model
        }

        func install(on container: FullscreenARContainerView) {
            self.container = container
            let arView = container.arView
            arView.session.delegate = self

            subscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self, weak container] _ in
                guard let self, let container else { return }
                guard let frame = container.arView.session.currentFrame else { return }
                container.setNeedsLayout()
                let viewSize = container.bounds.size
                let arViewFrame = container.arView.frame
                Task { @MainActor in
                    self.model.updateOverlays(from: frame, viewportSize: viewSize, arViewFrame: arViewFrame)
                }
            }
        }

        func stopObserving() {
            subscription?.cancel()
            subscription = nil
        }

        func resetARSession(on container: FullscreenARContainerView) {
            guard ARWorldTrackingConfiguration.isSupported else { return }

            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravityAndHeading
            configuration.environmentTexturing = .none
            configuration.planeDetection = []
            container.arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
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
