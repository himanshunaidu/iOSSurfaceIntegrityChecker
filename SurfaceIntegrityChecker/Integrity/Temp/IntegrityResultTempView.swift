//
//  IntegrityResultView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/13/25.
//
import SwiftUI
import simd

struct IntegrityResultTempView: View {
    var ROOT_DIRECTORY_NAME = "Experiment_4"
    
    @State var datasetName: String = ""
    @State private var datasetSaveSuccess: Bool = false
    @State private var datasetSaveError: String? = nil
    @State var integrityCalculator: IntegrityCalculator = IntegrityCalculator()
    @State var integrityResults: IntegrityResults = IntegrityResults()
    @State var arResources: MeshBundle?
    
    @State var cameraUIImage: UIImage? = nil
    @State var meshOverlayUIImage: UIImage? = nil
    @State var slope: Float = 0.0
    
    @State var options: [AnnotationOption] = AnnotationOptionClass.allCases.map { .classOption($0) }
    @State private var selectedOption: AnnotationOption = .classOption(.agree)
    
    let sharedCIContext = CIContext(options: nil)
    
    var body: some View {
        VStack {
            Text("Surface Integrity Result")
                .font(.title)
                .padding()
            
            if (arResources != nil) {
                HostedIntegrityResultImageViewController(cameraUIImage: $cameraUIImage, meshOverlayUIImage: $meshOverlayUIImage)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            
            VStack {
                HStack {
                    Spacer()
                    Text("\(AnnotationViewConstants.Texts.selectedClassPrefixText): Sidewalk")
                    Spacer()
                }
                
//                HStack {
//                    Picker(AnnotationViewConstants.Texts.selectObjectText, selection: $annotationImageManager.selectedObjectId) {
//                        ForEach(annotationImageManager.annotatedDetectedObjects ?? [], id: \.id) { object in
//                            Text(object.label ?? "")
//                                .tag(object.id)
//                        }
//                    }
////                    openAnnotationInstanceDetailView()
//                }
                
                ProgressBar(value: 0.5)
                
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        ForEach(options, id: \.self) { option in
                            Button(action: {
                                // Update the selected option
//                                updateAnnotation(newOption: option)

//                                    selectedOption = (selectedOption == option) ? nil : option
                                
//                                    if option == .misidentified {
//                                        selectedClassIndex = index
//                                        tempSelectedClassIndex = sharedImageData.segmentedIndices[index]
//                                        isShowingClassSelectionModal = true
//                                    }
                            }) {
                                Text(option.rawValue)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(selectedOption == option ? Color.blue : Color.gray)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    Spacer()
                }
                .padding()
                
                Button(action: {
                    
                }) {
                    Text(false ? AnnotationViewConstants.Texts.finishText : AnnotationViewConstants.Texts.nextText)
                }
                .padding()
            }
        }
        .onAppear() {
            if let arResources = arResources,
               let integrityResults = integrityCalculator.getIntegrityResults(arResources)
            {
                self.integrityResults = integrityResults
                let meshOverlayImage = createMeshOverlayImage(
                    arResources: arResources,
                    integrityResults: integrityResults,
                    stroke: 3.0,
                    color: .red
                )
                let cameraImage = alignImage(ciImage: arResources.cameraImage, orientation: arResources.orientation)
                self.cameraUIImage = renderToUIImage(cameraImage ?? CIImage())
                self.meshOverlayUIImage = alignImage(uiImage: meshOverlayImage, orientation: arResources.orientation)
                
                if let plane = integrityResults.plane {
                    let normal = plane.n
                    let up = SIMD3<Float>(0, 1, 0)
                    let dotProduct = simd_dot(normal, up)
                    let magnitudeProduct = simd_length(normal) * simd_length(up)
                    let angleRadians = acos(dotProduct / magnitudeProduct)
                    var slope = angleRadians * (180.0 / .pi) // Convert to degrees
                    if (slope > 90.0) {
                        slope = 180.0 - slope
                    }
                    self.slope = slope
                }
            }
        }
    }
    
    func createMeshOverlayImage(
        arResources: MeshBundle,
        integrityResults: IntegrityResults,
        stroke: CGFloat = 1.0,
        color: UIColor = .white
    ) -> UIImage? {
        guard let cameraImage = arResources.cameraImage
        else {
            return nil
        }
//        let meshAnchors = arResources.meshAnchors
        let size = cameraImage.extent.size
        
        let damageDetectionResults = arResources.damageDetectionResults
        
//        let meshImage: CGImage? = MeshRasterizer.rasterizeMesh(meshTriangles: integrityResults.points, size: size)
//        guard let cgImage = meshImage else {
//            return nil
//        }
        
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale  = 1.0 // draw in native pixel space, no extra scaling
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)
            cg.setLineWidth(stroke)
            cg.setStrokeColor(color.cgColor)
            cg.setFillColor(UIColor.clear.cgColor)
            
            drawWireFrame(
                cg,
                triangles: integrityResults.points,
                triangleColors: integrityResults.triangleColors,
                imageSize: size
            )
            
            if let damageDetectionResults = damageDetectionResults {
                drawBoundingBoxes(
                    cg,
                    boxes: damageDetectionResults.map( { $0.boundingBox }),
                    imageSize: size
                )
            }
        }
        
//        return imageOriented(image, to: arResources.orientation)
//        let image = UIImage(cgImage: cgImage)
        return image
    }
    
