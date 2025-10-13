//
//  ContentView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/5/25.
//

import SwiftUI

enum IntegrityStatus: CaseIterable, Identifiable, CustomStringConvertible {
    var id: Self { self }
    
    case intact
    case compromised
    
    var description: String {
        switch self {
        case .intact:
            return "The surface is intact."
        case .compromised:
            return "The surface has integrity issues."
        }
    }
}

struct ContentView: View {
    
    @State var arResources: MeshBundle?
    private func getARResources(meshBundle: MeshBundle?, shouldCallResourceUpdateCallback: Bool) {
        guard shouldCallResourceUpdateCallback, let meshBundle else { return }
        self.arResources = meshBundle
    }
    @State var shouldCallResourceUpdateCallback: Bool = true
    
    @State var showIntegritySheet = false
    @State var integrityResult: IntegrityStatus = .intact
    
    private var integrityCalculator: IntegrityCalculator = IntegrityCalculator()
//    private var datasetEncoder = DatasetEncoder(rootDirectoryName: "Experiment_4")
    
    var body: some View {
        ARViewControllerContainer(
            // Normalized ROI in top-left UIKit coords (0...1)
            roiTopLeft: CGRect(x: 0.60, y: 0.08, width: 0.32, height: 0.32),
            overlaySize: CGSize(width: 160, height: 160),
            showDebug: true,
            arResourceUpdateCallback: getARResources,
            shouldCallResourceUpdateCallback: $shouldCallResourceUpdateCallback
        )
        .ignoresSafeArea()
//        ARViewSingleFloorContainer().ignoresSafeArea()
        
        VStack {
            Button("Analyze") {
                shouldCallResourceUpdateCallback = false
                var integrity: Bool = false
                if let arResources = arResources {
                    integrity = integrityCalculator.calculateIntegrity(of: arResources)
                    // Save the dataset for future reference
//                    do {
//                        try datasetEncoder.addData(frameString: UUID().uuidString, meshBundle: arResources)
//                    } catch {
//                        print("Failed to save dataset: \(error)")
//                    }
                } else {
                    print("No AR Resources available for integrity calculation.")
                }
                integrityResult = integrity ? .compromised : .intact
                showIntegritySheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        
        .sheet(isPresented: $showIntegritySheet, onDismiss: {
            shouldCallResourceUpdateCallback = true
        }) {
            IntegrityResultView(integrityResult: integrityResult, arResources: arResources)
        }
        .onChange(of: showIntegritySheet) { isPresented in
            shouldCallResourceUpdateCallback = !isPresented
        }
    }
}

//#Preview {
//    ContentView()
//}
