//
//  IntegrityResultView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/13/25.
//
import SwiftUI

struct IntegrityResultView: View {
    var ROOT_DIRECTORY_NAME = "Experiment_4"
    
    @State var datasetName: String = ""
    @State private var datasetSaveSuccess: Bool = false
    @State private var datasetSaveError: String? = nil
    @State var integrityCalculator: IntegrityCalculator = IntegrityCalculator()
    @State var integrityResults: IntegrityResults = IntegrityResults()
    @State var arResources: MeshBundle?
    
    var body: some View {
        VStack {
            Text("Surface Integrity Result")
                .font(.title)
                .padding()
            
            if (arResources != nil) {
                HostedIntegrityResultImageViewController(arResources: $arResources)
            }
            
//            Text((integrityResult == .intact) ? "The surface is intact." : "The surface has integrity issues.")
//                .font(.headline)
//                .foregroundColor((integrityResult == .intact) ? .green : .red)
//                .padding()
            Picker("Status", selection: $integrityResults.integrityStatus) {
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
            if datasetSaveSuccess {
                Text("Dataset saved successfully!")
                    .foregroundColor(.green)
                    .padding()
            }
            
            Button("Save Result") {
                // Action to save the result
                if let arResources = arResources {
                    let datasetName = datasetName.isEmpty ? UUID().uuidString : datasetName
                    do {
                        let datasetEncoder = try DatasetEncoder(rootDirectoryName: ROOT_DIRECTORY_NAME, directoryName: datasetName)
                        try datasetEncoder.addData(frameString: UUID().uuidString, meshBundle: arResources)
                    } catch {
                        datasetSaveSuccess = false
                        datasetSaveError = "Failed to save dataset: \(error)"
                        print(datasetSaveError!)
                        return
                    }
                    datasetSaveSuccess = true
                    datasetSaveError = nil
                } else {
                    print("No AR Resources available for saving.")
                }
            }
        }
        .onAppear() {
            if let arResources = arResources,
               let integrityResults = integrityCalculator.getIntegrityResults(arResources)
            {
                self.integrityResults = integrityResults
            }
        }
    }
}
