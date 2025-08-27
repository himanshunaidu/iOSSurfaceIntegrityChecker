//
//  SharedData.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/26/25.
//
import SwiftUI
import ARKit


class SharedData: ObservableObject {
    @Published var capturedImage: CVPixelBuffer?
}
