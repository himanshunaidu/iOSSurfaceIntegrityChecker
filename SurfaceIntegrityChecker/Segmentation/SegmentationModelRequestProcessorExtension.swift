//
//  SegmentationModelRequestProcessor.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/25/25.
//
import CoreML
import Vision
import CoreImage
import CoreVideo

extension SegmentationModelRequestProcessor {
    func processSegmentationRequest(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> (segmentationImage: CVPixelBuffer, segmentedIndices: [Int])? {
        do {
            let segmentationRequest = VNCoreMLRequest(model: self.visionModel)
            self.configureSegmentationRequest(request: segmentationRequest)
            let segmentationRequestHandler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )
            
            try segmentationRequestHandler.perform([segmentationRequest])
            
            guard let segmentationResult = segmentationRequest.results as? [VNPixelBufferObservation] else {return nil}
            let segmentationBuffer = segmentationResult.first?.pixelBuffer
            guard let segmentationBuffer else { return nil }
            
            let uniqueGrayScaleValues = CVPixelBufferUtils.extractUniqueGrayscaleValues(from: segmentationBuffer)
            let grayscaleValuesToIndex = SegmentationConfig.cocoCustom11Config.labelToIndexMap
            let selectedIndices = uniqueGrayScaleValues.compactMap { grayscaleValuesToIndex[$0] }
            let selectedIndicesSet = Set(selectedIndices)
            let segmentedIndices = self.selectionClasses.filter{ selectedIndicesSet.contains($0) }
            
            return (segmentationBuffer, segmentedIndices)
        } catch {
            print("Error processing segmentation request: \(error)")
        }
        return nil
    }
}
