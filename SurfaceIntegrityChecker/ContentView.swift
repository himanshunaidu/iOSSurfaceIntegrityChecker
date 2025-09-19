//
//  ContentView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/5/25.
//

import SwiftUI

struct ContentView: View {
    
    @State var arResources: MeshBundle?
    private func getARResources(meshBundle: MeshBundle?) {
        self.arResources = meshBundle
    }
    
    @State var showIntegritySheet = false
    @State var integrityResult: Bool = false
    
    private var integrityCalculator: IntegrityCalculator = IntegrityCalculator()
    private var datasetEncoder = DatasetEncoder(rootDirectoryName: "Experiment_1")
    
    var body: some View {
        ARViewControllerContainer(
            // Normalized ROI in top-left UIKit coords (0...1)
            roiTopLeft: CGRect(x: 0.60, y: 0.08, width: 0.32, height: 0.32),
            overlaySize: CGSize(width: 160, height: 160),
            showDebug: true,
            arResourceUpdateCallback: getARResources
        )
        .ignoresSafeArea()
//        ARViewSingleFloorContainer().ignoresSafeArea()
        
        VStack {
            Button("Analyze") {
                var integrity: Bool = false
                if let arResources = arResources {
                    integrity = integrityCalculator.calculateIntegrity(of: arResources)
                    // Save the dataset for future reference
                    do {
                        try datasetEncoder.addData(frameString: UUID().uuidString, meshBundle: arResources)
                    } catch {
                        print("Failed to save dataset: \(error)")
                    }
                } else {
                    print("No AR Resources available for integrity calculation.")
                }
                integrityResult = integrity
                showIntegritySheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        
        .sheet(isPresented: $showIntegritySheet) {
            IntegrityResultView(integrityResult: integrityResult)
        }
    }
}

struct IntegrityResultView: View {
    var integrityResult: Bool
    
    var body: some View {
        VStack {
            Text("Surface Integrity Result")
                .font(.title)
                .padding()
            Text(!integrityResult ? "The surface is intact." : "The surface has integrity issues.")
                .font(.headline)
                .foregroundColor(!integrityResult ? .green : .red)
                .padding()
        }
    }
}

//#Preview {
//    ContentView()
//}
