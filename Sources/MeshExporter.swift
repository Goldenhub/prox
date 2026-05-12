import ARKit
import ModelIO
import MetalKit

struct MeshData {
    let vertices: [Float]
    let normals: [Float]
    let indices: [UInt32]
    let transform: simd_float4x4
    let anchorID: UUID
}

struct MeshExporter {

    static func extractMeshData(from anchor: ARMeshAnchor) -> MeshData {
        let geometry = anchor.geometry

        var vertices = [Float]()
        var normals = [Float]()
        var indices = [UInt32]()

        autoreleasepool {
            let vCount = geometry.vertices.count
            let vStride = geometry.vertices.stride
            let vPtr = geometry.vertices.buffer.contents().assumingMemoryBound(to: Float.self)

            vertices.reserveCapacity(vCount * 3)
            for i in 0..<vCount {
                let off = i * vStride / MemoryLayout<Float>.stride
                let pos = simd_float4(vPtr[off], vPtr[off + 1], vPtr[off + 2], 1)
                let world = anchor.transform * pos
                vertices.append(world.x)
                vertices.append(world.y)
                vertices.append(world.z)
            }

            let nCount = geometry.normals.count
            let nStride = geometry.normals.stride
            let nPtr = geometry.normals.buffer.contents().assumingMemoryBound(to: Float.self)

            normals.reserveCapacity(vCount * 3)
            for i in 0..<vCount {
                if i < nCount {
                    let off = i * nStride / MemoryLayout<Float>.stride
                    let dx = nPtr[off], dy = nPtr[off + 1], dz = nPtr[off + 2]
                    let len = sqrt(dx * dx + dy * dy + dz * dz)
                    if len > 0 {
                        normals.append(dx / len)
                        normals.append(dy / len)
                        normals.append(dz / len)
                    } else {
                        normals.append(0); normals.append(1); normals.append(0)
                    }
                } else {
                    normals.append(0); normals.append(1); normals.append(0)
                }
            }

            let fCount = geometry.faces.count
            let bpi = geometry.faces.bytesPerIndex
            let fPtr = geometry.faces.buffer.contents()

            indices.reserveCapacity(fCount * 3)
            for i in 0..<fCount * 3 {
                let off = i * bpi
                switch bpi {
                case 4:  indices.append(fPtr.load(fromByteOffset: off, as: UInt32.self))
                case 2:  indices.append(UInt32(fPtr.load(fromByteOffset: off, as: UInt16.self)))
                default: indices.append(UInt32(fPtr.load(fromByteOffset: off, as: UInt8.self)))
                }
            }
        }

        return MeshData(vertices: vertices, normals: normals, indices: indices,
                        transform: anchor.transform, anchorID: anchor.identifier)
    }

    static func exportUSDZ(meshes: [MeshData]) -> (url: URL?, errors: [String]) {
        let asset = MDLAsset()
        var errors = [String]()

        for mesh in meshes {
            guard mesh.vertices.count >= 9 else {
                errors.append("Anchor \(mesh.anchorID): too few vertices")
                continue
            }
            guard mesh.indices.count >= 3 else {
                errors.append("Anchor \(mesh.anchorID): no face indices")
                continue
            }

            let vCount = mesh.vertices.count / 3

            var interleaved = [Float]()
            interleaved.reserveCapacity(vCount * 6)
            for i in 0..<vCount {
                let vi = i * 3
                interleaved.append(mesh.vertices[vi])
                interleaved.append(mesh.vertices[vi + 1])
                interleaved.append(mesh.vertices[vi + 2])
                interleaved.append(mesh.normals[vi])
                interleaved.append(mesh.normals[vi + 1])
                interleaved.append(mesh.normals[vi + 2])
            }

            let vbData = Data(bytes: interleaved,
                              count: interleaved.count * MemoryLayout<Float>.stride)
            let ibData = Data(bytes: mesh.indices,
                              count: mesh.indices.count * MemoryLayout<UInt32>.stride)

            let vb = MDLMeshBufferData(type: .vertex, data: vbData)
            let ib = MDLMeshBufferData(type: .index, data: ibData)

            let desc = MDLVertexDescriptor()
            desc.attributes[0] = MDLVertexAttribute(
                name: MDLVertexAttributePosition,
                format: .float3, offset: 0, bufferIndex: 0)
            desc.attributes[1] = MDLVertexAttribute(
                name: MDLVertexAttributeNormal,
                format: .float3, offset: 12, bufferIndex: 0)
            desc.layouts[0] = MDLVertexBufferLayout(stride: 24)

            let submesh = MDLSubmesh(
                indexBuffer: ib,
                indexCount: mesh.indices.count,
                indexType: .uInt32,
                geometryType: .triangles,
                material: nil)

            let mdlMesh = MDLMesh(
                vertexBuffer: vb,
                vertexCount: vCount,
                descriptor: desc,
                submeshes: [submesh])

            asset.add(mdlMesh)
        }

        guard asset.count > 0 else {
            errors.append("No meshes could be processed")
            return (nil, errors)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomScan_\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("usdz")

        do {
            try asset.export(to: url)
            return (url, errors)
        } catch {
            errors.append("USDZ export failed: \(error.localizedDescription)")
            return (nil, errors)
        }
    }
}
