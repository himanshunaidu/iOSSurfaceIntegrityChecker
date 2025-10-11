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
    static let modelURL: URL = Bundle.main.url(forResource: "v8n_175_16_960", withExtension: "mlmodelc")!
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
        
        guard let damageDetectionResults: [DamageDetectionResult] = processImage(with: cIImage, orientation: .up) else {
            return nil
        }
        let damageDetectionResultImage = DetectedObjectRasterizer.rasterizeContourObjects(objects: damageDetectionResults, size: croppedSize)
        guard let damageDetectionResultImageUnwrapped = damageDetectionResultImage else {
            return (results: damageDetectionResults, resultImage: nil)
        }
        var damageDetectionResultCIImage: CIImage = CIImage(cgImage: damageDetectionResultImageUnwrapped)
        let inverse = orientation.inverted
        damageDetectionResultCIImage = damageDetectionResultCIImage.oriented(inverse)
        var damageDetectionImage = CIImageUtils.undoResizeWithAspectThenCrop(
            damageDetectionResultCIImage,
            originalSize: originalSize,
            croppedSize: croppedSize)
//        damageDetectionImage = backCIImageToPixelBuffer(damageDetectionImage)
        
        return (results: damageDetectionResults, resultImage: damageDetectionImage)
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
            var damageDetectionResults: [DamageDetectionResult] = detectionResult.map { observation in
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
