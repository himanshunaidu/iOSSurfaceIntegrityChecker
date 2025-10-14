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
    var arResourceUpdateCallback: (MeshBundle?, Bool) -> Void
    var locationManager: LocationManager = LocationManager()
    @Binding var shouldCallResourceUpdateCallback: Bool
    
    func makeUIViewController(context: Context) -> ARHostViewController {
        let vc = ARHostViewController()
        vc.roiTopLeft = roiTopLeft
        vc.overlaySize = overlaySize
        vc.showDebug = showDebug
        vc.shouldCallResourceUpdateCallback = shouldCallResourceUpdateCallback
        vc.arResourceUpdateCallback = arResourceUpdateCallback
        vc.locationManager = locationManager
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ARHostViewController, context: Context) {
        uiViewController.roiTopLeft = roiTopLeft
        uiViewController.overlaySize = overlaySize
        uiViewController.showDebug = showDebug
        uiViewController.arResourceUpdateCallback = arResourceUpdateCallback
        uiViewController.shouldCallResourceUpdateCallback = shouldCallResourceUpdateCallback
        // The following layouts should not be re-applied every update
//        uiViewController.applyOverlayLayoutIfNeeded()
//        uiViewController.applyDamageOverlayLayoutIfNeeded()
        uiViewController.applyDebugIfNeeded()
    }
    
    static func dismantleUIViewController(_ uiViewController: ARHostViewController, coordinator: ()) {
        print("Dismantling ARHostViewController")
        uiViewController.pauseSession()
    }
}

struct MeshBundle {
    var meshAnchors: [ARMeshAnchor] = []
    
    let anchorEntity: AnchorEntity
    var greenEntity: ModelEntity
    var redEntity: ModelEntity
    var fullEntity: ModelEntity?
    var lastUpdated: TimeInterval
    var aabbCenter: SIMD3<Float> = .zero
    var aabbExtents: SIMD3<Float> = .zero
    
    var faceCount: Int = 0
    var meanNormal: SIMD3<Float> = .zero
    var assignedColor: UIColor = .green
    
    var cameraTransform: simd_float4x4?
    var cameraIntrinsics: simd_float3x3?
    var cameraImage: CIImage?
    var depthBuffer: CVPixelBuffer?
    var confidenceBuffer: CVPixelBuffer?
    var location: CLLocation?
    var orientation: CGImagePropertyOrientation = .right // default to portrait (back camera)
    
    var segmentationLabelImage: CIImage?
    var damageDetectionResults: [DamageDetectionResult]?
}

final class ARHostViewController: UIViewController, ARSessionDelegate {
    
    // MARK: - Public knobs (updated by the Representable)
    var roiTopLeft: CGRect = CGRect(x: 0.60, y: 0.08, width: 0.32, height: 0.32) // normalized TL
    var overlaySize: CGSize = CGSize(width: 160, height: 160)
    var showDebug: Bool = true
    var arResourceUpdateCallback: ((MeshBundle?, Bool) -> Void)?
    var locationManager: LocationManager?
    var shouldCallResourceUpdateCallback: Bool = true
    
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
    private let damageOverlayImageView: UIImageView = {
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
    private let segmentationFrameProcessor: SegmentationFrameProcessor = SegmentationFrameProcessor()
    private let selectionClasses = [0]
    private var segmentationLabelImage: CIImage?
    private var cameraTransform: simd_float4x4?
    private var cameraIntrinsics: simd_float3x3?
    
    private let damageDetectionFrameProcessor: DamageDetectionFrameProcessor = DamageDetectionFrameProcessor()
    
    private let ciContext = CIContext()
    private let processQueue = DispatchQueue(label: "ar.host.process.queue")
    private var lastProcess = Date.distantPast
    var minInterval: TimeInterval = 0.10 // throttle ~10 FPS for the overlay
    
    private var floorBundle: MeshBundle?
    private let updateInterval: TimeInterval = 0.033
    
//    private var integrityCalculator: IntegrityCalculator = IntegrityCalculator()
    
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
        arView.addSubview(damageOverlayImageView)
        applyDamageOverlayLayoutIfNeeded()
        applyDebugIfNeeded()
        
//        arView.addSubview(analyzeButton)
//        analyzeButton.translatesAutoresizingMaskIntoConstraints = false
//
//        NSLayoutConstraint.activate([
//            analyzeButton.trailingAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
//            analyzeButton.bottomAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.bottomAnchor, constant: -16)
//        ])

        arView.session.delegate = self
        segmentationFrameProcessor.setSelectionClasses(self.selectionClasses)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        runSessionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pauseSession()
    }

