//
//  ARViewContainer.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/5/25.
//

import SwiftUI
import ARKit
import RealityKit
import simd
import CoreImage
import Vision

struct ARViewContainer: UIViewRepresentable {
    let arView = ARView(frame: .zero)
    let normalThreshold: Float = 15.0 // Degrees threshold for normal comparison
    
    func makeUIView(context: Context) -> ARView {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = [.horizontal]
        config.sceneReconstruction = .meshWithClassification
        config.environmentTexturing = .automatic
        assignFrameSemantics(config: config)
        config.videoFormat = getVideoFormat(config: config)

        arView.session.run(config)
        arView.session.delegate = context.coordinator
        
        arView.debugOptions.insert(.showSceneUnderstanding)
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        arView.debugOptions.insert(.showStatistics)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(arView: arView)
    }
    
    private func getVideoFormat(config: ARWorldTrackingConfiguration) -> ARConfiguration.VideoFormat {
//        if let format = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
//            print("Using recommended video format: \(format)")
//            return format
//        }
        return config.videoFormat
    }
    
    private func assignFrameSemantics(config: ARWorldTrackingConfiguration) {
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        print("Supporting scene Depth: \(ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth))")
    }

    class Coordinator: NSObject, ARSessionDelegate {
        private weak var arView: ARView?
        var captureHighResFrames: Bool = true
        var imageSaver = ImageSaver()
        
        init(arView: ARView) {
            self.arView = arView
        }
        
        func session(_ arSession: ARSession, didUpdate frame: ARFrame) {
            
            if captureHighResFrames {
                // Capture high-resolution frame if needed
                arSession.captureHighResolutionFrame { (highResFrame, error) in
                    if let highResFrame = highResFrame {
                        // Process the captured frame
                        self.saveFrame(highResFrame)
                    }
                    if let error = error {
                        print("Error capturing high-res frame: \(error.localizedDescription)")
                    }
                }
//                self.saveFrame(frame)
                captureHighResFrames = false // Disable after first capture
            }
        }
        
        private func saveFrame(_ frame: ARFrame) {
            // Save the frame to a file or process it as needed
            if let image = frame.sceneDepth?.depthMap {
                let ciImage = CIImage(cvPixelBuffer: image)
                imageSaver.writeToPhotoAlbumUnbackedCIImage(image: ciImage)
            }
            else if let depthMap = frame.smoothedSceneDepth?.depthMap {
                print("Scene depth map not available.")
                let ciImage = CIImage(cvPixelBuffer: depthMap)
                imageSaver.writeToPhotoAlbumUnbackedCIImage(image: ciImage)
            }
            else {
                print("No depth map available in the frame.")
            }
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            handleMeshAnchors(anchors)
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            print("Number of anchors in arview: \(arView?.scene.anchors.count ?? 0)")
            handleMeshAnchors(anchors)
        }

