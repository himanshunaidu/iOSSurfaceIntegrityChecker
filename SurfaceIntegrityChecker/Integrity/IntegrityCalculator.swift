//
//  AnchorIntegrityCalculator.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/28/25.
//

import Foundation
import ARKit

class IntegrityCalculator {
    private var connectedComponentsCalculator: ConnectedComponents = ConnectedComponents()
    
    func calculateIntegrity(of meshBundle: MeshBundle) -> Bool {
        let deviantMesh = meshBundle.redEntity.model?.mesh
        guard let deviantMesh else {
            print("No mesh found for the red entity.")
            return false
        }
        
        let connectedComponents = connectedComponentsCalculator.getConnectedComponents(deviantMesh)
//        print("Areas of connected components: \(connectedComponents.map { $0.totalArea })")
        let totalArea = connectedComponents.reduce(0, { $0 + $1.totalArea})
        
        return totalArea > 0.1
    }
}
