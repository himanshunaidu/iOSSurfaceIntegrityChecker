//
//  SegmentationFrameProcessor.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/26/25.
//

import SwiftUI
import RealityKit
import ARKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Combine
import CoreVideo

enum SegmentationProcessingError: Error, LocalizedError {
    case pixelBufferPoolCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .pixelBufferPoolCreationFailed:
            return "Failed to create pixel buffer pool."
        }
    }
}

final class SegmentationFrameProcessor: ObservableObject {
//    var pixelBuffer: CVPixelBuffer?
//    var exifOrientation: CGImagePropertyOrientation = .right
    
//    let sidewalkLabel = 1
    var selectionClasses: [Int] = []
    var selectionClassLabels: [UInt8] = []
    var selectionClassGrayscaleValues: [Float] = []
    var selectionClassColors: [CIColor] = []
    
    var ciContext = CIContext(options: nil)
    var cameraPixelBufferPool: CVPixelBufferPool? = nil
    var cameraColorSpace: CGColorSpace? = nil
    
    let grayscaleToColorMasker = GrayscaleToColorCIFilter()
    var segmentationModelRequestProcessor: SegmentationModelRequestProcessor?
    
    init() {
        self.segmentationModelRequestProcessor = SegmentationModelRequestProcessor(
            selectionClasses: selectionClasses)
        
        do {
            try setUpPixelBufferPools()
        } catch {
            fatalError("Failed to set up pixel buffer pools: \(error.localizedDescription)")
        }
    }
    
    func setSelectionClasses(_ selectionClasses: [Int]) {
        self.selectionClasses = selectionClasses
        self.selectionClassLabels = selectionClasses.map { SegmentationConfig.cocoCustom11Config.labels[$0] }
        self.selectionClassGrayscaleValues = selectionClasses.map { SegmentationConfig.cocoCustom11Config.grayscaleValues[$0] }
        self.selectionClassColors = selectionClasses.map { SegmentationConfig.cocoCustom11Config.colors[$0] }
        
        self.segmentationModelRequestProcessor?.setSelectionClasses(self.selectionClasses)
    }
    
    func processRequest(with pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> CIImage? {
        // Step 1: Preprocess the camera image to match model input requirements
        var cIImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let originalSize: CGSize = CGSize(
            width: cIImage.extent.width,
            height: cIImage.extent.height
        )
        let croppedSize: CGSize = CGSize(
            width: SegmentationConfig.cocoCustom11Config.inputSize.width,
            height: SegmentationConfig.cocoCustom11Config.inputSize.height
        )
        var cameraImage = CIImageUtils.resizeWithAspectThenCrop(cIImage, to: croppedSize)
        cameraImage = cameraImage.oriented(orientation)
        
        let renderedCameraPixelBuffer = renderCIImageToPixelBuffer(
            cameraImage,
            size: croppedSize,
            pixelBufferPool: cameraPixelBufferPool!,
            colorSpace: cameraColorSpace
        )
        
        guard let renderedCameraPixelBufferUnwrapped = renderedCameraPixelBuffer else {
            return nil
        }
        cIImage = CIImage(cvPixelBuffer: renderedCameraPixelBufferUnwrapped)
        
        // Step 2: Run the segmentation model and get the segmentation mask
        let segmentationImage = try processImage(with: cIImage, orientation: .up)
        
        // Step 3: Postprocess the segmentation mask to match camera image size
        guard var mask = segmentationImage else {
            return nil
        }
//        print("Segmentation Mask Size and Extent: \(mask.extent.size), \(mask.extent)")
        
        let inverse = orientation.inverted
        mask = mask.oriented(inverse)
//        print("Inverted Mask Size and Extent: \(mask.extent.size), \(mask.extent)")
        
        let resizedMask = CIImageUtils.undoResizeWithAspectThenCrop(
            mask, originalSize: originalSize, croppedSize: croppedSize)
//        print("Resized Mask Size and Extent: \(resizedMask.extent.size), \(resizedMask.extent)")
        return resizedMask
    }
    
    func processImage(with cIImage: CIImage, orientation: CGImagePropertyOrientation) throws -> CIImage? {
        let segmentationResults = self.segmentationModelRequestProcessor?.processSegmentationRequest(with: cIImage, orientation: orientation) ?? nil
        guard let segmentationImage = segmentationResults?.segmentationImage else {
            throw SegmentationARPipelineError.invalidSegmentation
        }
        
        self.grayscaleToColorMasker.inputImage = segmentationImage
        self.grayscaleToColorMasker.grayscaleValues = self.selectionClassGrayscaleValues
        self.grayscaleToColorMasker.colorValues =  self.selectionClassColors
//        return segmentationImage
        return self.grayscaleToColorMasker.outputImage
    }
}

extension SegmentationFrameProcessor {
    func setUpPixelBufferPools() throws {
        // Set up the pixel buffer pool for future flattening of camera images
        let cameraPixelBufferPoolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 5
        ]
        let cameraPixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: SegmentationConfig.cocoCustom11Config.inputSize.width,
            kCVPixelBufferHeightKey as String: SegmentationConfig.cocoCustom11Config.inputSize.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let cameraStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            cameraPixelBufferPoolAttributes as CFDictionary,
            cameraPixelBufferAttributes as CFDictionary,
            &cameraPixelBufferPool
        )
        guard cameraStatus == kCVReturnSuccess else {
            throw SegmentationProcessingError.pixelBufferPoolCreationFailed
        }
        cameraColorSpace = CGColorSpaceCreateDeviceRGB()
    }
    
    private func renderCIImageToPixelBuffer(
        _ image: CIImage, size: CGSize,
        pixelBufferPool: CVPixelBufferPool, colorSpace: CGColorSpace? = nil) -> CVPixelBuffer? {
        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            return nil
        }
        
        ciContext.render(image, to: pixelBuffer, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
        return pixelBuffer
    }
}
