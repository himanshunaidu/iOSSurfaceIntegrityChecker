//
//  ContourObjectRasterizer.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 4/18/25.
//

import CoreImage
import UIKit
import CoreText

/**
    Rasterizes detected contour objects into a CIImage.
    A helper function that is not used in the main app currently, but can be useful for debugging or visualization purposes.
 */

// Already defined
//struct RasterizeConfig {
//    let draw: Bool
//    let color: UIColor?
//    let width: CGFloat
//    let alpha: CGFloat
//    
//    init(draw: Bool = true, color: UIColor?, width: CGFloat = 2.0, alpha: CGFloat = 1.0) {
//        self.draw = draw
//        self.color = color
//        self.width = width
//        self.alpha = alpha
//    }
//}

/**
 A temporary struct to perform rasterization of detected objects.
 TODO: This should be replaced by a lower-level rasterization function that uses Metal or Core Graphics directly.
 */
struct DetectedObjectRasterizer {
    static func rasterizeContourObjects(
        objects: [DamageDetectionResult], size: CGSize,
        boundsConfig: RasterizeConfig = RasterizeConfig(color: .red, width: 5.0),
        labelConfig: RasterizeConfig = RasterizeConfig(color: .blue, width: 1.0)
    ) -> CGImage? {
        
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        for object in objects {
            /// Draw the bounding box
            if boundsConfig.draw {
                let boundingBox = object.boundingBox
                // Ignoring rectX and rectY for now
                let boundingBoxRect = CGRect(
                    x: CGFloat(boundingBox.origin.x) * size.width,
                    y: CGFloat(1 - boundingBox.origin.y) * size.height, // TODO: Remove 0.1 offset
                    width: CGFloat(boundingBox.size.width) * size.width,
                    height: CGFloat(boundingBox.size.height) * size.height
                )
                let boundsColor = boundsConfig.color ?? UIColor.red
                context.setStrokeColor(boundsColor.cgColor)
                context.setLineWidth(boundsConfig.width)
                context.addRect(boundingBoxRect) // Actually has origin at top-left
                context.strokePath()
            }
            
            // Write the label
            if labelConfig.draw {
                let label = object.label
                let boundingBox = object.boundingBox
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24),
                    .foregroundColor: UIColor.blue,
                    .paragraphStyle: paragraphStyle
                ]
                
                let textX = CGFloat(boundingBox.origin.x) * size.width
                let textY = CGFloat(1 - boundingBox.origin.y) * size.height - 20.0
                let textSize = (label as NSString).size(withAttributes: attributes)
                let textRect = CGRect(
                    x: textX,
                    y: textY,
                    width: textSize.width,
                    height: textSize.height
                )
                
                // Draw the text directly into the current context.
                (label as NSString).draw(in: textRect, withAttributes: attributes)
            }
        }
        let cgImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage
        UIGraphicsEndImageContext()
        
        if let cgImage = cgImage {
//            return CIImage(cgImage: cgImage)
            return cgImage
        }
        return nil
    }
}