    private func drawWireFrame(
        _ cg: CGContext,
        triangles: [(CGPoint, CGPoint, CGPoint)],
        triangleColors: [UIColor],
        imageSize: CGSize
    ) {
//        print("Drawing \(triangles.count) triangles on image of size \(imageSize)")
        for (index, triangle) in triangles.enumerated() {
            if !validatePoint(triangle.0, in: imageSize) ||
                !validatePoint(triangle.1, in: imageSize) ||
                !validatePoint(triangle.2, in: imageSize) {
//                print("Skipping triangle \(index) with out-of-bounds points: \(triangle.0), \(triangle.1), \(triangle.2)")
                continue
            }
            
            cg.setStrokeColor(triangleColors[index % triangleColors.count].cgColor)
            
            cg.beginPath()
            cg.move(to: triangle.0)
            cg.addLine(to: triangle.1)
            cg.addLine(to: triangle.2)
            cg.closePath()
            cg.strokePath()
        }
    }
    
    private func drawBoundingBoxes(
        _ cg: CGContext,
        boxes: [CGRect],
        imageSize: CGSize
    ) {
        cg.setStrokeColor(UIColor.red.cgColor)
        cg.setLineWidth(2.0)
        
        for box in boxes {
            if !validatePoint(box.origin, in: imageSize) ||
                !validatePoint(CGPoint(x: box.maxX, y: box.maxY), in: imageSize) {
                continue
            }
            
            cg.stroke(box)
        }
    }
    
    private func validatePoint(_ point: CGPoint, in size: CGSize) -> Bool {
        return point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height
    }
    
    // MARK: Temp function, later to be refactored to work well with the actual model output constraints
    private func centerSquareCrop(ciImage: CIImage) -> CIImage? {
        let e = ciImage.extent // in pixel coordinates, origin at bottom-left
        let side = min(e.width, e.height)
        let dx = (e.width  - side) / 2.0
        let dy = (e.height - side) / 2.0
        let cropRect = CGRect(x: e.origin.x + dx, y: e.origin.y + dy, width: side, height: side)
        // cropped(to:) is lazy until rendered—very cheap
        return ciImage.cropped(to: cropRect)
    }
    
    func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        guard let cgImage = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
    
    private func alignImage(
        ciImage: CIImage?, orientation: CGImagePropertyOrientation
    ) -> CIImage? {
        guard let ciImage = ciImage else { return nil }
        let orientedImage = ciImage.oriented(orientation)
        let centerCroppedImage = centerSquareCrop(ciImage: orientedImage)
        return centerCroppedImage
    }
    
    private func alignImage(
        uiImage: UIImage?, orientation: CGImagePropertyOrientation
    ) -> UIImage? {
        var image: CIImage? = nil
        if let uiImage = uiImage {
            image = CIImage(image: uiImage)
        }
        let alignedImage = alignImage(ciImage: image, orientation: orientation)
        if let alignedImage = alignedImage {
            return renderToUIImage(alignedImage)
        }
        return nil
    }
    
    private func imageOriented(_ image: UIImage, to orientation: CGImagePropertyOrientation) -> UIImage? {
        guard let cgimg = image.cgImage else { return image }

        let size = CGSize(width: cgimg.width, height: cgimg.height)
        let t = orientation.toUpTransform(for: size)

        // We want to *apply* the orientation to the pixels (i.e. return upright),
        // so we concatenate the corrective transform and redraw.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1.0

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.concatenate(t)
            cg.draw(cgimg, in: CGRect(origin: .zero, size: size))
        }
    }
}

struct ProgressBar: View {
    var value: Float


    var body: some View {
        ProgressView(value: value)
            .progressViewStyle(LinearProgressViewStyle())
            .padding()
    }
}
