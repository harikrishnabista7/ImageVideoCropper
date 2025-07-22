//
//  VideoCropperViewController.swift
//  ImageVideoCropperExample
//
//  Created by hari krishna on 22/07/2025.
//

import AVKit
import PhotosUI
import UIKit
import ImageVideoCropper

class VideoCropperDemoViewController: UIViewController, HBCropViewControllerDelegate {
    @IBOutlet var editBar: UIView!
    @IBOutlet var videoContainerView: UIView!
    private var player: AVPlayer?

    private var videoURL: URL? {
        didSet {
            editBar.isHidden = videoURL == nil
            showViewPlayer()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // Do any additional setup after loading the view.
    }

    @IBAction func showGallery(_ sender: Any) {
        showGallery(.videos)
    }

    @IBAction func editVideo(_ sender: Any) {
        guard let videoURL else { return }
        player?.pause()
        let cropper = HBCropViewController(videoURL: videoURL)
        cropper.delegate = self
        present(cropper, animated: true)
    }

    private func showViewPlayer() {
        guard let videoURL else { return }
        let vc = AVPlayerViewController()
        addChild(vc)
        player = AVPlayer(url: videoURL)
        vc.player = player
        videoContainerView.addSubview(vc.view)
        vc.view.frame = videoContainerView.bounds
        vc.didMove(toParent: self)
    }
    
    func cropViewController(_ cropViewController: HBCropViewController, didCropToVideo url: URL, withRect cropRect: CGRect, angle: Int) {
        self.videoURL = url
    }
    
    private func showProgress() {
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.frame = CGRect(origin: .zero, size: .init(width: 40, height: 40))
        videoContainerView.addSubview(activityIndicator)
        activityIndicator.center = videoContainerView.center
        activityIndicator.startAnimating()
    }
    private func hideProgress() {
        videoContainerView.subviews.forEach { $0.removeFromSuperview() }
    }
}

extension VideoCropperDemoViewController: GalleryPresenter, PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        showProgress()
        Task {
            if let url = await results.firstVideoURL() {
                await MainActor.run {
                    hideProgress()
                    videoURL = url
                }
            }
            
            
        }
    }
}
