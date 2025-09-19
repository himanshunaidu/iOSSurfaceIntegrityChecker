//
//  OtherDetailsEncoder.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 9/18/25.
//

import Foundation
import Accelerate
import ARKit

struct OtherDetailsData {
    let timestamp: TimeInterval
    let deviceOrientation: UIDeviceOrientation
    let originalSize: CGSize
}

class OtherDetailsEncoder {
    enum Status {
        case ok
        case fileCreationError
    }
    private var path: URL
    var fileHandle: FileHandle
    public var status: Status = Status.ok
    
    init(url: URL) {
        self.path = url
        self.fileHandle = FileHandle.standardOutput // Temporary assignment
        self.setupFileHander()
    }
    
//    func updatePath(_ url: URL) {
//        guard self.path != url else {
//            return
//        }
//        // Close the existing file handle
//        self.done()
//        // Update the path and create a new file handle
//        self.path = url
//        self.setupFileHander()
//    }
    
    private func setupFileHander() {
        FileManager.default.createFile(atPath: self.path.absoluteString,  contents:Data("".utf8), attributes: nil)
        do {
            try "".write(to: self.path, atomically: true, encoding: .utf8)
            self.fileHandle = try FileHandle(forWritingTo: self.path)
            self.fileHandle.write("timestamp, frame, deviceOrientation, originalWidth, originalHeight\n".data(using: .utf8)!)
        } catch let error {
            print("Can't create file \(self.path.absoluteString). \(error.localizedDescription)")
            preconditionFailure("Can't open camera transform file for writing.")
        }
    }
    
    func add(otherDetails: OtherDetailsData, frameString: String) {
        let frameNumber = String(frameString)
        let deviceOrientationString: String = String(otherDetails.deviceOrientation.rawValue)
        let originalWidth = String(Float(otherDetails.originalSize.width))
        let originalHeight = String(Float(otherDetails.originalSize.height))
        
        let line = "\(otherDetails.timestamp), \(frameNumber), \(deviceOrientationString), \(originalWidth), \(originalHeight)\n"
        self.fileHandle.write(line.data(using: .utf8)!)
    }
    
    func done() {
        do {
            try self.fileHandle.close()
        } catch let error {
            print("Can't close camera transform file \(self.path.absoluteString). \(error.localizedDescription)")
        }
    }
}
