//
//  ImageBoundingBox.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/16/25.
//

import CoreImage
import UIKit

/**
 A custom Image that displays a bounding box around the region of segmentation
 */
struct ImageBoundingBox {
    let sharedContext: CIContext = CIContext(options: nil)
    
    /**
     This function creates a CGImage with a bounding box drawn on it.
     */
    func create(
        imageSize: CGSize, boundingBoxSize: CGSize,
        postOrientation: CGImagePropertyOrientation
    ) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        let boundingBoxRect = getBoundingBoxWithAspectFitRect(imageSize: imageSize, boundingBoxSize: boundingBoxSize)
        
        context.setStrokeColor(UIColor.white.cgColor)
        context.setShadow(offset: .zero, blur: 5.0, color: UIColor.black.cgColor)
        context.setLineWidth(10.0)
        
        context.addRect(boundingBoxRect)
        context.strokePath()
        
        let boxedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        if let boxedImage = boxedImage {
            var ciImage = CIImage(image: boxedImage)
            ciImage = ciImage?.oriented(postOrientation)
            
            guard let ciImage = ciImage, let cgImage = sharedContext.createCGImage(ciImage, from: ciImage.extent) else {
                return boxedImage
            }
            return UIImage(cgImage: cgImage)
        }
        
        return boxedImage
    }
    
    private func getBoundingBoxWithAspectFitRect(imageSize: CGSize, boundingBoxSize: CGSize) -> CGRect {
        let sourceAspect = imageSize.width / imageSize.height
        let destAspect = boundingBoxSize.width / boundingBoxSize.height
        
        var boundingBoxRect: CGRect = .zero
        var scale: CGFloat = 1.0
        var xOffset: CGFloat = 0.0
        var yOffset: CGFloat = 0.0
        if sourceAspect > destAspect {
            scale = imageSize.height / boundingBoxSize.height
            xOffset = (imageSize.width - (boundingBoxSize.width * scale)) / 2
        } else {
            scale = imageSize.width / boundingBoxSize.width
            yOffset = (imageSize.height - (boundingBoxSize.height * scale)) / 2
        }
        boundingBoxRect.size = CGSize(width: boundingBoxSize.width * scale, height: boundingBoxSize.height * scale)
        boundingBoxRect.origin = CGPoint(x: xOffset, y: yOffset)
        return boundingBoxRect
    }
}
