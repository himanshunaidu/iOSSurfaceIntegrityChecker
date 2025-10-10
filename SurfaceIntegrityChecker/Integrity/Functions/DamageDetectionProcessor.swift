//
//  DamageDetectionProcessor.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/9/25.
//

import CoreML
import Vision
import CoreImage
import CoreVideo

/**
 A struct to handle damage detection in images using a CoreML model.
 */
struct DamageDetectionProcessor {
    let modelURL: URL = Bundle.main.url(forResource: "v8n_175_16_960", withExtension: "mlmodelc")!
    var visionModel: VNCoreMLModel
    
    init() {
        let configuration: MLModelConfiguration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        guard let visionModel = try? VNCoreMLModel(for: MLModel(contentsOf: modelURL, configuration: configuration)) else {
            fatalError("Cannot load CNN model")
        }
        self.visionModel = visionModel
    }
    
    func configureDetectionRequest(request: VNCoreMLRequest) {
        // TODO: Need to check on the ideal options for this
        request.imageCropAndScaleOption = .scaleFill
    }
    
    func processDetectionRequest(with cIImage: CIImage, orientation: CGImagePropertyOrientation = .up) {
        do {
            let segmentationRequest = VNCoreMLRequest(model: self.visionModel)
            self.configureDetectionRequest(request: segmentationRequest)
            let detectionRequestHandler = VNImageRequestHandler(
                ciImage: cIImage,
                orientation: orientation,
                options: [:]
            )
            try detectionRequestHandler.perform([segmentationRequest])
            
            guard let detectionResult = segmentationRequest.results as? [VNRecognizedObjectObservation] else {
                return
            }
            print("Detection result: \(detectionResult)")
        } catch {
            print("Error processing detection request: \(error)")
        }
//        return nil
    }
}
