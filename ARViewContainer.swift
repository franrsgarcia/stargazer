import SwiftUI
import Combine
import RealityKit
import ARKit

/// Hosts an ARView that fills the screen edge-to-edge (aspect fill, no letterboxing).
final class FullscreenARContainerView: UIView {
    let arView: ARView
    var onViewportChange: ((CGSize) -> Void)?

    override init(frame: CGRect) {
        arView = ARView(frame: frame)
        arView.automaticallyConfigureSession = false
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
        arView.frame = bounds
        applyAspectFillTransform()
        onViewportChange?(bounds.size)
    }

    func applyAspectFillTransformIfNeeded() {
        applyAspectFillTransform()
    }

    private func applyAspectFillTransform() {
        guard bounds.width > 0, bounds.height > 0 else {
            arView.layer.transform = CATransform3DIdentity
            return
        }

        guard let frame = arView.session.currentFrame else {
            arView.layer.transform = CATransform3DIdentity
            return
        }

        // Camera buffer is landscape; portrait effective size swaps dimensions.
        let imageWidth = CGFloat(frame.camera.imageResolution.height)
        let imageHeight = CGFloat(frame.camera.imageResolution.width)
        guard imageWidth > 0, imageHeight > 0 else {
            arView.layer.transform = CATransform3DIdentity
            return
        }

        let scale = max(bounds.width / imageWidth, bounds.height / imageHeight)
        arView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        arView.layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        arView.layer.transform = CATransform3DMakeScale(Float(scale), Float(scale), 1)
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
        return container
    }

    func updateUIView(_ uiView: FullscreenARContainerView, context: Context) {
        if model.showCameraFeed {
            uiView.arView.environment.background = .cameraFeed()
        } else {
            uiView.arView.environment.background = .color(.black)
        }
        uiView.applyAspectFillTransformIfNeeded()
    }

    static func dismantleUIView(_ uiView: FullscreenARContainerView, coordinator: Coordinator) {
        coordinator.stopObserving()
        uiView.arView.session.pause()
    }

    class Coordinator: NSObject, ARSessionDelegate {
        private let model: StargazerModel
        private var subscription: Cancellable?
        private weak var container: FullscreenARContainerView?

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
                container.applyAspectFillTransformIfNeeded()
                let viewSize = container.bounds.size
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
