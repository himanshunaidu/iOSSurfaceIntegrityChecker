//
//  AnnotationDetailInstanceView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/17/25.
//
import SwiftUI

struct AnnotationInstanceDetailView: View {
    var selectedObjectId: UUID
    @Binding var selectedObjectWidth: Float
    @Binding var selectedObjectBreakage: Bool
    @Binding var selectedObjectSlope: Float
    @Binding var selectedObjectCrossSlope: Float
    
    @Environment(\.presentationMode) var presentationMode
    
    var numberFormatter: NumberFormatter = {
        var nf = NumberFormatter()
        nf.numberStyle = .decimal
        return nf
    }()
    
    var body: some View {
        VStack {
            Text("Annotation Instance Details")
                .font(.title)
                .padding()
            
            Form {
                Section(header: Text("Object ID")) {
                    Text(selectedObjectId.uuidString)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Width")) {
                    TextField("Width in meters", value: $selectedObjectWidth, formatter: numberFormatter)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                }
                
                Section(header: Text("Breakage Status")) {
                    Toggle(isOn: $selectedObjectBreakage) {
                        Text("Potential Breakage")
                    }
                }
                
                Section(header: Text("Slope")) {
                    TextField("Slope in degrees", value: $selectedObjectSlope, formatter: numberFormatter)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                }
                
                Section(header: Text("Cross Slope")) {
                    TextField("Cross Slope in degrees", value: $selectedObjectCrossSlope, formatter: numberFormatter)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                }
            }
        }
    }
}
