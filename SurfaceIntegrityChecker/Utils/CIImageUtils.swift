//
//  CIImageUtils.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/26/25.
//

import UIKit

extension CIImage {
    func croppedToCenter(size: CGSize) -> CIImage {
        let x = (extent.width - size.width) / 2
        let y = (extent.height - size.height) / 2
        let cropRect = CGRect(x: x, y: y, width: size.width, height: size.height)
        let croppedImage = cropped(to: cropRect)
        
        let centeredImage = croppedImage.transformed(by: CGAffineTransform(translationX: -x, y: -y))
        return centeredImage
    }
    
    /// Returns a resized image.
    func resized(to size: CGSize) -> CIImage {
        let outputScaleX = size.width / extent.width
        let outputScaleY = size.height / extent.height
        var outputImage = self.transformed(by: CGAffineTransform(scaleX: outputScaleX, y: outputScaleY))
        outputImage = outputImage.transformed(
            by: CGAffineTransform(translationX: -outputImage.extent.origin.x, y: -outputImage.extent.origin.y)
        )
        return outputImage
    }
}

struct CIImageUtils {
    static func toPixelBuffer(_ ciImage: CIImage, pixelFormat: OSType = kCVPixelFormatType_32BGRA) -> CVPixelBuffer? {
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        let context = CIContext()
        context.render(ciImage, to: buffer)
        
        return buffer
    }
    
    /**
     This function resizes a CIImage to match the specified size by:
        - First, resizing the image to match the smaller dimension while maintaining the aspect ratio.
        - Then, cropping the image to the specified size while centering it.
     */
    static func resizeWithAspectThenCrop(_ image: CIImage, to size: CGSize) -> CIImage {
        let sourceAspect = image.extent.width / image.extent.height
        let destAspect = size.width / size.height
        
        var transform: CGAffineTransform = .identity
        if sourceAspect > destAspect {
            let scale = size.height / image.extent.height
            let newWidth = image.extent.width * scale
            let xOffset = (size.width - newWidth) / 2
            transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: xOffset / scale, y: 0)
        } else {
            let scale = size.width / image.extent.width
            let newHeight = image.extent.height * scale
            let yOffset = (size.height - newHeight) / 2
            transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: 0, y: yOffset / scale)
        }
        let newImage = image.transformed(by: transform)
        let croppedImage = newImage.cropped(to: CGRect(origin: .zero, size: size))
        return croppedImage
    }
    
    /**
     This reverse function attempts to revert the effect of `resizeWithAspectThenCrop`.
        It takes the cropped and resized image, the target size it was resized to, and the original size before resizing and cropping.
        It calculates the necessary scaling and translation to restore the image to its original aspect ratio and size.
     */
    static func undoResizeWithAspectThenCrop(
        _ mask: CIImage, originalSize: CGSize, croppedSize: CGSize
    ) -> CIImage {
            let sourceAspect = originalSize.width / originalSize.height
            let destAspect   = croppedSize.width / croppedSize.height

            if sourceAspect > destAspect {
                // Source wider than dest (e.g. 1920×1440 -> 640×640):
                // Step 1 used: scale = destH / srcH ; newWidth = srcW * scale ; then center-crop X.
                let scale = croppedSize.height / originalSize.height
                let newWidth = originalSize.width * scale
                let xOffset = (croppedSize.width - newWidth) / 2.0  // negative

                // Put the 640×640 mask back into an (newWidth × croppedH) canvas, centered
                let canvas = CGRect(x: 0, y: 0, width: newWidth, height: croppedSize.height)
                let translated = mask.transformed(by: CGAffineTransform(translationX: -xOffset, y: 0)) // -xOffset is positive
                let background = CIImage(color: .clear).cropped(to: canvas)
                let composed = translated.composited(over: background)

                // Scale up uniformly to original size (1/scale)
                let inv = 1.0 / scale
                return composed.transformed(by: CGAffineTransform(scaleX: inv, y: inv))
            } else {
                // Source taller than dest (crop Y)
                let scale = croppedSize.width / originalSize.width
                let newHeight = originalSize.height * scale
                let yOffset = (croppedSize.height - newHeight) / 2.0

                let canvas = CGRect(x: 0, y: 0, width: croppedSize.width, height: newHeight)
                let translated = mask.transformed(by: CGAffineTransform(translationX: 0, y: -yOffset))
                let background = CIImage(color: .clear).cropped(to: canvas)
                let composed = translated.composited(over: background)

                let inv = 1.0 / scale
                return composed.transformed(by: CGAffineTransform(scaleX: inv, y: inv))
            }
        }
    
    /**
     This function returns the transformation to revert the effect of `resizeWithAspectThenCrop`.
     */
    static func transformRevertResizeWithAspectThenCrop(imageSize: CGSize, from originalSize: CGSize) -> CGAffineTransform {
        let sourceAspect = imageSize.width / imageSize.height
        let originalAspect = originalSize.width / originalSize.height
        
        var transform: CGAffineTransform = .identity
        if sourceAspect < originalAspect {
            let scale = originalSize.height / imageSize.height
            let newWidth = imageSize.width * scale
            let xOffset = (originalSize.width - newWidth) / 2
            transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: xOffset / scale, y: 0)
        } else {
            let scale = originalSize.width / imageSize.width
            let newHeight = imageSize.height * scale
            let yOffset = (originalSize.height - newHeight) / 2
            transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: 0, y: yOffset / scale)
        }
        return transform
    }
}
