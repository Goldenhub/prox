import ARKit
import SceneKit

struct MeshData {
    let vertices: [Float]
    let normals: [Float]
    let indices: [UInt32]
    let vertexCount: Int
    let faceCount: Int
    let anchorID: UUID
    let transform: simd_float4x4
}

struct MeshExporter {

    static func extractMeshData(from anchor: ARMeshAnchor) -> MeshData {
        let geometry = anchor.geometry

        var vertices = [Float]()
        var normals = [Float]()
        var indices = [UInt32]()

        let vCount = geometry.vertices.count
        let vStride = geometry.vertices.stride
        let vPtr = geometry.vertices.buffer.contents().assumingMemoryBound(to: Float.self)

        vertices.reserveCapacity(vCount * 3)
        for i in 0..<vCount {
            let off = i * vStride / MemoryLayout<Float>.stride
            var x = vPtr[off], y = vPtr[off + 1], z = vPtr[off + 2]
            if !x.isFinite { x = 0 }
            if !y.isFinite { y = 0 }
            if !z.isFinite { z = 0 }
            vertices.append(x)
            vertices.append(y)
            vertices.append(z)
        }

        let nCount = geometry.normals.count
        let nStride = geometry.normals.stride
        let nPtr = geometry.normals.buffer.contents().assumingMemoryBound(to: Float.self)

        normals.reserveCapacity(vCount * 3)
        for i in 0..<vCount {
            if i < nCount {
                let off = i * nStride / MemoryLayout<Float>.stride
                var dx = nPtr[off], dy = nPtr[off + 1], dz = nPtr[off + 2]
                if !dx.isFinite { dx = 0 }
                if !dy.isFinite { dy = 0 }
                if !dz.isFinite { dz = 0 }
                let len = sqrt(dx * dx + dy * dy + dz * dz)
                if len > 0 { dx /= len; dy /= len; dz /= len }
                normals.append(dx); normals.append(dy); normals.append(dz)
            } else {
                normals.append(0); normals.append(1); normals.append(0)
            }
        }

        let fCount = geometry.faces.count
        let bpi = geometry.faces.bytesPerIndex
        let fPtr = geometry.faces.buffer.contents()

        var rawIndices = [UInt32]()
        let totalIndices = geometry.faces.buffer.length / bpi
        rawIndices.reserveCapacity(totalIndices)
        for i in 0..<totalIndices {
            let off = i * bpi
            switch bpi {
            case 4:  rawIndices.append(fPtr.load(fromByteOffset: off, as: UInt32.self))
            case 2:  rawIndices.append(UInt32(fPtr.load(fromByteOffset: off, as: UInt16.self)))
            default: rawIndices.append(UInt32(fPtr.load(fromByteOffset: off, as: UInt8.self)))
            }
        }

        indices = Array(rawIndices.prefix(fCount * 3))

        for idx in indices {
            if idx >= UInt32(vCount) {
                indices = []
                break
            }
        }

        return MeshData(vertices: vertices, normals: normals, indices: indices,
                        vertexCount: vCount, faceCount: fCount,
                        anchorID: anchor.identifier, transform: anchor.transform)
    }

    static func exportUSDZ(meshes: [MeshData]) -> (url: URL?, errors: [String]) {
        let scene = SCNScene()
        var errors = [String]()

        for mesh in meshes {
            print("[MeshExporter] anchor=\(mesh.anchorID) v=\(mesh.vertexCount) f=\(mesh.faceCount) idx=\(mesh.indices.count)")

            guard mesh.vertices.count >= 9 else {
                errors.append("Anchor \(mesh.anchorID): too few vertices"); continue
            }
            guard mesh.indices.count >= 3 else {
                errors.append("Anchor \(mesh.anchorID): no face indices"); continue
            }

            let vCount = mesh.vertices.count / 3

            var verts = [SCNVector3]()
            verts.reserveCapacity(vCount)
            var norms = [SCNVector3]()
            norms.reserveCapacity(vCount)
            for i in 0..<vCount {
                let vi = i * 3
                verts.append(SCNVector3(mesh.vertices[vi], mesh.vertices[vi+1], mesh.vertices[vi+2]))
                norms.append(SCNVector3(mesh.normals[vi], mesh.normals[vi+1], mesh.normals[vi+2]))
            }

            let vertexSource = SCNGeometrySource(vertices: verts)
            let normalSource = SCNGeometrySource(normals: norms)

            let indexData = Data(bytes: mesh.indices,
                                 count: mesh.indices.count * MemoryLayout<UInt32>.stride)
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: mesh.indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.stride)

            let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0.8, alpha: 1.0)
            material.isDoubleSided = true
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.simdTransform = mesh.transform
            scene.rootNode.addChildNode(node)
        }

        guard scene.rootNode.childNodes.count > 0 else {
            errors.append("No meshes could be processed")
            return (nil, errors)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomScan_\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("usdz")

        let success = scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
        if success {
            return (url, errors)
        } else {
            errors.append("USDZ export failed via SCNScene")
            return (nil, errors)
        }
    }
}
