//
//  ARViewControllerContainer.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/26/25.
//

import SwiftUI
import RealityKit
import ARKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

struct ARViewControllerContainer: UIViewControllerRepresentable {
    /// Normalized ROI in top-left UIKit coordinates (0...1)
    var roiTopLeft: CGRect
    var overlaySize: CGSize
    var showDebug: Bool = false
    
    func makeUIViewController(context: Context) -> ARHostViewController {
        let vc = ARHostViewController()
        vc.roiTopLeft = roiTopLeft
        vc.overlaySize = overlaySize
        vc.showDebug = showDebug
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ARHostViewController, context: Context) {
        uiViewController.roiTopLeft = roiTopLeft
        uiViewController.overlaySize = overlaySize
        uiViewController.showDebug = showDebug
        uiViewController.applyOverlayLayoutIfNeeded()
        uiViewController.applyDebugIfNeeded()
    }
    
    static func dismantleUIViewController(_ uiViewController: ARHostViewController, coordinator: ()) {
        uiViewController.pauseSession()
    }
}

private struct MeshBundle {
    let anchorEntity: AnchorEntity
    var greenEntity: ModelEntity
    var redEntity: ModelEntity
    var lastUpdated: TimeInterval
    var aabbCenter: SIMD3<Float> = .zero
    var aabbExtents: SIMD3<Float> = .zero
    
    var faceCount: Int = 0
    var meanNormal: SIMD3<Float> = .zero
    var assignedColor: UIColor = .green
}

final class ARHostViewController: UIViewController, ARSessionDelegate {
    
    // MARK: - Public knobs (updated by the Representable)
    var roiTopLeft: CGRect = CGRect(x: 0.60, y: 0.08, width: 0.32, height: 0.32) // normalized TL
    var overlaySize: CGSize = CGSize(width: 160, height: 160)
    var showDebug: Bool = true
    
    // MARK: - Views
    private let arView: ARView = {
        let v = ARView(frame: .zero)
        v.automaticallyConfigureSession = false
        return v
    }()
    private let overlayImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = UIColor(white: 0, alpha: 0.35)
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    // MARK: - Processing
    private let ciContext = CIContext()
    private let processQueue = DispatchQueue(label: "ar.host.process.queue")
    private var lastProcess = Date.distantPast
    var minInterval: TimeInterval = 0.10 // throttle ~10 FPS for the overlay
    
    private var floorBundle: MeshBundle?
    private let updateInterval: TimeInterval = 0.033
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(arView)
        arView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        arView.addSubview(overlayImageView)
        applyOverlayLayoutIfNeeded()
        applyDebugIfNeeded()

        arView.session.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("ARHostViewController will appear; starting session.")
        runSessionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("ARHostViewController will disappear; pausing session.")
        pauseSession()
    }

    deinit {
        pauseSession()
    }
    
    // MARK: - Session control
    func runSessionIfNeeded() {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        arView.session.run(config, options: [])
    }
    
    func pauseSession() {
        arView.session.delegate = nil
        arView.session.pause()
    }
    
    // MARK: - Layout / debug
    func applyOverlayLayoutIfNeeded() {
        NSLayoutConstraint.deactivate(overlayImageView.constraints)
        // Pin to top-trailing with given size and padding
        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            overlayImageView.widthAnchor.constraint(equalToConstant: overlaySize.width),
            overlayImageView.heightAnchor.constraint(equalToConstant: overlaySize.height),
            overlayImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: pad),
            overlayImageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -pad)
        ])
    }

    func applyDebugIfNeeded() {
        if showDebug {
            arView.debugOptions.insert(.showStatistics)
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        } else {
            arView.debugOptions.remove(.showStatistics)
            arView.environment.sceneUnderstanding.options.remove(.occlusion)
        }
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 1) Feed mesh handling (anchors are updated in separate callbacks too)
        // (Optional to keep light—can be removed if you only need the overlay)
        // NOP here; mesh work is in didAdd/didUpdate anchors

        // 2) Produce overlay image with throttling
