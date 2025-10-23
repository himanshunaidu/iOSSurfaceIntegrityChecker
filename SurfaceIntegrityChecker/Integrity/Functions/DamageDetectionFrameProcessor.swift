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

enum DamageDetectionConfig {
    static let inputWidth: Int = 640
    static let inputHeight: Int = 640
//    static let modelURL: URL = Bundle.main.url(forResource: "v8n_175_16_960", withExtension: "mlmodelc")!
    static let modelURL: URL = Bundle.main.url(forResource: "v8n_175_16_960_lab_controlled", withExtension: "mlmodelc")!
}

enum DetectionProcessingError: Error, LocalizedError {
    case pixelBufferPoolCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .pixelBufferPoolCreationFailed:
            return "Failed to create pixel buffer pool."
        }
    }
}

struct DamageDetectionResult {
    var boundingBox: CGRect
    var confidence: VNConfidence
    var label: String
}

/**
 A struct to handle damage detection in images using a CoreML model.
 
 TODO: Instead of performing all the image pre-processing manually, use the built-in Vision options to handle this (e.g. orientation, imageCropAndScaleOption).
 */
final class DamageDetectionFrameProcessor: ObservableObject {
    var visionModel: VNCoreMLModel
    
    var ciContext = CIContext(options: nil)
    var cameraPixelBufferPool: CVPixelBufferPool? = nil
    var cameraColorSpace: CGColorSpace? = nil
    
    init() {
        let configuration: MLModelConfiguration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        guard let visionModel = try? VNCoreMLModel(for: MLModel(contentsOf: DamageDetectionConfig.modelURL, configuration: configuration)) else {
            fatalError("Cannot load CNN model")
        }
        self.visionModel = visionModel
        
        do {
            try setUpPixelBufferPools()
        } catch {
            fatalError("Failed to set up pixel buffer pools: \(error.localizedDescription)")
        }
    }
    
    func configureRequest(request: VNCoreMLRequest) {
        // TODO: Need to check on the ideal options for this
        request.imageCropAndScaleOption = .scaleFill
    }
    
