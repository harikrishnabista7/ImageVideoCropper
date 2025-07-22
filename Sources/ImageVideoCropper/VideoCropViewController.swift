//
//  VideoCropViewController.swift
//  ImageVideoCropper
//
//  Created by hari krishna on 16/07/2025.
//
import AVFoundation
import TOCropViewController

class VideoCropViewController: TOCropViewController, @preconcurrency TOCropViewDelegate {
    private var videoCropView: TOCropVideoView!

    var onDidCropVideoToRect: ((URL, CGRect, NSInteger) -> Void)?

    var onDidCancelWithError: ((Error) -> Void)?

    private lazy var progressContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0.8
        return view
    }()

    private lazy var progressView: UIProgressView = {
        let view = UIProgressView()
        view.progressViewStyle = .bar
        view.tintColor = .white
        return view
    }()

    private var url: URL!

    convenience init(url: URL) {
        guard let thumbnail = url.getThumbnail() else {
            fatalError("Could not load thumbnail for video at \(url)")
        }

        self.init(croppingStyle: .default, image: thumbnail)
        self.url = url
        videoCropView = TOCropVideoView(url: url, thumbnail: thumbnail)
    }

    override func viewDidLoad() {
        videoCropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoCropView.delegate = self
        view.addSubview(videoCropView)

        super.viewDidLoad()

        extendToolbarTargets()
    }

    private func showProgressView() {
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.text = "Exporting..."

        progressContainerView.frame = view.bounds
        view.addSubview(progressContainerView)

        label.frame = CGRect(x: 20, y: view.bounds.height - 130, width: view.bounds.width - 40, height: 30)
        progressView.frame = CGRect(x: 0, y: view.bounds.height - 100, width: view.bounds.width, height: 5)
        progressContainerView.addSubview(label)
        progressContainerView.addSubview(progressView)
    }

    private func hideProgressView() {
        progressContainerView.removeFromSuperview()
    }

    override var cropView: TOCropView {
        return videoCropView
    }

    private func extendToolbarTargets() {
        toolbar.rotateClockwiseButton?.addTarget(self, action: #selector(rotateButtonTouchDown), for: .touchDown)

        toolbar.rotateCounterclockwiseButton.addTarget(self, action: #selector(rotateButtonTouchDown), for: .touchDown)

        toolbar.resetButton.addTarget(self, action: #selector(resetButtonTouchDown), for: .touchDown)

        toolbar.doneButtonTapped = doneButtonTapped
    }

    private func doneButtonTapped() {
        if let onDidCropVideoToRect = onDidCropVideoToRect {
            Task {
                showProgressView()
                let angle = CGFloat(cropView.angle) * (CGFloat.pi / 180.0)
                do {
                    let url = try await VideoCropper.shared.cropVideo(url: url, cropRect: self.imageCropFrame, angleInRadians: angle) { [weak self] progress in
                        Task { @MainActor in
                            self?.progressView.progress = Float(progress)
                        }
                    }
                    hideProgressView()
                    onDidCropVideoToRect(url, imageCropFrame, 0)
                    presentingViewController?.dismiss(animated: true)
                } catch {
                    onDidCancelWithError?(error)
                    hideProgressView()
                    presentingViewController?.dismiss(animated: true)
                }
            }
        }
    }

    @objc private func rotateButtonTouchDown() {
        videoCropView.handleBeforeRotation()
    }

    @objc private func resetButtonTouchDown() {
        videoCropView.handleBeforeReset()
    }

    @objc
    func cropViewDidBecomeResettable(_ cropView: TOCropView) {
        toolbar.resetButtonEnabled = true
    }

    @objc
    func cropViewDidBecomeNonResettable(_ cropView: TOCropView) {
        toolbar.resetButtonEnabled = false
    }
}

fileprivate extension URL {
    func getThumbnail() -> UIImage? {
        let asset = AVURLAsset(url: self)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTimeMakeWithSeconds(1, preferredTimescale: 60)
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)

            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}
