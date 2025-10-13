//
//  CameraOrientation.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/25/25.
//
import UIKit
import CoreGraphics

class CameraOrientation {
    
    static func getCGImageOrientationForBackCamera(currentDeviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        switch currentDeviceOrientation {
            case .portrait:
                return .right                // Camera is rotated 90° CW to be upright
            case .portraitUpsideDown:
                return .left                 // Camera is rotated 90° CCW
            case .landscapeLeft:
                return .up                   // (Home button on the right) Camera is not rotated.
            case .landscapeRight:
                return .down                 // (Home button on the left) Camera is rotated 180°.
            default:
                return .right               // Fallback to portrait
        }
    }
    
    static func getCGImageReverseOrientationForBackCamera(currentDeviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        switch currentDeviceOrientation {
        case .portrait:
            return .left                 // Camera is rotated 90° CCW to revert to original orientation
        case .portraitUpsideDown:
            return .right                // Camera is rotated 90° CW to revert to original orientation
        case .landscapeLeft:
            return .up                 // Home button on the right, camera is rotated 180°
        case .landscapeRight:
            return .down                   // Home button on the left, camera is rotated 180°
        default:
            return .left                // Fallback to portrait
        }
    }
    
    static func getUIImageOrientationForBackCamera(currentDeviceOrientation: UIDeviceOrientation) -> UIImage.Orientation {
        switch currentDeviceOrientation {
            case .portrait:
                return .right
            case .portraitUpsideDown:
                return .left
            case .landscapeLeft:
                return .up
            case .landscapeRight:
                return .down
            default:
                return .right
        }
    }
    
    // Since people tend to hold devices in portrait mode by default when using the camera,
    // we can assume that the camera is in portrait mode when the device orientation is unknown.
    static func isLandscapeOrientation(currentDeviceOrientation: UIDeviceOrientation) -> Bool {
        return currentDeviceOrientation == .landscapeLeft || currentDeviceOrientation == .landscapeRight
    }
}

extension CGImagePropertyOrientation {
    var inverted: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .right
        case .right: return .left
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .rightMirrored
        case .rightMirrored: return .leftMirrored
        @unknown default: return .up
        }
    }
    
    var normalizedToUpTransform: CGAffineTransform {
        var t = CGAffineTransform.identity

        // First handle the 90/180° rotations (use unit size = 1)
        switch self {
        case .down, .downMirrored:
            // rotate 180° around origin, then move back into [0,1]^2
            t = t.translatedBy(x: 1, y: 1)
            t = t.rotated(by: .pi)

        case .left, .leftMirrored:
            // rotate +90° (CCW), then shift into [0,1]^2
            t = t.translatedBy(x: 1, y: 0)
            t = t.rotated(by: .pi / 2)

        case .right, .rightMirrored:
            // rotate -90° (CW), then shift into [0,1]^2
            t = t.translatedBy(x: 0, y: 1)
            t = t.rotated(by: -.pi / 2)

        case .up, .upMirrored:
            break
        }

        // Then handle the mirror variants (horizontal flip)
        switch self {
        case .upMirrored, .downMirrored:
            // flip horizontally
            t = t.translatedBy(x: 1, y: 0)
            t = t.scaledBy(x: -1, y: 1)

        case .leftMirrored, .rightMirrored:
            // after 90° rotation, width/height swap;
            // still a horizontal flip in the rotated space
            t = t.translatedBy(x: 1, y: 0)
            t = t.scaledBy(x: -1, y: 1)

        case .up, .down, .left, .right:
            break
        }

        return t
    }
    
    func toUpTransform(for size: CGSize) -> CGAffineTransform {
        var t = CGAffineTransform.identity
        
        switch self {
        case .down, .downMirrored:
            t = t.translatedBy(x: size.width, y: size.height)
            t = t.rotated(by: .pi)
        case .left, .leftMirrored:
            t = t.translatedBy(x: size.height, y: 0)
            t = t.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            t = t.translatedBy(x: 0, y: size.width)
            t = t.rotated(by: -.pi / 2)
        case .up, .upMirrored:
            break
        }
        
        switch self {
        case .upMirrored, .downMirrored:
            t = t.translatedBy(x: size.width, y: 0)
            t = t.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            t = t.translatedBy(x: size.width, y: 0)
            t = t.scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        }
        
        return t
    }
}
