//
//  TOCropVideoView.swift
//  ImageVideoCropper
//
//  Created by hari krishna on 13/07/2025.
//

import AVFoundation
import TOCropViewController
import UIKit

class TOCropVideoView: TOCropView {
    private var player: AVPlayer!
    private var url: URL!
    private var output: AVPlayerItemVideoOutput!
    private nonisolated(unsafe) var timeObserver: Any?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var preferredTransform: CGAffineTransform = .identity

    private let foregroundPlayerView: PlayerView = .init()
    private let backgroundPlayerView: PlayerView = .init()

    private(set) var duration: TimeInterval = 0.0 {
        didSet {
            controls.setPlaybackDuration(duration)
        }
    }

    private(set) var currentTime: TimeInterval = 0.0 {
        didSet {
            controls.setCurrentPlaybackTime(currentTime)
            let progress = currentTime / duration
            if progress >= 0 && progress <= 1 {
                controls.setCurrentPlaybackProgress(Float(progress))
            }
        }
    }

    private lazy var controls: TOCropViewPlayerControls = .init()

    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private lazy var context = { CIContext(options: [
        .workingColorSpace: colorSpace,
    ]) }()

    convenience init(url: URL, thumbnail: UIImage) {
        self.init(croppingStyle: .default, image: thumbnail)
        self.url = url

        let asset = AVURLAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            preferredTransform = track.preferredTransform
        }
        player = AVPlayer(playerItem: .init(asset: asset))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        foregroundPlayerView.frame = foregroundImageView.bounds
    }

    override func performInitialSetup() {
        super.performInitialSetup()

        setupPlayerViews()

        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        ])
        player.currentItem?.add(output)

        addSubview(controls)

        controls.layer.shadowColor = UIColor.black.cgColor
        controls.layer.shadowOpacity = 0.2
        controls.layer.shadowOffset = CGSize(width: 0, height: 1)
        controls.layer.shadowRadius = 1
        controls.delegate = self

        hideVideoLayer()

        setControlsFrame()

        observePlayerTime()
        observePlayerItemStatus()
    }

    deinit {
        timeControlStatusObserver = nil
        guard let timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }

    override func gridPanGestureRecognized(_ recognizer: UIPanGestureRecognizer) {
        hideControls()
        if case .ended = recognizer.state {
            showControlsWithDelay()
        }

        pause()

        super.gridPanGestureRecognized(recognizer)
    }

    override func scrollWillBeginZooming() {
        super.scrollWillBeginZooming()
        pause()
    }

    override func scrollWillBeginDragging() {
        super.scrollWillBeginDragging()
        pause()
    }

    override func scrollDidEndZooming() {
        super.scrollDidEndZooming()
        showControlsWithDelay()
        setNeedsLayout()
    }

    override func scrollDidEndDragging() {
        super.scrollDidEndDragging()
        showControlsWithDelay()
        setNeedsLayout()
    }

    override func scrollDidEndDecelerating() {
        super.scrollDidEndDecelerating()
        showControlsWithDelay()
        setNeedsLayout()
    }

    override func matchForegroundToBackground() {
        super.matchForegroundToBackground()

        setControlsFrame()
    }

    private func setupPlayerViews() {
        foregroundImageView.addSubview(foregroundPlayerView)
        foregroundPlayerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        foregroundPlayerView.frame = foregroundImageView.bounds
        (foregroundPlayerView.layer as! AVPlayerLayer).player = player

        backgroundImageView.addSubview(backgroundPlayerView)
        backgroundPlayerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundPlayerView.frame = backgroundImageView.bounds
        (backgroundPlayerView.layer as! AVPlayerLayer).player = player
    }

    private func synchronizeVideoFrameToImageView() {
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())

        if output.hasNewPixelBuffer(forItemTime: itemTime),
           let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            if preferredTransform.hasRotation {
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let transform = preferredTransform.concatenating(CGAffineTransform(scaleX: -1, y: -1).translatedBy(x: 0, y: -CGFloat(height)))

                let normalized = ciImage.transformed(by: transform)

                ciImage = normalized.transformed(by: CGAffineTransform(translationX: -normalized.extent.minX,
                                                                       y: -normalized.extent.minY))
            }

            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: colorSpace) {
                let image = UIImage(cgImage: cgImage)
                foregroundImageView.image = image
                backgroundImageView.image = image
            }
        }
    }

    private func hideVideoLayer() {
        foregroundPlayerView.isHidden = true
        backgroundPlayerView.isHidden = true
    }

    private func showVideoLayer() {
        foregroundPlayerView.frame = foregroundImageView.bounds
        foregroundPlayerView.isHidden = false

        backgroundPlayerView.frame = backgroundImageView.bounds
        backgroundPlayerView.isHidden = false
    }

    private func play() {
        player.play()
        showVideoLayer()
    }

    private func pause() {
        player.pause()
        synchronizeVideoFrameToImageView()
        hideVideoLayer()
    }

    private func hideControls(animate: Bool = true) {
        if animate {
            UIView.animate(withDuration: 1.25, delay: 0.0, options: .curveEaseIn) {
                self.controls.isHidden = true
            }
        } else {
            controls.isHidden = true
        }
    }

    private func showControlsWithDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + cropAdjustingDelay) {
            UIView.animate(withDuration: 1.25, delay: 0.0, options: .curveEaseIn) {
                self.controls.isHidden = false
            }
        }
    }

    private func setControlsFrame() {
        controls.frame = CGRect(x: foregroundContainerView.frame.minX + 20, y: foregroundContainerView.frame.maxY - 60, width: foregroundContainerView.frame.width - 40, height: 40)
    }

    private func observePlayerTime() {
        let interval = CMTime(value: 1, timescale: 10)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval,
                                                      queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                // Update the published currentTime and duration values.
                currentTime = time.seconds
                duration = player.currentItem?.duration.seconds ?? 0.0
            }
        }
    }

    private func observePlayerItemStatus() {
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                switch player.timeControlStatus {
                case .playing:
                    controls.playerStatus = .playing
                case .paused:
                    controls.playerStatus = .paused
                case .waitingToPlayAtSpecifiedRate:
                    print("Buffering / Waiting")
                @unknown default:
                    break
                }
            }
        }
    }

    func handleBeforeRotation() {
        pause()
        hideControls(animate: false)
        showControlsWithDelay()
    }

    func handleBeforeReset() {
        pause()
        hideControls(animate: false)
        showControlsWithDelay()
    }

    class PlayerView: UIView {
        override class var layerClass: AnyClass {
            return AVPlayerLayer.self
        }
    }
}

extension TOCropVideoView: @preconcurrency TOCropViewPlayerControlsDelegate {
    func toCropViewPlayerControlsDidTapPlayPause(_ controls: TOCropViewPlayerControls) {
        if currentTime >= duration {
            player.seek(to: .zero)
        }
        if player.timeControlStatus == .paused {
            play()
        } else if player.timeControlStatus == .playing {
            pause()
        }
    }

    func toCropViewPlayerControlsDidChangeSliderValue(_ controls: TOCropViewPlayerControls, value: Float) {
        player.pause()
        guard let timeScale = player.currentItem?.duration.timescale else { return }
        let newTimeSeconds = duration * TimeInterval(value)
        let newTime = CMTime(seconds: newTimeSeconds, preferredTimescale: timeScale)

        player.seek(to: newTime)
        currentTime = newTimeSeconds
    }
}
