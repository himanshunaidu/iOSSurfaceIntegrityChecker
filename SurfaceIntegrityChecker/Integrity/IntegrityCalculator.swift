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
struct IntegrityStatusDetails {
    var status: IntegrityStatus
    var details: String
}

struct IntegrityResults {
    var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
    var triangleNormals: [SIMD3<Float>] = []
    var points: [(CGPoint, CGPoint, CGPoint)] = []
    var integrityStatus: IntegrityStatus = .intact
    
    var triangleColors: [UIColor] = []
    
    var meshIntegrityStatusDetails: IntegrityStatusDetails = IntegrityStatusDetails(status: .intact, details: "")
    var boundingBoxIntegrityStatusDetails: IntegrityStatusDetails = IntegrityStatusDetails(status: .intact, details: "")
    var boundingBoxMeshIntegrityStatusDetails: IntegrityStatusDetails = IntegrityStatusDetails(status: .intact, details: "")
    
    var plane: Plane? = nil
}

class IntegrityCalculator {
    private var connectedComponentsCalculator: ConnectedComponents = ConnectedComponents()
    private var planeFit: PlaneFit = PlaneFit()
    
    private var meshPlaneAngularDeviationThreshold: Float = 7.5 // degrees
    private var meshPlaneDeviantTriangleAreaPercentageThreshold: Float = 0.05 // 5%
    private var boundingBoxAreaThreshold: Float = 0.1 // m²
    private var boundingBoxMeshAngularStdThreshold: Float = 0.1 // radians
    
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
        var points: [(CGPoint, CGPoint, CGPoint)] = []
        
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
                    }
                    counts["kept", default: 0] += 1
                    
                    //
                    let edge1 = v1 - v0
                    let edge2 = v2 - v0
                    let normal = normalize(cross(edge1, edge2))
                    
                    let point = [v0, v1, v2].map {
                        projectWorldToPixel(
                            $0,
                            cameraTransform: cameraTransform,
                            intrinsics: cameraIntrinsics,
                            imageSize: segmentationLabelImage.extent.size) ?? CGPoint(x: -1, y: -1)
                    }
                    if (!validatePoint(point[0], in: segmentationLabelImage.extent.size) ||
                        !validatePoint(point[1], in: segmentationLabelImage.extent.size) ||
                        !validatePoint(point[2], in: segmentationLabelImage.extent.size)) {
                        continue
                    }
                    triangleNormals.append(normal)
                    triangles.append((v0, v1, v2))
                    points.append( (point[0], point[1], point[2]) )
                }
            }
        }
        
