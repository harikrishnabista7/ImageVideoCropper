//
//  ImageCropperDemoViewController.swift
//  ImageVideoCropperExample
//
//  Created by hari krishna on 22/07/2025.
//

import ImageVideoCropper
import PhotosUI
import UIKit

class ImageCropperDemoViewController: UIViewController {
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var editBar: UIView!

    var currentImage: UIImage? {
        didSet {
            editBar.isHidden = currentImage == nil
            imageView.image = currentImage
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    @IBAction func addImage(_ sender: Any) {
        showGallery(.images)
    }

    @IBAction func cropImage(_ sender: Any) {
        guard let currentImage = currentImage else { return }
        let cropper = HBCropViewController(image: currentImage)
        cropper.delegate = self
        present(cropper, animated: true)
    }
}

extension ImageCropperDemoViewController: HBCropViewControllerDelegate {
    func cropViewController(_ cropViewController: HBCropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
        currentImage = image
        cropViewController.dismiss(animated: true)
    }
}

extension ImageCropperDemoViewController: GalleryPresenter, PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        Task {
            if let image = await results.firstImage() {
                await MainActor.run {
                    self.currentImage = image
                }
            }
        }
    }
}
