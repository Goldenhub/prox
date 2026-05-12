import SwiftUI
import RealityKit
import ARKit
import CoreVideo

struct ARViewContainer: UIViewRepresentable {
    @Binding var distance: Float?

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: UIScreen.main.bounds)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.smoothedSceneDepth, .sceneDepth]
        config.isLightEstimationEnabled = false
        config.providesAudioData = false

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        arView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(distance: $distance)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        @Binding var distance: Float?
        weak var arView: ARView?

        init(distance: Binding<Float?>) {
            self._distance = distance
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth,
                  let arView = arView else {
                distance = nil
                return
            }

            let depthMap = depthData.depthMap
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)

            guard width > 0, height > 0 else {
                distance = nil
                return
            }

            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

            guard let base = CVPixelBufferGetBaseAddress(depthMap) else {
                distance = nil
                return
            }

            let viewCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let viewSize = arView.bounds.size
            guard viewSize.width > 0, viewSize.height > 0 else {
                distance = nil
                return
            }

            let normalized = CGPoint(x: viewCenter.x / viewSize.width,
                                     y: viewCenter.y / viewSize.height)
            let transform = frame.displayTransform(for: .portrait, viewportSize: viewSize)
            let imagePoint = normalized.applying(transform)

            let dx = clampPixelCoord(Int(imagePoint.x * CGFloat(width)), maximum: width - 1)
            let dy = clampPixelCoord(Int(imagePoint.y * CGFloat(height)), maximum: height - 1)

            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)

            let val: Float32
            if pixelFormat == kCVPixelFormatType_DepthFloat32 {
                val = base.load(fromByteOffset: dy * bytesPerRow + dx * 4, as: Float32.self)
            } else {
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                val = Float32(ptr[dy * bytesPerRow + dx]) / 255.0 * 5.0
            }

            if val.isFinite && val > 0.1 {
                distance = val
            } else {
                distance = nil
            }
        }

        private func clampPixelCoord(_ value: Int, maximum: Int) -> Int {
            return min(max(value, 0), maximum)
        }
    }
}