    deinit {
        pauseSession()
    }
    
    // MARK: - Session control
    func runSessionIfNeeded() {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
//        config.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        arView.session.run(config, options: [])
    }
    
    func pauseSession() {
        print("Pausing AR session")
        arView.session.delegate = nil
        arView.session.pause()
    }
    
    // MARK: - Layout / debug
    func applyOverlayLayoutIfNeeded() {
        NSLayoutConstraint.deactivate(overlayImageView.constraints)
        // Pin to top-trailing with given size and padding
//        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            overlayImageView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
//            overlayImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//            overlayImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            overlayImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    func applyDamageOverlayLayoutIfNeeded() {
        NSLayoutConstraint.deactivate(damageOverlayImageView.constraints)
        // Pin to top-trailing with given size and padding
//        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            damageOverlayImageView.topAnchor.constraint(equalTo: view.topAnchor),
            damageOverlayImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
//            damageOverlayImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//            damageOverlayImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            damageOverlayImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    func applyDebugIfNeeded() {
        if showDebug {
//            arView.debugOptions.insert(.showStatistics)
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
//            arView.debugOptions.remove(.showStatistics)
            arView.environment.sceneUnderstanding.options.remove(.occlusion)
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 1) Feed mesh handling (anchors are updated in separate callbacks too)
        // (Optional to keep light—can be removed if you only need the overlay)
        // NOP here; mesh work is in didAdd/didUpdate anchors

        // 2) Produce overlay image with throttling
        let now = Date()
        guard now.timeIntervalSince(lastProcess) >= minInterval else { return }
        lastProcess = now
//
        let pixelBuffer = frame.capturedImage
        let exif: CGImagePropertyOrientation = exifOrientationForCurrentDevice()
        
        let cIImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cameraTransform = frame.camera.transform
        let cameraIntrinsics = frame.camera.intrinsics
        
        let depthBuffer = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap
        
        let depthConfidenceBuffer = frame.sceneDepth?.confidenceMap ?? frame.smoothedSceneDepth?.confidenceMap
//        let confidenceImage: CIImage? = depthConfidenceBuffer != nil ? CIImage(cvPixelBuffer: depthConfidenceBuffer!) : nil
        
        locationManager?.setLocationAndHeading()
        var location: CLLocation? = nil
        if let latitude = locationManager?.latitude,
           let longitude = locationManager?.longitude {
            location = CLLocation(latitude: latitude, longitude: longitude)
        }
        
        processQueue.async { [weak self] in
            self?.processOverlay(pixelBuffer: pixelBuffer, exifOrientation: exif, cameraTransform: cameraTransform, cameraIntrinsics: cameraIntrinsics)
            self?.floorBundle?.cameraTransform = cameraTransform
            self?.floorBundle?.cameraIntrinsics = cameraIntrinsics
            self?.floorBundle?.cameraImage = cIImage
            self?.floorBundle?.depthBuffer = depthBuffer
            self?.floorBundle?.confidenceBuffer = depthConfidenceBuffer
            self?.floorBundle?.location = location
            self?.floorBundle?.orientation = exif
        }
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        handleMeshAnchors(anchors)
        self.arResourceUpdateCallback?(floorBundle, shouldCallResourceUpdateCallback)
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        handleMeshAnchors(anchors)
        self.arResourceUpdateCallback?(floorBundle, shouldCallResourceUpdateCallback)
    }
    
    private func renderMaskTo8BitPixelBuffer(_ mask: CIImage) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let w = Int(mask.extent.width), h = Int(mask.extent.height)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_OneComponent8,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let pb else { return nil }

        ciContext.render(mask, to: pb, bounds: mask.extent, colorSpace: nil)
        
//        let uniqueValues = CVPixelBufferUtils.extractUniqueGrayscaleValues(from: pb)
//        print("Unique values in rendered mask: \(uniqueValues.sorted())")
        return pb
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
    
