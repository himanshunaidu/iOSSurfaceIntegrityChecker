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
        ARViewSingleFloorContainer().edgesIgnoringSafeArea(.all)
//        ARPointCloudViewContainer().edgesIgnoringSafeArea(.all)
    }
}

//#Preview {
//    ContentView()
//}