    func processRequest(with pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> (results: [DamageDetectionResult]?, resultImage: CIImage?)? {
        var cIImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let originalSize: CGSize = CGSize(
            width: cIImage.extent.width,
            height: cIImage.extent.height
        )
        let croppedSize: CGSize = CGSize(
            width: CGFloat(DamageDetectionConfig.inputWidth),
            height: CGFloat(DamageDetectionConfig.inputHeight)
        )
        var cameraImage = cIImage.oriented(orientation)
        cameraImage = CIImageUtils.centerCropAspectFit(cameraImage, to: croppedSize)
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
        
        guard let damageDetectionResults: [DamageDetectionResult] = processImage(with: cIImage, orientation: .up) else {
            return nil
        }
        var alignedDamageDetectionResults = damageDetectionResults.map { result in
            var alignedResult = result
            alignedResult.boundingBox = alignBoundingBox(result.boundingBox, orientation: orientation, imageSize: croppedSize, originalSize: originalSize)
            return alignedResult
        }
//        alignedDamageDetectionResults.append(DamageDetectionResult(
//            boundingBox: CGRect(x: 0, y: originalSize.height/2, width: originalSize.width/2, height: originalSize.height/2),
//            confidence: 1.0,
//            label: "Container"
//        ))
            
        
        let damageDetectionResultImage = DetectedObjectRasterizer.rasterizeContourObjects(objects: damageDetectionResults, size: croppedSize)
        guard let damageDetectionResultImageUnwrapped = damageDetectionResultImage else {
            return (results: damageDetectionResults, resultImage: nil)
        }
        var damageDetectionResultCIImage: CIImage = CIImage(cgImage: damageDetectionResultImageUnwrapped)
        let inverse = orientation.inverted
        damageDetectionResultCIImage = damageDetectionResultCIImage.oriented(inverse)
        let damageDetectionImage = CIImageUtils.revertCenterCropAspectFit(
            damageDetectionResultCIImage,
            originalSize: originalSize)
//        damageDetectionImage = backCIImageToPixelBuffer(damageDetectionImage)
        
        return (results: alignedDamageDetectionResults, resultImage: damageDetectionImage)
    }
    
    func processImage(with cIImage: CIImage, orientation: CGImagePropertyOrientation) -> [DamageDetectionResult]? {
        do {
            let segmentationRequest = VNCoreMLRequest(model: self.visionModel)
            self.configureRequest(request: segmentationRequest)
            let detectionRequestHandler = VNImageRequestHandler(
                ciImage: cIImage,
                orientation: orientation,
                options: [:]
            )
            try detectionRequestHandler.perform([segmentationRequest])
            
            guard let detectionResult = segmentationRequest.results as? [VNRecognizedObjectObservation] else {
                return nil
            }
            let damageDetectionResults: [DamageDetectionResult] = detectionResult.map { observation in
                let topLabel = observation.labels.first
                return DamageDetectionResult(
                    boundingBox: observation.boundingBox,
                    confidence: topLabel?.confidence ?? 0.0,
                    label: topLabel?.identifier ?? "N/A"
                )
            }
//            let containerResult = DamageDetectionResult(
//                boundingBox: CGRect(x: 0.0, y: 0.99, width: 1.0, height: 0.98),
//                confidence: 1.0,
//                label: "Container"
//            )
//            damageDetectionResults.insert(containerResult, at: 0)
            
            return damageDetectionResults
        } catch {
            print("Error processing detection request: \(error)")
        }
        return nil
    }
    
    /**
        Aligns a bounding box from normalized coordinates to image coordinates, taking into account the image orientation.
     */
    func alignBoundingBox(_ boundingBox: CGRect, orientation: CGImagePropertyOrientation, imageSize: CGSize, originalSize: CGSize) -> CGRect {
        var orientationTransform = orientation.normalizedToUpTransform.inverted()
        
        // Adjust for Vision's coordinate system (origin at bottom-left)
        // Not needed as it is taken care of later during rendering
//        orientationTransform = orientationTransform.concatenating(CGAffineTransform(scaleX: 1, y: -1))
//        orientationTransform = orientationTransform.concatenating(CGAffineTransform(translationX: 0, y: imageSize.height))
//        print("Adjusted Orientation Transform: \(orientationTransform)")
        
        let alignedBox = boundingBox.applying(orientationTransform)
        
        // Revert the center-cropping effect to map back to original image size
        
        let translatedBox = translateBoundingBoxToRevertCenterCrop(alignedBox, imageSize: imageSize, originalSize: originalSize)
        
        let finalBox = CGRect(
            x: translatedBox.origin.x * originalSize.width,
            y: (1 - (translatedBox.origin.y + translatedBox.size.height)) * originalSize.height,
            width: translatedBox.size.width * originalSize.width,
            height: translatedBox.size.height * originalSize.height
        )
        
        return finalBox
    }
    
//    private func transformBoundingBox(_ boundingBox: CGRect, with transform: CGAffineTransform) -> CGRect {
//        // We cannot simply use the .applying method as it transforms the space
//        // Instead, we get the four corners and transform them individually
//        let topLeft = CGPoint(x: boundingBox.minX, y: boundingBox.minY).applying(transform)
//        let topRight = CGPoint(x: boundingBox.maxX, y: boundingBox.minY).applying(transform)
//        let bottomLeft = CGPoint(x: boundingBox.minX, y: boundingBox.maxY).applying(transform)
//        let bottomRight = CGPoint(x: boundingBox.maxX, y: boundingBox.maxY).applying(transform)
//        
//        let newRect = CGRect(
//            x: min(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x),
//            y: min(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y),
//            width: max(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x) - min(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x),
//            height: max(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y) - min(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)
//        )
//        return newRect
//    }
    
    /**
     Translated a bounding box to revert the effect of center cropping.
     
     Since the co-ordinates are normalized, we only need to adjust translations and not scaling.
     */
    private func translateBoundingBoxToRevertCenterCrop(_ boundingBox: CGRect, imageSize: CGSize, originalSize: CGSize) -> CGRect {
        let sourceAspect = imageSize.width / imageSize.height
        let originalAspect = originalSize.width / originalSize.height
        
        var transform: CGAffineTransform = .identity
        if sourceAspect < originalAspect {
            // Image was cropped horizontally because original is wider
            let scale = imageSize.height / originalSize.height
            let newImageSize = CGSize(width: imageSize.width / scale, height: imageSize.height / scale)
            
            let xOffset = (originalSize.width - newImageSize.width) / (2 * originalSize.width)
            let widthScale = newImageSize.width / originalSize.width
            transform = CGAffineTransform(scaleX: widthScale, y: 1)
                .translatedBy(x: xOffset / widthScale, y: 0)
        } else {
            // Image was cropped vertically because original is taller
            let scale = imageSize.width / originalSize.width
            let newImageSize = CGSize(width: imageSize.width / scale, height: imageSize.height / scale)
            
            let yOffset = (originalSize.height - newImageSize.height) / (2 * originalSize.height)
            let heightScale = newImageSize.height / originalSize.height
            transform = CGAffineTransform(scaleX: 1, y: heightScale)
                .translatedBy(x: 0, y: yOffset / heightScale)
        }
        let translatedBox = boundingBox.applying(transform)
        return translatedBox
    }
}

extension DamageDetectionFrameProcessor {
    func setUpPixelBufferPools() throws {
        // Set up the pixel buffer pool for future flattening of camera images
        let cameraPixelBufferPoolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 5
        ]
        let cameraPixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: DamageDetectionConfig.inputWidth,
            kCVPixelBufferHeightKey as String: DamageDetectionConfig.inputHeight,
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
