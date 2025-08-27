//
//  ContentView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/5/25.
//

import SwiftUI

struct ContentView: View {
    
    var body: some View {
        ARViewControllerContainer(
            // Normalized ROI in top-left UIKit coords (0...1)
            roiTopLeft: CGRect(x: 0.60, y: 0.08, width: 0.32, height: 0.32),
            overlaySize: CGSize(width: 160, height: 160),
            showDebug: true
        )
        .ignoresSafeArea()
//        ARViewSingleFloorContainer().ignoresSafeArea()
    }
}

//#Preview {
//    ContentView()
//}
