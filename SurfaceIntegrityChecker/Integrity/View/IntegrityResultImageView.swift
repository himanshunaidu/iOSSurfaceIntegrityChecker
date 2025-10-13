//
//  IntegrityResultImageView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/13/25.
//


import SwiftUI


class IntegrityResultImageViewController: UIViewController {
    var imageView: UIImageView! = nil
    
    var arResources: MeshBundle?
    
    var cameraUIImage: UIImage? = nil
    var selection:[Int] = []
    var classes: [String] = []
    
    init(arResources: MeshBundle?) {
        self.imageView = UIImageView()
        self.arResources = arResources
        super.init(nibName: nil, bundle: nil)
        self.updateResources(arResources)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = cameraUIImage

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
        guard let image = cameraUIImage else { return 1.0 }
        return image.size.width / image.size.height
    }
    
    func updateResources(_ newResources: MeshBundle?) {
        if var newCameraImage = newResources?.cameraImage {
//            newCameraImage = newCameraImage.oriented(newResources?.orientation ?? .right)
            self.cameraUIImage = UIImage(ciImage: newCameraImage)
            self.imageView.image = self.cameraUIImage
        }
    }
}

struct HostedIntegrityResultImageViewController: UIViewControllerRepresentable{
    @Binding var arResources: MeshBundle?
    
    func makeUIViewController(context: Context) -> IntegrityResultImageViewController {
        let viewController = IntegrityResultImageViewController(arResources: arResources)
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: IntegrityResultImageViewController, context: Context) {
        uiViewController.updateResources(arResources)
    }
}
