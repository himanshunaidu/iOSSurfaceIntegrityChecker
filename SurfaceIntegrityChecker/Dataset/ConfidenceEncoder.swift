//
//  ConfidenceEncoder.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 9/18/25.
//

import Foundation
import CoreImage

class ConfidenceEncoder {
    enum Status {
        case ok
        case fileCreationError
    }
    private var baseDirectory: URL
    private let ciContext: CIContext
    public var status: Status = Status.ok

    init(outDirectory: URL) {
        self.baseDirectory = outDirectory
        self.ciContext = CIContext()
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
            print("Could not create confidence folder. \(error.localizedDescription)")
            status = Status.fileCreationError
        }
    }

    func encodeFrame(frame: CVPixelBuffer, frameString: String) {
        let filename = String(frameString)
        let image = CIImage(cvPixelBuffer: frame)
        assert(CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_OneComponent8)
        let framePath = self.baseDirectory.absoluteURL.appendingPathComponent(filename, isDirectory: false).appendingPathExtension("png")

        if let colorSpace = CGColorSpace(name: CGColorSpace.extendedGray) {
            do {
                try self.ciContext.writePNGRepresentation(of: image, to: framePath, format: CIFormat.L8, colorSpace: colorSpace)
            } catch let error {
                print("Could not save confidence value. \(error.localizedDescription)")
            }
        }
    }
}
