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

enum DatasetEncodingError: Error, LocalizedError {
    case directoryAlreadyExists
    
    var errorDescription: String? {
        switch self {
        case .directoryAlreadyExists:
            return "Directory already exists."
        }
    }
}

/**
 Encoder for saving dataset frames and metadata.

 This encoder saves RGB, depth, and segmentation images along with camera intrinsics, location, and other details.
 Finally, it also adds a node to TDEI workspaces at the capture location.
 
 Storage Format:
    - Root Directory Name (this will be hardcoded)
     - Directory Name: (this is provided or generated using current date and time)
        - camera_matrix.csv
        - camera_transform.csv
        - mesh.ply
        - rgb.png
        - depth.png
        - confidence.png
        - location.csv
        - other_details.csv
 */
class DatasetEncoder {
    private var rootDirectoryURL: URL
    private var datasetDirectoryURL: URL
    
    public let cameraMatrixPath: URL
    public let cameraTransformPath: URL
    public let meshPath: URL
    public let rgbFilePath: URL
    public let depthFilePath: URL
    public let confidenceFilePath: URL
    public let locationPath: URL
    public let otherDetailsPath: URL
    
    private let cameraTransformEncoder: CameraTransformEncoder
    private let meshEncoder: MeshEncoder
    private let rgbEncoder: RGBEncoder
    private let depthEncoder: DepthEncoder
    private let confidenceEncoder: ConfidenceEncoder
    private let locationEncoder: LocationEncoder
    private let otherDetailsEncoder: OtherDetailsEncoder
    
//    public var status: DatasetEncoderStatus = .allGood
    private var savedFrames: Int = 0
    private var counter: Int = 0
    public var capturedFrameIds: Set<String> = []
    
    init(rootDirectoryName: String, directoryName: String? = nil) throws {
        rootDirectoryURL = DatasetEncoder.createDirectory(directoryName: rootDirectoryName)
        
        // Current date and time as a string
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        // Create a unique directory name using the date and time
        let directoryName = directoryName ?? dateString
        if (DatasetEncoder.checkDirectory(directoryName: directoryName, relativeTo: rootDirectoryURL)) {
            throw DatasetEncodingError.directoryAlreadyExists
        }
        datasetDirectoryURL = DatasetEncoder.createDirectory(directoryName: directoryName, relativeTo: rootDirectoryURL)
        
        self.cameraMatrixPath = datasetDirectoryURL.appendingPathComponent("camera_matrix.csv", isDirectory: false)
        self.cameraTransformPath = datasetDirectoryURL.appendingPathComponent("camera_transform.csv", isDirectory: false)
        self.meshPath = datasetDirectoryURL.appendingPathComponent("mesh", isDirectory: true)
        self.rgbFilePath = datasetDirectoryURL.appendingPathComponent("rgb", isDirectory: true)
        self.depthFilePath = datasetDirectoryURL.appendingPathComponent("depth", isDirectory: true)
        self.confidenceFilePath = datasetDirectoryURL.appendingPathComponent("confidence", isDirectory: true)
        self.locationPath = datasetDirectoryURL.appendingPathComponent("location.csv", isDirectory: false)
        self.otherDetailsPath = datasetDirectoryURL.appendingPathComponent("other_details.csv", isDirectory: false)
        
        self.cameraTransformEncoder = CameraTransformEncoder(url: self.cameraTransformPath)
        self.meshEncoder = MeshEncoder(outDirectory: self.meshPath)
        self.rgbEncoder = RGBEncoder(outDirectory: self.rgbFilePath)
        self.depthEncoder = DepthEncoder(outDirectory: self.depthFilePath)
        self.confidenceEncoder = ConfidenceEncoder(outDirectory: self.confidenceFilePath)
        self.locationEncoder = LocationEncoder(url: self.locationPath)
        self.otherDetailsEncoder = OtherDetailsEncoder(url: self.otherDetailsPath)
    }
    
    static private func checkDirectory(directoryName: String, relativeTo: URL? = nil) -> Bool {
        var relativeTo = relativeTo
        if relativeTo == nil {
            relativeTo = FileManager.default.urls(for:.documentDirectory, in: .userDomainMask).first!
        }
        let directory = URL(filePath: directoryName, directoryHint: .isDirectory, relativeTo: relativeTo)
        if FileManager.default.fileExists(atPath: directory.path) {
            // Return existing directory if it already exists
            return true
        }
        return false
    }
    
    static private func createDirectory(directoryName: String, relativeTo: URL? = nil) -> URL {
        var relativeTo = relativeTo
        if relativeTo == nil {
            relativeTo = FileManager.default.urls(for:.documentDirectory, in: .userDomainMask).first!
        }
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
        frameString: String,
        meshBundle: MeshBundle,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) throws {
        if (self.capturedFrameIds.contains(frameString)) {
            print("Frame with Name \(frameString) already exists. Skipping.")
            throw DatasetEncodingError.directoryAlreadyExists
//            return
        }
        
//        let frameNumber: UUID = frameId
        
        if let cameraTransform = meshBundle.cameraTransform {
            self.cameraTransformEncoder.add(transform: cameraTransform, timestamp: timestamp, frameString: frameString)
        }
        if let cameraIntrinsics = meshBundle.cameraIntrinsics {
            self.writeIntrinsics(cameraIntrinsics: cameraIntrinsics)
        }
        if let cameraImage = meshBundle.cameraImage {
            self.rgbEncoder.save(ciImage: cameraImage, frameString: frameString)
        }
        if let depthImage = meshBundle.depthImage {
            self.depthEncoder.save(ciImage: depthImage, frameString: frameString)
        }
        if let confidenceBuffer = meshBundle.confidenceBuffer {
            self.confidenceEncoder.encodeFrame(frame: confidenceBuffer, frameString: frameString)
        }
        if let location = meshBundle.location {
            let locationData: LocationData = LocationData(timestamp: timestamp, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            self.locationEncoder.add(locationData: locationData, frameString: frameString)
        }
        self.meshEncoder.save(meshBundle: meshBundle, frameString: frameString)
        
        savedFrames = savedFrames + 1
        self.capturedFrameIds.insert(frameString)
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
