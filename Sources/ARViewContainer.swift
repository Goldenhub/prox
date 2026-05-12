import SwiftUI
import RealityKit
import ARKit
import CoreVideo

struct PlacedMarker: Identifiable {
    let id = UUID()
    let position: SIMD3<Float>
    let distance: Float?
}

extension simd_float4x4 {
    var position: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var distance: Float?
    @Binding var confidence: Int?
    @Binding var placedMarkers: [PlacedMarker]
    var onCaptureDistance: (() -> Void)?

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: UIScreen.main.bounds)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView
        confidence = nil

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

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

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.syncMarkers(placedMarkers, uiView: uiView)
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(distance: $distance, confidence: $confidence, placedMarkers: $placedMarkers)
        c.onCaptureDistance = onCaptureDistance
        return c
    }

    class Coordinator: NSObject, ARSessionDelegate {
        @Binding var distance: Float?
        @Binding var confidence: Int?
        @Binding var placedMarkers: [PlacedMarker]
        var onCaptureDistance: (() -> Void)?
        weak var arView: ARView?
        var rootAnchor = AnchorEntity(world: .zero)
        var lastMarkerCount = 0

        init(distance: Binding<Float?>, confidence: Binding<Int?>, placedMarkers: Binding<[PlacedMarker]>) {
            self._distance = distance
            self._confidence = confidence
            self._placedMarkers = placedMarkers
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            let point = recognizer.location(in: arView)
            let arH = arView.bounds.height
            if point.y > arH - 260 {
                onCaptureDistance?()
                return
            }
            let results = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any)
            guard let hit = results.first else { return }

            let pos = hit.worldTransform.position
            let prev = placedMarkers.last?.position
            let dist: Float? = prev.map { length(pos - $0) }

            placedMarkers.append(PlacedMarker(position: pos, distance: dist))
            HapticManager.impact(.light)

            let sphere = makeSphereEntity()
            sphere.position = pos
            rootAnchor.addChild(sphere)

            if let prev = prev, let d = dist, d > 0.001 {
                let line = makeLineEntity(from: prev, to: pos)
                rootAnchor.addChild(line)
            }
        }

        func syncMarkers(_ markers: [PlacedMarker], uiView: ARView) {
            guard markers.count != lastMarkerCount else { return }

            rootAnchor.children.removeAll()
            lastMarkerCount = 0

            for (i, marker) in markers.enumerated() {
                let sphere = makeSphereEntity()
                sphere.position = marker.position
                rootAnchor.addChild(sphere)

                if i > 0 {
                    let prev = markers[i - 1].position
                    let line = makeLineEntity(from: prev, to: marker.position)
                    rootAnchor.addChild(line)
                }
            }
            lastMarkerCount = markers.count

            if !rootAnchor.isAnchored {
                uiView.scene.addAnchor(rootAnchor)
            }
        }

        private func makeSphereEntity() -> ModelEntity {
            let mesh = MeshResource.generateSphere(radius: 0.012)
            let material = SimpleMaterial(color: .systemBlue, isMetallic: true)
            return ModelEntity(mesh: mesh, materials: [material])
        }

        private func makeLineEntity(from: SIMD3<Float>, to: SIMD3<Float>) -> ModelEntity {
            let direction = to - from
            let distance = length(direction)
            guard distance > 0.001 else { return ModelEntity() }
            let mid = (from + to) / 2

            let mesh = MeshResource.generateCylinder(height: distance, radius: 0.003)
            let material = SimpleMaterial(color: .white, isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = mid

            let up = SIMD3<Float>(0, 1, 0)
            let dir = normalize(direction)
            entity.orientation = simd_quatf(from: up, to: dir)

            return entity
        }

        func sessionWasInterrupted(_ session: ARSession) {
            DispatchQueue.main.async { self.distance = nil }
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            guard let arView = arView else { return }
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
                if let confidenceMap = depthData.confidenceMap {
                    CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
                    let confPtr = CVPixelBufferGetBaseAddress(confidenceMap)?.assumingMemoryBound(to: UInt8.self)
                    let confBytes = CVPixelBufferGetBytesPerRow(confidenceMap)
                    if let confPtr {
                        let confVal = confPtr[dy * confBytes + dx]
                        confidence = Int(confVal)
                    }
                    CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
                }
            } else {
                distance = nil
                confidence = nil
            }
        }

        private func clampPixelCoord(_ value: Int, maximum: Int) -> Int {
            return min(max(value, 0), maximum)
        }
    }
}
