//
//  ContentView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/5/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
//            ARViewContainer().edgesIgnoringSafeArea(.all)
        ZStack {
            ARViewSingleFloorContainer().edgesIgnoringSafeArea(.all)
            SegmentationViewContainer().edgesIgnoringSafeArea(.all)
        }
//        ARPointCloudViewContainer().edgesIgnoringSafeArea(.all)
    }
}

//#Preview {
//    ContentView()
//}
