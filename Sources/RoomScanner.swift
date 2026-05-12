import SwiftUI
import RealityKit
import ARKit

struct RoomScanner: UIViewRepresentable {
    @Binding var meshAnchors: [ARMeshAnchor]

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.environmentTexturing = .automatic
        config.frameSemantics = [.smoothedSceneDepth, .sceneDepth]
        config.isLightEstimationEnabled = true
        config.providesAudioData = false

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }

        arView.session.run(config)

        arView.environment.sceneUnderstanding.options.insert(.receivesLighting)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(meshAnchors: $meshAnchors)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        @Binding var meshAnchors: [ARMeshAnchor]
        weak var arView: ARView?

        init(meshAnchors: Binding<[ARMeshAnchor]>) {
            self._meshAnchors = meshAnchors
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            let newAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
            meshAnchors.append(contentsOf: newAnchors)
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
                if let idx = meshAnchors.firstIndex(where: { $0.identifier == meshAnchor.identifier }) {
                    meshAnchors[idx] = meshAnchor
                }
            }
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            let removed = Set(anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier })
            meshAnchors.removeAll { removed.contains($0.identifier) }
        }
    }
}