//        guard !triangleNormals.isEmpty else { return nil }
        var triangleColors: [UIColor] = triangles.map { _ in UIColor(red: 0.957, green: 0.137, blue: 0.910, alpha: 0.9) }
        let meshIntegrityResults = getMeshIntegrity(triangles, triangleColors: &triangleColors)
        let meshIntegrityDetails = meshIntegrityResults.integrityStatusDetails
        var boundingBoxIntegrityDetails: IntegrityStatusDetails? = nil
        var boundingBoxMeshIntegrityDetails: IntegrityStatusDetails? = nil
        if let damageDetectionResults = arResources.damageDetectionResults {
            let (boundingBoxTriangleIndices, boundingBoxMeshAreas, boundingBoxIntegrityDetailsWrapped) = getBoundingBoxIntegrity(
                points, triangles: triangles, damageDetectionResults: damageDetectionResults, triangleColors: &triangleColors
            )
            boundingBoxMeshIntegrityDetails = getBoundingBoxMeshIntegrity(
                triangles,
                boundingBoxTriangleIndices: boundingBoxTriangleIndices,
                boundingBoxMeshAreas: boundingBoxMeshAreas,
                damageDetectionResults: damageDetectionResults,
                triangleColors: &triangleColors
            )
            boundingBoxIntegrityDetails = boundingBoxIntegrityDetailsWrapped
        }
        
        var integrityStatus: IntegrityStatus = .intact
        if let meshIntegrityDetails = meshIntegrityDetails,
           meshIntegrityDetails.status == .compromised {
            integrityStatus = .compromised
        }
        if let boundingBoxIntegrityDetails = boundingBoxIntegrityDetails,
           boundingBoxIntegrityDetails.status == .compromised {
            integrityStatus = .compromised
        }
        if let boundingBoxMeshIntegrityDetails = boundingBoxMeshIntegrityDetails,
           boundingBoxMeshIntegrityDetails.status == .compromised {
            integrityStatus = .compromised
        }
        return IntegrityResults(
            triangles: triangles,
            triangleNormals: triangleNormals,
            points: points,
            integrityStatus: integrityStatus,
            triangleColors: triangleColors,
            meshIntegrityStatusDetails: meshIntegrityDetails ?? IntegrityStatusDetails(status: .intact, details: ""),
            boundingBoxIntegrityStatusDetails: boundingBoxIntegrityDetails ?? IntegrityStatusDetails(status: .intact, details: ""),
            boundingBoxMeshIntegrityStatusDetails: boundingBoxMeshIntegrityDetails ?? IntegrityStatusDetails(status: .intact, details: ""),
            plane: meshIntegrityResults.plane
        )
    }
    
    func getMeshIntegrity(_ triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)], triangleColors: inout [UIColor]) -> (plane: Plane?, integrityStatusDetails: IntegrityStatusDetails?) {
        var trianglePoints: [SIMD3<Float>] = []
        var triangleAreas: [Float] = []
        var deviantArea: Float = 0.0
        var totalArea: Float = 0.0
        
        for (_, triangle) in triangles.enumerated() {
            let (v0, v1, v2) = triangle
            let centroid = (v0 + v1 + v2) / 3.0
            trianglePoints.append(centroid)
            
            let area = length(cross(v1 - v0, v2 - v0)) / 2.0
            triangleAreas.append(area)
            totalArea += area
        }
        
        let plane: Plane? = planeFit.fitPlanePCA(trianglePoints, weights: triangleAreas)
        guard let plane else {
            print("Failed to fit a plane to the triangle centroids.")
            return (nil, nil)
        }
        
        var angularDeviations: [Float] = []
        for (index, triangle) in triangles.enumerated() {
            let (v0, v1, v2) = triangle
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = normalize(cross(edge1, edge2))
            
            let dotProduct = dot(normal, plane.n)
            let clampedDot = max(-1.0, min(1.0, dotProduct))
            let angleRad = acos(clampedDot)
            var angleDeg = angleRad * (180.0 / .pi)
            if angleDeg > 90 {
                angleDeg = 180 - angleDeg
            }
            angularDeviations.append(angleDeg)
            
            if angleDeg > meshPlaneAngularDeviationThreshold {
//                print("Deviation of triangle \(index) is \(angleDeg)°")
                triangleColors[index] = UIColor(red: 1.0, green: 0, blue: 0, alpha: 0.9)
                deviantArea += triangleAreas[index]
            }
        }
        
        let deviantAreaPercentage = deviantArea / totalArea
        let status = deviantAreaPercentage > meshPlaneDeviantTriangleAreaPercentageThreshold
//        let details: String = "Deviant area: \(String(format: "%.2f", deviantArea)) m²/ Total area: \(String(format: "%.2f", totalArea)) m²"
        let details: String = "Deviant \(String(format: "%.2f", deviantArea))/\(String(format: "%.2f", totalArea)) m²"
        let integrityStatusDetails = IntegrityStatusDetails(
            status: status ? .compromised : .intact,
            details: details
        )
        return (plane, integrityStatusDetails)
    }
    
    /**
     Also returns details for each bounding box:
        - boundingBoxTriangleIndices: [boundingBoxIndex: [triangleIndices]]
        - boundingBoxMeshAreas: [boundingBoxIndex: area]
     */
    func getBoundingBoxIntegrity(
        _ trianglePoints: [(CGPoint, CGPoint, CGPoint)],
        triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)],
        damageDetectionResults: [DamageDetectionResult],
        triangleColors: inout [UIColor]
    ) -> (boundingBoxTriangleIndices: [Int:[Int]], boundingBoxMeshAreas: [Int: Float], integrityStatusDetails: IntegrityStatusDetails?) {
        if triangles.count != trianglePoints.count {
            print("Mismatch in number of triangles and triangle points.")
            return ([:], [:], nil)
        }
        let boundingBoxes = damageDetectionResults.map { $0.boundingBox }
        var boundingBoxMeshAreas: [Int: Float] = [:]
        var boundingBoxTriangleIndices: [Int:[Int]] = [:]
        
        var triangleAreas: [Float] = []
        for (_, triangle) in triangles.enumerated() {
            let (v0, v1, v2) = triangle
            let area = length(cross(v1 - v0, v2 - v0)) / 2.0
            triangleAreas.append(area)
        }
        
        for (index, trianglePoint) in trianglePoints.enumerated() {
            let triangle = triangles[index]
            
            let triangleVertices = [trianglePoint.0, trianglePoint.1, trianglePoint.2].map { SIMD2<Float>(Float($0.x), Float($0.y)) }
            let centroid = (triangleVertices[0] + triangleVertices[1] + triangleVertices[2]) / 3.0
            let centroidPoint = CGPoint(x: CGFloat(centroid.x), y: CGFloat(centroid.y))
            
            for (bI, boundingBox) in boundingBoxes.enumerated() {
                if boundingBox.contains(centroidPoint) {
                    boundingBoxTriangleIndices[bI, default: []].append(index)
                    boundingBoxMeshAreas[bI, default: 0] += triangleAreas[index]
                    triangleColors[index] = UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.9)
                }
            }
        }
        
        var status: Bool = false
        var numDeviantBoxes: Int = 0
        for (bI, area) in boundingBoxMeshAreas {
            if area > boundingBoxAreaThreshold {
                status = true
                numDeviantBoxes += 1
            }
        }
        
