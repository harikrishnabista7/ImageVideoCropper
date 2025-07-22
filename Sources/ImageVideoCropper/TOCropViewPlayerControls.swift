//
//  ToCropViewPlayerControls.swift
//  ImageVideoCropper
//
//  Created by hari krishna on 13/07/2025.
//

import UIKit

protocol TOCropViewPlayerControlsDelegate: AnyObject {
    func toCropViewPlayerControlsDidTapPlayPause(_ controls: TOCropViewPlayerControls)
    func toCropViewPlayerControlsDidChangeSliderValue(_ controls: TOCropViewPlayerControls, value: Float)
}

enum TOCropViewPlayerStatus {
    case playing
    case paused
}

class TOCropViewPlayerControls: UIView {
    var playerStatus: TOCropViewPlayerStatus = .paused {
        didSet {
            switch playerStatus {
            case .playing:
                playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            case .paused:
                playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            }
        }
    }

    func setPlaybackDuration(_ duration: TimeInterval) {
        durationLabel.text = duration.timeFormatted
    }

    func setCurrentPlaybackTime(_ time: TimeInterval) {
        currentTimeLabel.text = time.timeFormatted
    }

    func setCurrentPlaybackProgress(_ progress: Float) {
        progressView.progress = progress
    }

    weak var delegate: TOCropViewPlayerControlsDelegate?

    private lazy var playButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "play.fill"), for: .normal)

        let action = UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.toCropViewPlayerControlsDidTapPlayPause(self)
        }
        button.addAction(action, for: .touchUpInside)
        return button
    }()

    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView()
        progress.layer.cornerRadius = 2.5
        progress.progress = 0
        progress.clipsToBounds = true
        return progress
    }()

    private lazy var currentTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "00:00"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        return label
    }()

    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.text = "00:00"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        return label
    }()

    private var playbackProgressTransform = CGAffineTransform.identity

    private var progressViewContainer: UIStackView!

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupUI() {
        addSubview(playButton)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        playButton.topAnchor.constraint(equalTo: topAnchor).isActive = true
        playButton.widthAnchor.constraint(equalToConstant: 25).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: 25).isActive = true
        playButton.contentVerticalAlignment = .top

        let timeStackView = UIStackView(arrangedSubviews: [currentTimeLabel, durationLabel])
        timeStackView.axis = .horizontal

        progressViewContainer = UIStackView(arrangedSubviews: [progressView, timeStackView])
        progressViewContainer.distribution = .fillProportionally
        progressViewContainer.axis = .vertical
        progressViewContainer.spacing = 4

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.heightAnchor.constraint(equalToConstant: 5).isActive = true

        addSubview(progressViewContainer)
        progressViewContainer.translatesAutoresizingMaskIntoConstraints = false
        progressViewContainer.leftAnchor.constraint(equalTo: playButton.rightAnchor, constant: 8).isActive = true
        progressViewContainer.topAnchor.constraint(equalTo: topAnchor, constant: 4).isActive = true
        progressViewContainer.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        progressViewContainer.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        tintColor = .white

        addGestures(view: progressViewContainer)
    }

    private func addGestures(view: UIView) {
        let tapGesture = UIPanGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap(gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: progressViewContainer)
        let per = translation.x / progressViewContainer.bounds.width

        let value = progressView.progress + Float(per)
        let currentValue = min(max(0, value), 1)
        progressView.setProgress(currentValue, animated: true)

        delegate?.toCropViewPlayerControlsDidChangeSliderValue(self, value: currentValue)

        gesture.setTranslation(.zero, in: progressViewContainer)

        UIView.animate(withDuration: 0.1) {
            switch gesture.state {
            case .began, .changed:
                self.progressView.transform = self.playbackProgressTransform.concatenating(.init(scaleX: 1, y: 1.8))
                self.progressViewContainer.spacing = 8
                self.progressView.layer.cornerRadius = 2.5
                self.playButton.isHidden = true

            case .ended:
                self.progressView.transform = self.playbackProgressTransform
                self.progressViewContainer.spacing = 4
                self.progressView.layer.cornerRadius = 3
                self.playButton.isHidden = false

            default: break
            }
        }
    }
}

extension TimeInterval {
    var timeFormatted: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
