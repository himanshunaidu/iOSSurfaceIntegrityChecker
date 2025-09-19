//
//  DatasetEncoder.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 9/16/25.
//

import Foundation
import ARKit
import CryptoKit
import CoreLocation

enum DatasetEncoderStatus {
    case allGood
    case directoryCreationError
    case fileCreationError
}

class DatasetEncoder {
    private var datasetDirectoryURL: URL
    
    public let cameraMatrixPath: URL
    public let cameraTransformPath: URL
    public let meshPath: URL
    
    private let cameraTransformEncoder: CameraTransformEncoder
    private let meshEncoder: MeshEncoder
    
    public var status: DatasetEncoderStatus = .allGood
    private var savedFrames: Int = 0
    private var counter: Int = 0
    public var capturedFrameIds: Set<UUID> = []
    
    init() {
        // Current date and time as a string
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        // Create a unique directory name using the date and time
        datasetDirectoryURL = DatasetEncoder.createDirectory(directoryName: dateString)
        
        self.cameraMatrixPath = datasetDirectoryURL.appendingPathComponent("camera_matrix.csv", isDirectory: false)
        self.cameraTransformPath = datasetDirectoryURL.appendingPathComponent("camera_transform.csv", isDirectory: false)
        self.meshPath = datasetDirectoryURL.appendingPathComponent("mesh", isDirectory: true)
        
        self.cameraTransformEncoder = CameraTransformEncoder(url: self.cameraTransformPath)
        self.meshEncoder = MeshEncoder(outDirectory: self.meshPath)
    }
    
    static private func createDirectory(directoryName: String) -> URL {
        let relativeTo = FileManager.default.urls(for:.documentDirectory, in: .userDomainMask).first!
        let directory = URL(filePath: directoryName, directoryHint: .isDirectory, relativeTo: relativeTo)
        if FileManager.default.fileExists(atPath: directory.path) {
            // Return existing directory if it already exists
            return directory
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            print("Error creating directory. \(error), \(error.userInfo)")
        }
        return directory
    }
    
    public func addData(
        frameId: UUID,
        meshBundle: MeshBundle,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        if (self.capturedFrameIds.contains(frameId)) {
            print("Frame with ID \(frameId) already exists. Skipping.")
            return
        }
        
        let frameNumber: UUID = frameId
        
        if let cameraTransform = meshBundle.cameraTransform {
            self.cameraTransformEncoder.add(transform: cameraTransform, timestamp: timestamp, frameNumber: frameNumber)
        }
        if let cameraIntrinsics = meshBundle.cameraIntrinsics {
            self.writeIntrinsics(cameraIntrinsics: cameraIntrinsics)
        }
        self.meshEncoder.save(meshBundle: meshBundle, frameNumber: frameNumber)
        
        savedFrames = savedFrames + 1
        self.capturedFrameIds.insert(frameNumber)
    }
    
    private func writeIntrinsics(cameraIntrinsics: simd_float3x3) {
        let rows = cameraIntrinsics.transpose.columns
        var csv: [String] = []
        for row in [rows.0, rows.1, rows.2] {
            let csvLine = "\(row.x), \(row.y), \(row.z)"
            csv.append(csvLine)
        }
        let contents = csv.joined(separator: "\n")
        do {
            try contents.write(to: self.cameraMatrixPath, atomically: true, encoding: String.Encoding.utf8)
        } catch let error {
            print("Could not write camera matrix. \(error.localizedDescription)")
        }
    }
}
