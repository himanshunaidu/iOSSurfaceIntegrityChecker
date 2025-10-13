//
//  AnchorIntegrityCalculator.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/28/25.
//

import Foundation
import ARKit

enum IntegrityStatus: CaseIterable, Identifiable, CustomStringConvertible {
    var id: Self { self }
    
    case intact
    case compromised
    
    var description: String {
        switch self {
        case .intact:
            return "The surface is intact."
        case .compromised:
            return "The surface has integrity issues."
        }
    }
}

struct IntegrityResults {
    var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
    var triangleNormals: [SIMD3<Float>] = []
    var integrityStatus: IntegrityStatus = .intact
}

class IntegrityCalculator {
    private var connectedComponentsCalculator: ConnectedComponents = ConnectedComponents()
    
    func calculateIntegrity(of meshBundle: MeshBundle) -> Bool {
        let deviantMesh = meshBundle.redEntity.model?.mesh
        guard let deviantMesh else {
            print("No mesh found for the red entity.")
            return false
        }
        
        let connectedComponents = connectedComponentsCalculator.getConnectedComponents(deviantMesh)
//        print("Areas of connected components: \(connectedComponents.map { $0.totalArea })")
        let totalArea = connectedComponents.reduce(0, { $0 + $1.totalArea})
        
        return totalArea > 0.1
    }
    
    func getIntegrityResults(_ arResources: MeshBundle) -> IntegrityResults? {
        guard let segmentationLabelImage = arResources.segmentationLabelImage,
              let cameraTransform = arResources.cameraTransform,
              let cameraIntrinsics = arResources.cameraIntrinsics
        else {
            return nil
        }
        
        guard let segmentationPixelBuffer = segmentationLabelImage.pixelBuffer else {
            print("Segmentation label image does not have underlying pixel buffer")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(segmentationPixelBuffer, .readOnly)
        let width = CVPixelBufferGetWidth(segmentationPixelBuffer)
        let height = CVPixelBufferGetHeight(segmentationPixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(segmentationPixelBuffer)
        defer { CVPixelBufferUnlockBaseAddress(segmentationPixelBuffer, .readOnly) }
        
        let meshAnchors = arResources.meshAnchors
        
        var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        var triangleNormals: [SIMD3<Float>] = []
        
        var uniqueValueFrequencies: [UInt8: Int] = [:]
        var counts = ["total": 0, "projectFailed": 0, "sampleFailed": 0, "classMismatch": 0, "kept": 0]
        
        for meshAnchor in meshAnchors {
            // Next step: Analyze this mesh anchor for height anomalies
            let geometry = meshAnchor.geometry
            //            let id = meshAnchor.identifier
            
            let faces = geometry.faces
            let classifications = geometry.classification
            
            let transform = meshAnchor.transform
            
            if let classifications = classifications {
                for index in 0..<faces.count {
                    // Randomly skip some faces to reduce load
                    //                        if Int.random(in: 0..<10) < 5 { continue }
                    
                    // Each face is a triangle (3 indices)
                    let face = faces[index]
                    let classificationAddress = classifications.buffer.contents().advanced(by: classifications.offset + (classifications.stride * Int(index)))
                    let classificationValue = Int(classificationAddress.assumingMemoryBound(to: UInt8.self).pointee)
                    let classification = ARMeshClassification(rawValue: classificationValue) ?? .none
                    
                    // We're interested in floor-like horizontal surfaces
                    //                    guard classification == .floor else { continue }
                    //
                    let v0 = worldVertex(at: Int(face[0]), geometry: geometry, transform: transform)
                    let v1 = worldVertex(at: Int(face[1]), geometry: geometry, transform: transform)
                    let v2 = worldVertex(at: Int(face[2]), geometry: geometry, transform: transform)
                    
                    // MARK: If the triangle centroid corresponds to a segmentation pixel that has value in selectionClasses, keep it
                    let c = (v0 + v1 + v2) / 3.0
                    counts["total", default: 0] += 1
                    guard let px = projectWorldToPixel(
                        c,
                        cameraTransform: cameraTransform,
                        intrinsics: cameraIntrinsics,
                        imageSize: segmentationLabelImage.extent.size) else {
                        counts["projectFailed", default: 0] += 1
                        continue
                    }
                    guard let value = sampleMask(
                        segmentationPixelBuffer, at: px,
                        width: width, height: height, bytesPerRow: bpr) else {
                        //                        print("Failed to sample mask at pixel \(px)")
                        counts["sampleFailed", default: 0] += 1
                        continue
                    }
                    uniqueValueFrequencies[value, default: 0] += 1
                    // MARK: Hard-code the match for now
                    if value != 1 {
                        //                        print("Skipping triangle at \(px) with label \(value)")
                        counts["classMismatch", default: 0] += 1
                        continue
                    } else {
                    }
                    counts["kept", default: 0] += 1
                    
                    triangles.append((v0, v1, v2))
                    //
                    let edge1 = v1 - v0
                    let edge2 = v2 - v0
                    let normal = normalize(cross(edge1, edge2))
                    
                    triangleNormals.append(normal)
                }
            }
        }
        
        guard !triangleNormals.isEmpty else { return nil }
        
        return IntegrityResults(
            triangles: triangles,
            triangleNormals: triangleNormals,
            integrityStatus: .intact
        )
    }
    
    // Helper: Get world-space position of a vertex
    func worldVertex(at index: Int, geometry: ARMeshGeometry, transform: simd_float4x4) -> SIMD3<Float> {
        let vertices = geometry.vertices
        let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (vertices.stride * Int(index)))
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
//            print("Vertex at index \(index): \(vertex)")
//            let vertex = geometry.vertices[index]
        let worldVertex4D = (transform * SIMD4(vertex.x, vertex.y, vertex.z, 1.0))
        return SIMD3(worldVertex4D.x, worldVertex4D.y, worldVertex4D.z)
    }
    
    func projectWorldToPixel(_ world: simd_float3,
                             cameraTransform: simd_float4x4, // ARCamera.transform (camera->world)
                             intrinsics K: simd_float3x3,
                             imageSize: CGSize) -> CGPoint? {
        // world -> camera
        let view = simd_inverse(cameraTransform)              // world->camera
        let p4   = simd_float4(world, 1.0)
        let pc   = view * p4                                  // camera space
        let x = pc.x, y = pc.y, z = pc.z
        
        guard z < 0 else {
            return nil
        }                       // behind camera
        
        // normalized image plane coords (flip Y so +Y goes up in pixels)
        let xn = x / -z
        let yn = -y / -z
        
        // intrinsics (column-major)
        let fx = K.columns.0.x
        let fy = K.columns.1.y
        let cx = K.columns.2.x
        let cy = K.columns.2.y
        
        // pixels in sensor/native image coordinates
        let u = fx * xn + cx
        let v = fy * yn + cy
        
        if u.isFinite && v.isFinite &&
            u >= 0 && v >= 0 &&
            u < Float(imageSize.width) && v < Float(imageSize.height) {
            return CGPoint(x: CGFloat(u.rounded()), y: CGFloat(v.rounded()))
        }
        return nil
    }
    
    func sampleMask(_ pixelBuffer: CVPixelBuffer, at px: CGPoint,
                    width: Int, height: Int, bytesPerRow: Int
    ) -> UInt8? {
        let w = width
        let h = height
        let bpr = bytesPerRow

        let ix = Int(px.x), iy = Int(px.y)
        guard ix >= 0, iy >= 0, ix < w, iy < h else {
            return nil
        }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let value = ptr[iy * bpr + ix]
        return value
    }
}
