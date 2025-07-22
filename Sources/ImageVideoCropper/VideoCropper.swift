//
//  VideoCropper.swift
//  MediaCropper
//
//  Created by hari krishna on 09/07/2025.
//
import AVFoundation
import Combine
import CoreImage

enum VideoCropperError: Error {
    case failedToCreateComposition
    case videoTrackNotFound
    case failedToExportVideo(underlying: Error?) // Add underlying error info
    case invalidCropRect
    case fileNotFound
}

final class VideoCropper: @unchecked Sendable {
    static let shared = VideoCropper()
    private var exportSession: AVAssetExportSession?
    private var exportTask: Task<URL, Error>?
    private var timerCancellable: AnyCancellable?
    private let progressUpdateInterval: TimeInterval = 0.2

    private init() { }

    func cropVideo(url: URL, cropRect: CGRect, angleInRadians: CGFloat = 0.0, progress: @Sendable @escaping (Float) -> Void) async throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoCropperError.fileNotFound
        }

        guard cropRect.width > 0 && cropRect.height > 0 else {
            throw VideoCropperError.invalidCropRect
        }

        await cleanup()

        let asset = AVURLAsset(url: url)

        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)

        let composition = AVMutableComposition()
        var trackIds: [CMPersistentTrackID] = []

        for track in videos {
            guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoCropperError.failedToCreateComposition
            }
            try videoCompositionTrack.insertTimeRange(.init(start: .zero, duration: duration), of: track, at: .zero)
            trackIds.append(videoCompositionTrack.trackID)
        }

        for track in audios {
            guard let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoCropperError.failedToCreateComposition
            }
            try audioCompositionTrack.insertTimeRange(.init(start: .zero, duration: duration), of: track, at: .zero)
        }

        guard let firstTrack = videos.first else {
            throw VideoCropperError.videoTrackNotFound
        }

        let videoSize = try await firstTrack.load(.naturalSize)
        let frameRate = try await firstTrack.load(.nominalFrameRate)
        let transform = try await firstTrack.load(.preferredTransform)

        let transformed = videoSize.applying(transform).applying(.init(rotationAngle: angleInRadians))
        let width = abs(transformed.width)
        let height = abs(transformed.height)

        let normalizedCropRect = CGRect(x: 0, y: 0, width: width, height: height).intersection(cropRect)

        let renderSize: CGSize = normalizedCropRect.size

        let instruction = VideoCropperInstruction(
            timeRange: .init(start: .zero, duration: duration),
            trackIds: trackIds,
            preferredTransform: transform,
            cropRect: normalizedCropRect,
            angleInRadians: angleInRadians
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.customVideoCompositorClass = VideoCropperCompositor.self
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)_cropped.mov")

        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        exportSession?.outputURL = outputURL
        exportSession?.videoComposition = videoComposition
        exportSession?.outputFileType = .mov

        self.exportSession = exportSession

        // Assign export task
        let exportTask = Task {
            guard let exportSession = exportSession else {
                throw VideoCropperError.failedToCreateComposition
            }

            timerCancellable = Timer.publish(every: self.progressUpdateInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self, let exportSession = self.exportSession else { return }
                    progress(exportSession.progress)
                }

            await exportSession.export()

            if exportSession.status == .completed {
                return outputURL
            } else {
                throw exportSession.error ?? VideoCropperError.failedToExportVideo(underlying: exportSession.error)
            }
        }

        self.exportTask = exportTask
        return try await exportTask.value
    }

    @MainActor
    private func cleanup() async {
        exportSession?.cancelExport()
        exportTask?.cancel()

        // Wait for tasks to complete
        _ = await exportTask?.result

        timerCancellable?.cancel()

        exportTask = nil
        exportSession = nil
        timerCancellable = nil
    }

    @MainActor
    func cancel() async {
        await cleanup()
    }

    class VideoCropperInstruction: NSObject, AVVideoCompositionInstructionProtocol {
        var timeRange: CMTimeRange

        var enablePostProcessing: Bool = false

        var containsTweening: Bool = false

        var requiredSourceTrackIDs: [NSValue]?

        var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

        let preferredTransform: CGAffineTransform

        let cropRect: CGRect

        let trackIds: [CMPersistentTrackID]

        let angleInRadians: CGFloat

        init(timeRange: CMTimeRange, trackIds: [CMPersistentTrackID], preferredTransform: CGAffineTransform, cropRect: CGRect, angleInRadians: CGFloat) {
            self.timeRange = timeRange
            self.trackIds = trackIds
            requiredSourceTrackIDs = trackIds.map { NSNumber(value: $0) }
            self.preferredTransform = preferredTransform
            self.cropRect = cropRect
            self.angleInRadians = angleInRadians
        }
    }

    final class VideoCropperCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
        let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = pixelBufferAttributes()

        let sourcePixelBufferAttributes: [String: any Sendable]? = pixelBufferAttributes()

        let context = CIContext()

        private static func pixelBufferAttributes() -> [String: any Sendable] {
            return [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: any Sendable],
                kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ]
        }

        func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) { }

        func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
            guard let instruction = request.videoCompositionInstruction as? VideoCropperInstruction else {
                return request.finish(with: NSError(domain: "com.custom.compositor", code: -1, userInfo: nil))
            }

            guard let destinationPixelBuffer = request.renderContext.newPixelBuffer() else {
                return request.finish(with: NSError(domain: "com.custom.compositor", code: -3, userInfo: nil))
            }

            guard let sourcePixel = request.sourceFrame(byTrackID: instruction.trackIds[0]) else {
                return request.finish(with: NSError(domain: "com.custom.compositor", code: -4, userInfo: [NSLocalizedDescriptionKey: "Missing source frame"]))
            }

            var finalImage: CIImage = CIImage(cvPixelBuffer: sourcePixel)

            // normalizing the transform
            if instruction.preferredTransform.hasRotation {
                let height = CVPixelBufferGetHeight(sourcePixel)
                let transform = instruction.preferredTransform.concatenating(CGAffineTransform(scaleX: -1, y: -1).translatedBy(x: 0, y: -CGFloat(height)))

                let normalized = CIImage(cvPixelBuffer: sourcePixel)
                    .transformed(by: transform)

                finalImage = normalized.transformed(by: CGAffineTransform(translationX: -normalized.extent.minX,
                                                                          y: -normalized.extent.minY))
            }

            // applying desired rotation for cropping
            if instruction.angleInRadians != 0 {
                let threeSixtyInRadian: CGFloat = 360 * .pi / 180

                let angle: CGFloat = threeSixtyInRadian - instruction.angleInRadians // flipping the angle to coreimage
                let rotatedImage = finalImage.transformed(by: CGAffineTransform(rotationAngle: angle))
                finalImage = rotatedImage.transformed(by: CGAffineTransform(translationX: -rotatedImage.extent.minX,
                                                                            y: -rotatedImage.extent.minY))
            }

            // Flipping the croprect to match with UIKit coordinates
            let flippedCropRect = CGRect(
                x: instruction.cropRect.origin.x,
                y: finalImage.extent.height - instruction.cropRect.origin.y - instruction.cropRect.height,
                width: instruction.cropRect.width,
                height: instruction.cropRect.height
            )

            let croppedImage = finalImage.cropped(to: flippedCropRect)
            finalImage = croppedImage.transformed(by: CGAffineTransform(translationX: -croppedImage.extent.minX,
                                                                        y: -croppedImage.extent.minY))

            context.render(finalImage, to: destinationPixelBuffer)

            request.finish(withComposedVideoFrame: destinationPixelBuffer)
        }
    }
}

extension CGAffineTransform {
    var hasRotation: Bool {
        return b != 0 || c != 0
    }
}