    // MARK: - Overlay pipeline
    private func processOverlay(pixelBuffer: CVPixelBuffer, exifOrientation: CGImagePropertyOrientation, cameraTransform: simd_float4x4, cameraIntrinsics: simd_float3x3) {
        autoreleasepool {
            // Orient into display space
//            let base = CIImage(cvPixelBuffer: pixelBuffer).oriented(exifOrientation)
//            print("Base Image Size and Extent: \(base.extent.size), \(base.extent)")
//            let extent = base.extent  // pixel space, origin bottom-left
            guard let segmentationResults = try? segmentationFrameProcessor.processRequest(with: pixelBuffer, orientation: exifOrientation) else { return }
            guard let segmentationLabel = segmentationResults.label else { return }
            segmentationLabelImage = segmentationLabel
            self.cameraTransform = cameraTransform
            self.cameraIntrinsics = cameraIntrinsics
            guard var segmentationColor = segmentationResults.color else { return }
            
            // Convert normalized TL ROI -> CI bottom-left pixel rect
//            let tl = roiTopLeft
//            let crop = CGRect(
//                x: tl.minX * extent.width,
//                y: (1.0 - tl.maxY) * extent.height,
//                width: tl.width * extent.width,
//                height: tl.height * extent.height
//            ).integral

//            let cropped = base.cropped(to: crop)

            // Example post-processing (Edges)
//            let edges = CIFilter.edges()
//            edges.inputImage = cropped
//            edges.intensity = 1.5
//            let output = edges.outputImage ?? cropped

            segmentationColor = segmentationColor.oriented(exifOrientation)
//            segmentationColor = segmentationColor.transformed(by: CGImagePropertyOrientation.right.toUpTransform(for: segmentationColor.extent.size))
            guard let cg = ciContext.createCGImage(segmentationColor, from: segmentationColor.extent) else { return }
            let ui = UIImage(cgImage: cg)
            
            let damageDetectionResults = damageDetectionFrameProcessor.processRequest(with: pixelBuffer, orientation: exifOrientation)
            let damageDetectionImage = damageDetectionResults?.resultImage
            var damageUI: UIImage? = nil
            var cgDamage: CGImage? = nil
            if var damageDetectionImage = damageDetectionImage {
                damageDetectionImage = damageDetectionImage.oriented(exifOrientation)
                cgDamage = ciContext.createCGImage(damageDetectionImage, from: damageDetectionImage.extent)
            }
            if let cgDamage = cgDamage {
                damageUI = UIImage(cgImage: cgDamage)
            }
            
//            let localImage = UIImage(named: "1e8fde45bd_frame_006840_leftImg8bit_up_mirrored")
//            var localFinalImage: UIImage? = nil
//            if let localImage = localImage {
//                let localCIImage = CIImage(image: localImage)
//                if var localCIImage = localCIImage {
////                    print("Before transformation Local Image Size and Extent: \(localImage.size), \(localCIImage.extent)")
//                    localCIImage = localCIImage.transformed(by: CGImagePropertyOrientation.upMirrored.toUpTransform(for: localCIImage.extent.size))
////                    localCIImage = localCIImage.oriented(.right)
//                    if let cg = ciContext.createCGImage(localCIImage, from: localCIImage.extent) {
//                        localFinalImage = UIImage(cgImage: cg)
////                        print("After transformation Local Image Size and Extent: \(localFinalImage?.size), \(localCIImage.extent)")
//                    }
//                }
//            }

            DispatchQueue.main.async { [weak self] in
                self?.overlayImageView.image = ui
                self?.damageOverlayImageView.image = damageUI
                
                self?.floorBundle?.segmentationLabelImage = self?.segmentationLabelImage
                self?.floorBundle?.damageDetectionResults = damageDetectionResults?.results
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
        // Create copy of segmentation image to avoid threading issues
        guard let segmentationLabelImage = segmentationLabelImage,
                let cameraTransform = cameraTransform,
              let cameraIntrinsics = cameraIntrinsics else {
            return
        }
//        guard let segmentationPixelBuffer = renderMaskTo8BitPixelBuffer(segmentationLabelImage) else {
//            print("Failed to render segmentation mask to pixel buffer")
//            return
//        }
        guard let segmentationPixelBuffer = segmentationLabelImage.pixelBuffer else {
            print("Segmentation label image does not have underlying pixel buffer")
            return
        }
        
        CVPixelBufferLockBaseAddress(segmentationPixelBuffer, .readOnly)
        let width = CVPixelBufferGetWidth(segmentationPixelBuffer)
        let height = CVPixelBufferGetHeight(segmentationPixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(segmentationPixelBuffer)
        defer { CVPixelBufferUnlockBaseAddress(segmentationPixelBuffer, .readOnly) }
        
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        
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
            
            floorBundle = MeshBundle(
                anchorEntity: anchorEntity, greenEntity: greenEntity, redEntity: redEntity,
                lastUpdated: 0, assignedColor: assignedColor)
        }
        
        var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        var triangleNormals: [SIMD3<Float>] = []
        
        var pxRange: [CGFloat] = [1920, 1440, 0.0, 0.0] // minX, minY, maxX, maxY
        var uniqueValueFrequencies: [UInt8: Int] = [:]
        var counts = ["total": 0, "projectFailed": 0, "sampleFailed": 0, "classMismatch": 0, "kept": 0]
        for meshAnchor in meshAnchors {
            // Next step: Analyze this mesh anchor for height anomalies
            let geometry = meshAnchor.geometry
//            let id = meshAnchor.identifier
            
            // Throttle updates per anchor
            if Date().timeIntervalSince1970 - (floorBundle?.lastUpdated ?? 0) < updateInterval { continue }

//                _ = geometry.vertices
            let faces = geometry.faces
            let classifications = geometry.classification
//            let normals = geometry.normals
            
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
                    // Update pixel range
                    if px.x < pxRange[0] { pxRange[0] = CGFloat(px.x) }
                    if px.y < pxRange[1] { pxRange[1] = CGFloat(px.y) }
                    if px.x > pxRange[2] { pxRange[2] = CGFloat(px.x) }
                    if px.y > pxRange[3] { pxRange[3] = CGFloat(px.y) }
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
//
                    let edge1 = v1 - v0
                    let edge2 = v2 - v0
                    let normal = normalize(cross(edge1, edge2))
                    
                    triangles.append((v0, v1, v2))
                    triangleNormals.append(normal)
                }
            }
        }
//        print("Pixel Range in segmentation image for floor triangles: \(pxRange)")
//            print("Finished processing \(meshAnchors.count) mesh anchors.")
        if (counts["total", default: 0] > 0) {
//            print("Unique segmentation values under floor triangles: \(uniqueValueFrequencies)")
//            print("Counts: \(counts)")
        }
        // Step 2: Compute mean normal
        guard !triangleNormals.isEmpty else { return }
        
//        let meanNormal = normalize(triangleNormals.reduce(SIMD3<Float>(0, 0, 0), +) / Float(triangleNormals.count))
        let meanNormal = simd_float3(0, 1, 0) // Assume up vector for floor
        
        // Step 3: Split triangles based on deviation
        let thresholdDegrees: Float = 10.0
        var normalTriangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        var deviantTriangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        
        for (i, triangle) in triangles.enumerated() {
            let angleRad = abs(acos(dot(triangleNormals[i], meanNormal)))
            var angleDeg = angleRad * (180.0 / .pi)
            if angleDeg > 90.0 {
                angleDeg = 180.0 - angleDeg
            }
            if angleDeg > thresholdDegrees {
                deviantTriangles.append(triangle)
            } else {
                normalTriangles.append(triangle)
            }
        }
//                print("Normal Triangles Count: \(normalTriangles.count)")
//                print("Deviant Triangles Count: \(deviantTriangles.count)")
        
        // Step 4: Visualize
        if let normalEntity = createHorizontalMeshEntity(triangles: normalTriangles, color: UIColor(red: 0.957, green: 0.137, blue: 0.910, alpha: 0.9), name: "GreenMesh") {
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
        
        if let fullEntity = createHorizontalMeshEntity(triangles: triangles, color: floorBundle?.assignedColor ?? .green, opacity: 0.25, name: "FullMesh") {
            floorBundle?.fullEntity = fullEntity
        }
        
        floorBundle?.meshAnchors = meshAnchors
        
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
    
//    func createColorMeshEntity(
//        triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)],
//        normals: [SIMD3<Float>],
//        opacity: Float = 0.4,
//        name: String = "ColorMesh"
//    ) -> ModelEntity? {
//        if (triangles.isEmpty) {
//            return nil
//        }
//        
//        var positions: [SIMD3<Float>] = []
//        var indices: [UInt32] = []
//        var colors: [SIMD4<Float>] = []
//
//        for (i, triangle) in triangles.enumerated() {
//            let baseIndex = UInt32(i * 3)
//            positions.append(triangle.0)
//            positions.append(triangle.1)
//            positions.append(triangle.2)
//            indices.append(contentsOf: [baseIndex, baseIndex + 1, baseIndex + 2])
//            
//            let normal = normals[i]
//            let normalColor = (normal * 0.5) + SIMD3<Float>(repeating: 0.5)
//            let color = SIMD4<Float>(abs(normal.x), abs(normal.y), abs(normal.z), opacity)
//            colors.append(contentsOf: [color, color, color])
//        }
//        
//        var meshDescriptors = MeshDescriptor(name: name)
//        meshDescriptors.positions = MeshBuffers.Positions(positions)
//        meshDescriptors.primitives = .triangles(indices)
//        meshDescriptors.colors = .colors(colors)
//        guard let mesh = try? MeshResource.generate(from: [meshDescriptors]) else {
//            return nil
//        }
//    }
}