//        let now = Date()
//        guard now.timeIntervalSince(lastProcess) >= minInterval else { return }
//        lastProcess = now
//
//        let pixelBuffer = frame.capturedImage
//        let exif = exifOrientationForCurrentDevice()
//        processQueue.async { [weak self] in
//            self?.processOverlay(pixelBuffer: pixelBuffer, exifOrientation: exif)
//        }
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        handleMeshAnchors(anchors)
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        handleMeshAnchors(anchors)
    }
    
    // MARK: - Overlay pipeline
    private func processOverlay(pixelBuffer: CVPixelBuffer, exifOrientation: CGImagePropertyOrientation) {
        autoreleasepool {
            // Orient into display space
            let base = CIImage(cvPixelBuffer: pixelBuffer).oriented(exifOrientation)
            let extent = base.extent  // pixel space, origin bottom-left

            // Convert normalized TL ROI -> CI bottom-left pixel rect
            let tl = roiTopLeft
            let crop = CGRect(
                x: tl.minX * extent.width,
                y: (1.0 - tl.maxY) * extent.height,
                width: tl.width * extent.width,
                height: tl.height * extent.height
            ).integral

            let cropped = base.cropped(to: crop)

            // Example post-processing (Edges)
            let edges = CIFilter.edges()
            edges.inputImage = cropped
            edges.intensity = 1.5
            let output = edges.outputImage ?? cropped

            guard let cg = ciContext.createCGImage(output, from: output.extent) else { return }
            let ui = UIImage(cgImage: cg)

            DispatchQueue.main.async { [weak self] in
                self?.overlayImageView.image = ui
            }
        }
    }

    private func exifOrientationForCurrentDevice() -> CGImagePropertyOrientation {
        // If you lock to portrait + back camera, returning .right is enough.
        switch UIDevice.current.orientation {
        case .landscapeLeft:  return .up
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        default:              return .right // portrait (back camera)
        }
    }
    
    func generateRandomColor() -> UIColor {
        let red = CGFloat(arc4random_uniform(256)) / 255.0
        let green = CGFloat(arc4random_uniform(256)) / 255.0
        let blue = CGFloat(arc4random_uniform(256)) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    func handleMeshAnchors(_ anchors: [ARAnchor]) {
        if floorBundle == nil {
            let anchorEntity = AnchorEntity(world: .zero)
            let greenEntity = ModelEntity()
            let redEntity = ModelEntity()
            
            greenEntity.name = "GreenMesh"
            redEntity.name = "RedMesh"
            
            anchorEntity.addChild(greenEntity)
            anchorEntity.addChild(redEntity)
            
            arView.scene.addAnchor(anchorEntity)
            let assignedColor = generateRandomColor()
            
            floorBundle = MeshBundle(anchorEntity: anchorEntity, greenEntity: greenEntity, redEntity: redEntity, lastUpdated: 0, assignedColor: assignedColor)
        }
        
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        
        var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        var triangleNormals: [SIMD3<Float>] = []
        
        for meshAnchor in meshAnchors {
            // Next step: Analyze this mesh anchor for height anomalies
            let geometry = meshAnchor.geometry
            let id = meshAnchor.identifier
            
            // Throttle updates per anchor
            if Date().timeIntervalSince1970 - (floorBundle?.lastUpdated ?? 0) < updateInterval { continue }

//                _ = geometry.vertices
            let faces = geometry.faces
            let classifications = geometry.classification
            let normals = geometry.normals
            
            let transform = meshAnchor.transform
            
//                triangleNormals.reserveCapacity(faces.count)

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
                    guard classification == .floor else { continue }
//
                    let v0 = worldVertex(at: Int(face[0]), geometry: geometry, transform: transform)
                    let v1 = worldVertex(at: Int(face[1]), geometry: geometry, transform: transform)
                    let v2 = worldVertex(at: Int(face[2]), geometry: geometry, transform: transform)
                    
                    triangles.append((v0, v1, v2))
//
                    let edge1 = v1 - v0
                    let edge2 = v2 - v0
                    let normal = normalize(cross(edge1, edge2))
                    
                    triangleNormals.append(normal)
                }
            }
        }
//            print("Finished processing \(meshAnchors.count) mesh anchors.")
        // Step 2: Compute mean normal
        guard !triangleNormals.isEmpty else { return }
        
        let meanNormal = normalize(triangleNormals.reduce(SIMD3<Float>(0, 0, 0), +) / Float(triangleNormals.count))
        
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
        if let normalEntity = createHorizontalMeshEntity(triangles: normalTriangles, color: .green, name: "GreenMesh") {
//                    let anchorEntity = AnchorEntity(world: .zero)
//                    anchorEntity.addChild(normalEntity)
//                    arView?.scene.addAnchor(anchorEntity)
            floorBundle?.greenEntity.model = normalEntity.model
        }

        if let deviantEntity = createHorizontalMeshEntity(triangles: deviantTriangles, color: .red,
            name: "RedMesh") {
//                    let anchorEntity = AnchorEntity(world: .zero)
//                    anchorEntity.addChild(deviantEntity)
//                    arView?.scene.addAnchor(anchorEntity)
            floorBundle?.redEntity.model = deviantEntity.model
        }
        
//                if let entity = createHorizontalMeshEntity(triangles: triangles) {
//                    let anchorEntity = AnchorEntity(world: .zero) // Or use meshAnchor.transform for relative
//                    anchorEntity.addChild(entity)
//                    arView?.scene.addAnchor(anchorEntity)
//                }
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
        opacity: Float = 0.4,
        name: String = "HorizontalMesh"
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

        var meshDescriptors = MeshDescriptor(name: name)
        meshDescriptors.positions = MeshBuffers.Positions(positions)
        meshDescriptors.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [meshDescriptors]) else {
            return nil
        }

        var material = UnlitMaterial(color: color.withAlphaComponent(CGFloat(opacity)))
        material.triangleFillMode = .fill
        let entity = ModelEntity(mesh: mesh, materials: [material])
        return entity
    }
}
