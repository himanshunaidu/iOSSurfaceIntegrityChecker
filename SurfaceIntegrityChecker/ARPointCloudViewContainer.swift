//
//  ARPointCloudViewContainer.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/7/25.
//

import SwiftUI
import ARKit
import SceneKit

struct ARPointCloudViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.sceneReconstruction = .meshWithClassification
        config.planeDetection = [.horizontal]
        view.session.run(config)

        // ✅ Built-in yellow point cloud
        view.debugOptions = [.showFeaturePoints, .showWorldOrigin]

        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) { }
}
