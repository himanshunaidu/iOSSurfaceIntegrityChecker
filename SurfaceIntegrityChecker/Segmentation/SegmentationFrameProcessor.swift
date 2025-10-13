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

/**
    An object that processes camera frames for segmentation using a Core ML model.
 
    TODO: Instead of performing all the image pre-processing manually, use the built-in Vision options to handle this (e.g. orientation, imageCropAndScaleOption).
 */
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
    
    func processRequest(with pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> (label: CIImage?, color: CIImage?)? {
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
        
        var cameraImage = cIImage.oriented(orientation)
        cameraImage = CIImageUtils.resizeWithAspectThenCrop(cameraImage, to: croppedSize)
        
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
        self.grayscaleToColorMasker.inputImage = mask
        self.grayscaleToColorMasker.grayscaleValues = self.selectionClassGrayscaleValues
        self.grayscaleToColorMasker.colorValues =  self.selectionClassColors
        let colorMask = self.grayscaleToColorMasker.outputImage
        
        let inverse = orientation.inverted
        mask = mask.oriented(inverse)
        var resizedMask = CIImageUtils.undoResizeWithAspectThenCrop(
            mask, originalSize: originalSize, croppedSize: croppedSize)
        resizedMask = self.backCIImageToPixelBuffer(resizedMask)
        
        if var colorMask = colorMask {
            colorMask = colorMask.oriented(inverse)
            let resizedColorMask = CIImageUtils.undoResizeWithAspectThenCrop(
                colorMask, originalSize: originalSize, croppedSize: croppedSize)
            return (label: resizedMask, color: resizedColorMask)
        }
        
        return (label: resizedMask, color: nil)
    }
    
    func processImage(with cIImage: CIImage, orientation: CGImagePropertyOrientation) throws -> CIImage? {
        let segmentationResults = self.segmentationModelRequestProcessor?.processSegmentationRequest(with: cIImage, orientation: orientation) ?? nil
        guard let segmentationImage = segmentationResults?.segmentationImage else {
            throw SegmentationARPipelineError.invalidSegmentation
        }
        
//        self.grayscaleToColorMasker.inputImage = segmentationImage
//        self.grayscaleToColorMasker.grayscaleValues = self.selectionClassGrayscaleValues
//        self.grayscaleToColorMasker.colorValues =  self.selectionClassColors
        return segmentationImage
//        return self.grayscaleToColorMasker.outputImage
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
    
    private func backCIImageToPixelBuffer(_ image: CIImage) -> CIImage {
        var imageBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] // Required for Metal/CoreImage
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(image.extent.width),
            Int(image.extent.height),
            kCVPixelFormatType_OneComponent8,
            attributes as CFDictionary,
            &imageBuffer
        )
        guard status == kCVReturnSuccess, let imageBuffer = imageBuffer else {
            print("Error: Failed to create pixel buffer")
            return image
        }
        // Render the CIImage to the pixel buffer
        self.ciContext.render(image, to: imageBuffer, bounds: image.extent, colorSpace: CGColorSpaceCreateDeviceGray())
        // Create a CIImage from the pixel buffer
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        return ciImage
    }
}
