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
    public var status: DatasetEncoderStatus = .allGood
    
    public let cameraMatrixPath: URL
    public let cameraTransformPath: URL
    public let meshPath: URL
    
    private var counter: Int = 0
    
    init() {
        // Current date and time as a string
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        // Create a unique directory name using the date and time
        let defaultURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.datasetDirectoryURL = defaultURL.appendingPathComponent(dateString)
        
        self.cameraMatrixPath = datasetDirectoryURL.appendingPathComponent("camera_matrix.csv", isDirectory: false)
        self.cameraTransformPath = datasetDirectoryURL.appendingPathComponent("camera_transform.csv", isDirectory: false)
        self.meshPath = datasetDirectoryURL.appendingPathComponent("mesh", isDirectory: true)
    }
}
