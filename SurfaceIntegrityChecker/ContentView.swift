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
    private func getARResources(meshBundle: MeshBundle?) {
        self.arResources = meshBundle
    }
    
    @State var showIntegritySheet = false
    @State var integrityResult: IntegrityStatus = .intact
    
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
        
        .sheet(isPresented: $showIntegritySheet) {
            IntegrityResultView(integrityResult: integrityResult, arResources: arResources)
        }
    }
}

struct IntegrityResultView: View {
    @State var integrityResult: IntegrityStatus
    @State var datasetName: String = ""
    @State private var datasetSaveError: String? = nil
    var arResources: MeshBundle?
    
    var body: some View {
        VStack {
            Text("Surface Integrity Result")
                .font(.title)
                .padding()
//            Text((integrityResult == .intact) ? "The surface is intact." : "The surface has integrity issues.")
//                .font(.headline)
//                .foregroundColor((integrityResult == .intact) ? .green : .red)
//                .padding()
            Picker("Status", selection: $integrityResult) {
                ForEach(IntegrityStatus.allCases) { option in
                    Text(String(describing: option))
                }
            }
            
            TextField("Dataset Name", text: $datasetName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            if let error = datasetSaveError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            Button("Save Result") {
                // Action to save the result
                if let arResources = arResources {
                    let datasetName = datasetName.isEmpty ? UUID().uuidString : datasetName
                    let datasetEncoder = DatasetEncoder(rootDirectoryName: "Experiment_1", directoryName: datasetName)
                    do {
                        try datasetEncoder.addData(frameString: UUID().uuidString, meshBundle: arResources)
                    } catch {
                        datasetSaveError = "Failed to save dataset: \(error)"
                        print(datasetSaveError!)
                    }
                } else {
                    print("No AR Resources available for saving.")
                }
            }
        }
    }
}

//#Preview {
//    ContentView()
//}
