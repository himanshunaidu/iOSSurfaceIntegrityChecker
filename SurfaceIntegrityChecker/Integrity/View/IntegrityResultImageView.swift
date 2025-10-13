//
//  IntegrityResultImageView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/13/25.
//


import SwiftUI


class IntegrityResultImageViewController: UIViewController {
    var imageView: UIImageView! = nil
    
    var cameraImage: UIImage?
    
    var selection:[Int] = []
    var classes: [String] = []
    
    init(cameraImage: UIImage?) {
        self.imageView = UIImageView()
        self.cameraImage = cameraImage
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = cameraImage

        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//            segmentationView.widthAnchor.constraint(equalTo: segmentationView.heightAnchor, multiplier: aspectRatio)
        ])
    }
    
    private var aspectRatio: CGFloat {
        guard let image = cameraImage else { return 1.0 }
        return image.size.width / image.size.height
    }
}

struct HostedIntegrityResultImageViewController: UIViewControllerRepresentable{
    @Binding var cameraImage: UIImage?
    
    func makeUIViewController(context: Context) -> IntegrityResultImageViewController {
        let viewController = IntegrityResultImageViewController(cameraImage: cameraImage)
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: IntegrityResultImageViewController, context: Context) {
        uiViewController.imageView.image = cameraImage
    }
}
