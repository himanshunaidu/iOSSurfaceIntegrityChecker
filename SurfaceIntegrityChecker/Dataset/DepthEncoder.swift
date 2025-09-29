//
//  DepthEncoder.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 9/18/25.
//

import Foundation
import CoreImage
import UIKit

class DepthEncoder {
    enum Status {
        case ok
        case fileCreationError
    }
    private var baseDirectory: URL
    public var status: Status = Status.ok
    
    init(outDirectory: URL) {
        self.baseDirectory = outDirectory
        self.createDirectoryIfNeeded()
    }
    
//    func updateBaseDirectory(_ outDirectory: URL) {
//        guard self.baseDirectory != outDirectory else { return }
//        self.baseDirectory = outDirectory
//        self.createDirectoryIfNeeded()
//    }
    
    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: self.baseDirectory.absoluteURL, withIntermediateDirectories: true, attributes: nil)
        } catch let error {
            print("Could not create folder. \(error.localizedDescription)")
            status = Status.fileCreationError
        }
    }
    
    func save(ciImage: CIImage, frameString: String) {
        let filename = String(frameString)
        let image = UIImage(ciImage: ciImage)
        guard let data = image.pngData() else {
            print("Could not convert CIImage to PNG data for frame \(frameString).")
            return
        }
        let path = self.baseDirectory.absoluteURL.appendingPathComponent(filename, isDirectory: false).appendingPathExtension("png")
        do {
            try data.write(to: path)
        } catch let error {
            print("Could not save depth image \(frameString). \(error.localizedDescription)")
        }
    }
    
    func save(frame: CVPixelBuffer, frameString: String) {
        let filename = String(frameString)
        let encoder = self.convert(buffer: frame)
        let data = encoder.fileContents()
        let path = self.baseDirectory.absoluteURL.appendingPathComponent(filename, isDirectory: false).appendingPathExtension("png")
        do {
            try data?.write(to: path)
        } catch let error {
            print("Could not save depth image \(frameString). \(error.localizedDescription)")
        }
    }
    
    private func convert(buffer: CVPixelBuffer) -> PngEncoder {
        assert(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32)
        let height = CVPixelBufferGetHeight(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags.readOnly)
        let inBase = CVPixelBufferGetBaseAddress(buffer)
        let inPixelData = inBase!.assumingMemoryBound(to: Float32.self)
        
        let out = PngEncoder.init(depth: inPixelData, width: Int32(width), height: Int32(height))!
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        return out
    }
}