//        let details = "Bounding Boxes: Total=\(boundingBoxes.count), Deviant=\(numDeviantBoxes) with area > \(boundingBoxAreaThreshold) m²"
        let details = "\(numDeviantBoxes) with area>\(boundingBoxAreaThreshold)m²"
        return (boundingBoxTriangleIndices, boundingBoxMeshAreas, IntegrityStatusDetails(
            status: status ? .compromised : .intact,
            details: details
        ))
    }
    
    func getBoundingBoxMeshIntegrity(
        _ triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)],
        boundingBoxTriangleIndices: [Int:[Int]],
        boundingBoxMeshAreas: [Int: Float],
        damageDetectionResults: [DamageDetectionResult],
        triangleColors: inout [UIColor]
    ) -> IntegrityStatusDetails? {
        var status: Bool = false
        var numDeviantBoxes: Int = 0
        for (bI, triangleIndices) in boundingBoxTriangleIndices {
            let boundingBox = damageDetectionResults[bI].boundingBox
            let meshArea = boundingBoxMeshAreas[bI, default: 0]
            
            let triangleNormals: [SIMD3<Float>] = triangleIndices.map { index in
                let (v0, v1, v2) = triangles[index]
                let edge1 = v1 - v0
                let edge2 = v2 - v0
                let normal = normalize(cross(edge1, edge2))
                return normal
            }
            let triangleNormalMean = triangleNormals.reduce(SIMD3<Float>(0,0,0), +) / Float(triangleNormals.count)
            let triangleNormalVariance = triangleNormals.map {
                length($0 - triangleNormalMean) * length($0 - triangleNormalMean)
            }.reduce(0, +) / Float(triangleNormals.count)
            
            let triangleNormalStdDev = sqrt(triangleNormalVariance)
            
            for (tI, triangleNormal) in triangleNormals.enumerated() {
                let deviation = length(triangleNormal - triangleNormalMean)
                if deviation > 2 * triangleNormalStdDev {
                    let index = triangleIndices[tI]
                    triangleColors[index] = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.9)
                }
            }
            
            if triangleNormalStdDev > boundingBoxMeshAngularStdThreshold {
                status = true
                numDeviantBoxes += 1
            }
        }
//        let details = "Bounding Boxes Mesh: Deviant=\(numDeviantBoxes) with angular std > \(String(format: "%.2f", boundingBoxMeshAngularStdThreshold)) radians"
        let details = "\(numDeviantBoxes) with std>\(String(format: "%.2f", boundingBoxMeshAngularStdThreshold)) rad"
        return IntegrityStatusDetails(
            status: status ? .compromised : .intact,
            details: details
        )
    }
    
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
    
    // Helper: Get world-space position of a vertex
    private func worldVertex(at index: Int, geometry: ARMeshGeometry, transform: simd_float4x4) -> SIMD3<Float> {
        let vertices = geometry.vertices
        let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (vertices.stride * Int(index)))
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
//            print("Vertex at index \(index): \(vertex)")
//            let vertex = geometry.vertices[index]
        let worldVertex4D = (transform * SIMD4(vertex.x, vertex.y, vertex.z, 1.0))
        return SIMD3(worldVertex4D.x, worldVertex4D.y, worldVertex4D.z)
    }
    
    private func projectWorldToPixel(_ world: simd_float3,
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
    
    private func sampleMask(_ pixelBuffer: CVPixelBuffer, at px: CGPoint,
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
    
    private func validatePoint(_ point: CGPoint, in size: CGSize) -> Bool {
        return point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height
    }
}
