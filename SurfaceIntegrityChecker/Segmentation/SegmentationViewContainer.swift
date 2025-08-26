//
//  SegmentationViewContainer.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 8/26/25.
//
import SwiftUI

struct SegmentationViewContainer: UIViewRepresentable {
    let segmentationImage: UIImage
    let imageView = UIImageView(frame: .zero)
    
    func makeUIView(context: Context) -> UIImageView {
//        let imageView = UIImageView(frame: .zero)
        imageView.contentMode = .scaleAspectFit
        imageView.image = segmentationImage
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        // Update the view if needed
        uiView.image = segmentationImage
    }
}