        func handleMeshAnchors(_ anchors: [ARAnchor]) {
            let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
            for meshAnchor in meshAnchors {
                // Next step: Analyze this mesh anchor for height anomalies
                let geometry = meshAnchor.geometry

                let transform = meshAnchor.transform

//                _ = geometry.vertices
                let faces = geometry.faces
                let classifications = geometry.classification
                let normals = geometry.normals
                
                var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
                var triangleNormals: [SIMD3<Float>] = []

                if let classifications = classifications {
                    for index in 0..<faces.count {
                        // Each face is a triangle (3 indices)
                        let face = faces[index]
                        let classificationAddress = classifications.buffer.contents().advanced(by: classifications.offset + (classifications.stride * Int(index)))
                        let classificationValue = Int(classificationAddress.assumingMemoryBound(to: UInt8.self).pointee)
                        let classification = ARMeshClassification(rawValue: classificationValue) ?? .none
                        
                        // We're interested in floor-like horizontal surfaces
                        guard classification == .floor else { continue }
//                        
                        let v0 = worldVertex(at: Int(face[0]), geometry: geometry, transform: transform)
                        let v1 = worldVertex(at: Int(face[1]), geometry: geometry, transform: transform)
                        let v2 = worldVertex(at: Int(face[2]), geometry: geometry, transform: transform)
                        
                        // Optional: Use v0, v1, v2 to calculate the normal if you want to verify orientation
                        // Optional: Check if this triangle lies near the camera, under the user, etc.
                        
                        // Store, mark, or visualize these triangles as horizontal surface
                        // Change the color of the mesh
                        triangles.append((v0, v1, v2))
//                        
                        let edge1 = v1 - v0
                        let edge2 = v2 - v0
                        let normal = normalize(cross(edge1, edge2))
                        
//                        let originalNormalsAddress = normals.buffer.contents().advanced(by: normals.offset + (normals.stride * Int(index)))
//                        let originalNormal = originalNormalsAddress.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                        
//                        if (originalNormal.x > 1.0 || originalNormal.y > 1.0 || originalNormal.z > 1.0)
//                        {
//                            print("Original Normal: \(originalNormal)")
//                        }
                        
//                        let normalDifference = normalize(originalNormal - normal)
//                        print("Normal Difference: \(normalDifference)")
                        
                        triangleNormals.append(normal)
                    }
                }
                
                // Step 2: Compute mean normal
                guard !triangleNormals.isEmpty else { continue }
                let meanNormal = normalize(triangleNormals.reduce(SIMD3<Float>(0, 0, 0), +) / Float(triangleNormals.count))
//                print("Mean Normal: \(meanNormal)")
                
                // Step 3: Split triangles based on deviation
                let thresholdDegrees: Float = 15.0
                var normalTriangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
                var deviantTriangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
                
                for (i, triangle) in triangles.enumerated() {
                    let angleRad = acos(dot(triangleNormals[i], meanNormal))
                    let angleDeg = angleRad * (180.0 / .pi)
                    if angleDeg > thresholdDegrees {
                        deviantTriangles.append(triangle)
                    } else {
                        normalTriangles.append(triangle)
                    }
                }
//                print("Normal Triangles Count: \(normalTriangles.count)")
//                print("Deviant Triangles Count: \(deviantTriangles.count)")
                
                // Step 4: Visualize
                if let normalEntity = createHorizontalMeshEntity(triangles: normalTriangles, color: .green) {
                    let anchorEntity = AnchorEntity(world: .zero)
                    anchorEntity.addChild(normalEntity)
                    arView?.scene.addAnchor(anchorEntity)
                }

                if let deviantEntity = createHorizontalMeshEntity(triangles: deviantTriangles, color: .red) {
                    let anchorEntity = AnchorEntity(world: .zero)
                    anchorEntity.addChild(deviantEntity)
                    arView?.scene.addAnchor(anchorEntity)
                }
                
//                if let entity = createHorizontalMeshEntity(triangles: triangles) {
//                    let anchorEntity = AnchorEntity(world: .zero) // Or use meshAnchor.transform for relative
//                    anchorEntity.addChild(entity)
//                    arView?.scene.addAnchor(anchorEntity)
//                }
                
            }
//            print("Finished processing \(meshAnchors.count) mesh anchors.")
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
        
        func createHorizontalMeshEntity(
            triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)],
            color: UIColor = .green,
            opacity: Float = 0.4
        ) -> ModelEntity? {
            if (triangles.isEmpty) {
                return nil
            }
            
            var positions: [SIMD3<Float>] = []
            var indices: [UInt32] = []

            for (i, triangle) in triangles.enumerated() {
                let baseIndex = UInt32(i * 3)
                positions.append(triangle.0)
                positions.append(triangle.1)
                positions.append(triangle.2)
                indices.append(contentsOf: [baseIndex, baseIndex + 1, baseIndex + 2])
            }

            var meshDescriptors = MeshDescriptor(name: "HorizontalMesh")
            meshDescriptors.positions = MeshBuffers.Positions(positions)
            meshDescriptors.primitives = .triangles(indices)
            guard let mesh = try? MeshResource.generate(from: [meshDescriptors]) else {
                return nil
            }

            var material = UnlitMaterial(color: color.withAlphaComponent(CGFloat(opacity)))
            material.triangleFillMode = .lines
            let entity = ModelEntity(mesh: mesh, materials: [material])
            return entity
        }
    }
}
