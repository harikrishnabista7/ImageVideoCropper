//
//  PhotoGallery.swift
//  ImageVideoCropperExample
//
//  Created by hari krishna on 22/07/2025.
//
import PhotosUI

protocol GalleryPresenter: PHPickerViewControllerDelegate where Self: UIViewController {}

extension GalleryPresenter {
    func showGallery(_ filter: PHPickerFilter) {
        var configuration = PHPickerConfiguration()
        configuration.filter = filter

        let gallery = PHPickerViewController(configuration: configuration)
        gallery.delegate = self
        present(gallery, animated: true)
    }
}

extension Array where Element == PHPickerResult {
    func firstImage() async -> UIImage? {
        guard let firstResult = first else { return nil }
        return await withCheckedContinuation { continuation in
            firstResult.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                if let image = obj as? UIImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func firstVideoURL() async -> URL? {
        guard let firstResult = first else { return nil }
        let itemProvider = firstResult.itemProvider

        guard itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                guard let url = url else {
                    print("Failed to get video file:", error?.localizedDescription ?? "Unknown error")
                    continuation.resume(returning: nil)
                    return
                }

//                // URL is temporary — copy to a local permanent location
                let fileName = UUID().uuidString + ".mov"
                let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

                do {
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    continuation.resume(returning: destinationURL)
                } catch {
                    print("Failed to copy video:", error.localizedDescription)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
