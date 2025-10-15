//
//  IntegrityResultImageView.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/13/25.
//


import SwiftUI


class IntegrityResultImageViewController: UIViewController {
    var imageView: UIImageView! = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = UIColor(white: 0, alpha: 0.35)
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    var meshOverlayView: UIImageView! = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = UIColor(white: 0, alpha: 0.35)
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    var arResources: MeshBundle?
    var meshOverlayImage: UIImage? = nil
    
    var cameraUIImage: UIImage? = nil
    var selection:[Int] = []
    var classes: [String] = []
    
    init(arResources: MeshBundle?, meshOverlayImage: UIImage? = nil) {
//        self.imageView = UIImageView()
//        self.meshOverlayView = UIImageView()
        self.arResources = arResources
        self.meshOverlayImage = meshOverlayImage
        super.init(nibName: nil, bundle: nil)
        self.updateResources(arResources)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get view dimensions
        print("View dimensions: \(view.bounds.size)")
        
//        imageView.contentMode = .scaleAspectFit
//        imageView.translatesAutoresizingMaskIntoConstraints = false
//        imageView.image = cameraUIImage

        view.addSubview(imageView)

        NSLayoutConstraint.deactivate(imageView.constraints)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//            segmentationView.widthAnchor.constraint(equalTo: segmentationView.heightAnchor, multiplier: aspectRatio)
        ])
        
//        meshOverlayView.contentMode = .scaleAspectFit
//        meshOverlayView.translatesAutoresizingMaskIntoConstraints = false
        meshOverlayView.image = meshOverlayImage
        
        view.addSubview(meshOverlayView)
        
        NSLayoutConstraint.deactivate(meshOverlayView.constraints)
        NSLayoutConstraint.activate([
            meshOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            meshOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            meshOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            meshOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        print("Updated View dimensions: \(view.bounds.size)")
    }
    
    private var aspectRatio: CGFloat {
        guard let image = cameraUIImage else { return 1.0 }
        return image.size.width / image.size.height
    }
    
    func updateResources(_ newResources: MeshBundle?, meshOverlayImage: UIImage? = nil) {
        if var newCameraImage = newResources?.cameraImage {
            newCameraImage = newCameraImage.oriented(newResources?.orientation ?? .right)
            self.cameraUIImage = UIImage(ciImage: newCameraImage)
            self.imageView.image = self.cameraUIImage
        }
        if var newMeshOverlayImage = meshOverlayImage {
            newMeshOverlayImage = orientImage(newMeshOverlayImage, to: newResources?.orientation ?? .right) ?? newMeshOverlayImage
            self.meshOverlayImage = newMeshOverlayImage
            self.meshOverlayView.image = self.meshOverlayImage
        }
    }
    
    private func orientImage(_ image: UIImage, to orientation: CGImagePropertyOrientation) -> UIImage? {
        guard let cgimg = image.cgImage else { return image }
        
        let size = CGSize(width: cgimg.width, height: cgimg.height)
        let t = orientation.toUpTransform(for: size)
        
        var ciImage = CIImage(cgImage: cgimg)
        ciImage = ciImage.transformed(by: t)
        
        let orientedImg = UIImage(ciImage: ciImage)
        return orientedImg
    }
}

struct HostedIntegrityResultImageViewController: UIViewControllerRepresentable{
    @Binding var arResources: MeshBundle?
    @Binding var meshOverlayImage: UIImage?
    
    func makeUIViewController(context: Context) -> IntegrityResultImageViewController {
        let viewController = IntegrityResultImageViewController(arResources: arResources)
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: IntegrityResultImageViewController, context: Context) {
        uiViewController.updateResources(arResources, meshOverlayImage: meshOverlayImage)
    }
}
