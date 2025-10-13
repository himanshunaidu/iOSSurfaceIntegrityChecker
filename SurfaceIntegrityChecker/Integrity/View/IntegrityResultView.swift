//
//  IntegrityResultView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/13/25.
//
import SwiftUI

struct IntegrityResultView: View {
    var ROOT_DIRECTORY_NAME = "Experiment_4"
    
    @State var datasetName: String = ""
    @State private var datasetSaveSuccess: Bool = false
    @State private var datasetSaveError: String? = nil
    @State var integrityCalculator: IntegrityCalculator = IntegrityCalculator()
    @State var integrityResults: IntegrityResults = IntegrityResults()
    @State var arResources: MeshBundle?
    @State var meshOverlayImage: UIImage? = nil
    
    var body: some View {
        VStack {
            Text("Surface Integrity Result")
                .font(.title)
                .padding()
            
            if (arResources != nil) {
                HostedIntegrityResultImageViewController(arResources: $arResources, meshOverlayImage: $meshOverlayImage)
            }
            
//            Text((integrityResult == .intact) ? "The surface is intact." : "The surface has integrity issues.")
//                .font(.headline)
//                .foregroundColor((integrityResult == .intact) ? .green : .red)
//                .padding()
            Picker("Status", selection: $integrityResults.integrityStatus) {
                ForEach(IntegrityStatus.allCases) { option in
                    Text(String(describing: option))
                }
            }
            
            TextField("Dataset Name", text: $datasetName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            if let error = datasetSaveError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }
            if datasetSaveSuccess {
                Text("Dataset saved successfully!")
                    .foregroundColor(.green)
                    .padding()
            }
            
            Button("Save Result") {
                // Action to save the result
                if let arResources = arResources {
                    let datasetName = datasetName.isEmpty ? UUID().uuidString : datasetName
                    do {
                        let datasetEncoder = try DatasetEncoder(rootDirectoryName: ROOT_DIRECTORY_NAME, directoryName: datasetName)
                        try datasetEncoder.addData(frameString: UUID().uuidString, meshBundle: arResources)
                    } catch {
                        datasetSaveSuccess = false
                        datasetSaveError = "Failed to save dataset: \(error)"
                        print(datasetSaveError!)
                        return
                    }
                    datasetSaveSuccess = true
                    datasetSaveError = nil
                } else {
                    print("No AR Resources available for saving.")
                }
            }
        }
        .onAppear() {
            if let arResources = arResources,
               let integrityResults = integrityCalculator.getIntegrityResults(arResources)
            {
                self.integrityResults = integrityResults
                self.meshOverlayImage = createMeshOverlayImage(
                    arResources: arResources,
                    integrityResults: integrityResults,
                    stroke: 1.0,
                    color: .white
                )
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
        let meshAnchors = arResources.meshAnchors
        let size = cameraImage.extent.size
        
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
                imageSize: size
            )
        }
        
//        return imageOriented(image, to: arResources.orientation)
        return image
    }
    
    private func drawWireFrame(
        _ cg: CGContext,
        triangles: [(CGPoint, CGPoint, CGPoint)],
        imageSize: CGSize
    ) {
        print("Drawing \(triangles.count) triangles on image of size \(imageSize)")
        for (index, triangle) in triangles.enumerated() {
            if index == 0 {
                print("Drawing triangle 0: \(triangle)") // Debug print for the first triangle
            }
            let a2 = CGPoint(
                x: CGFloat(triangle.0.x) * imageSize.width,
                y: CGFloat(triangle.0.y) * imageSize.height
            )
            let b2 = CGPoint(
                x: CGFloat(triangle.1.x) * imageSize.width,
                y: CGFloat(triangle.1.y) * imageSize.height
            )
            let c2 = CGPoint(
                x: CGFloat(triangle.2.x) * imageSize.width,
                y: CGFloat(triangle.2.y) * imageSize.height
            )
            cg.beginPath()
            cg.move(to: a2)
            cg.addLine(to: b2)
            cg.addLine(to: c2)
            cg.closePath()
            cg.strokePath()
        }
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
