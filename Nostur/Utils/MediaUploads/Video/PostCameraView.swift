import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Open directly in Photo mode, with the system's Photo / Video mode switch.
/// Captures stay local until the user posts; uploads still remove source metadata.
struct PostCameraView: UIViewControllerRepresentable {
    @Binding var isImporting: Bool
    var onPhoto: (Data) -> Void
    var onRecorded: (URL) -> Void
    var onCancel: () -> Void
    var onError: (String) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera) &&
        (UIImagePickerController.availableMediaTypes(for: .camera)?.contains(UTType.movie.identifier) ?? false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.cameraCaptureMode = .photo
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: PostCameraView
        private var isFinishing = false

        init(_ parent: PostCameraView) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard !isFinishing else { return }
            if let type = info[.mediaType] as? String, type == UTType.image.identifier,
               let image = info[.originalImage] as? UIImage {
                attachCapture(picker: picker, isVideo: false, prepare: {
                    try await videoFileWork {
                        guard let data = image.pngData() else { throw CocoaError(.fileReadCorruptFile) }
                        return data
                    }
                }, onUse: { self.parent.onPhoto($0) })
            } else if let type = info[.mediaType] as? String, type == UTType.movie.identifier,
                      let source = info[.mediaURL] as? URL {
                attachCapture(picker: picker, isVideo: true, prepare: {
                    try await RecordedVideoFile.copy(from: source)
                }, onUse: { self.parent.onRecorded($0) })
            } else {
                parent.onError(String(localized: "Could not read the camera capture. Please try again."))
            }
        }

        private func attachCapture<T: Sendable>(picker: UIImagePickerController, isVideo: Bool,
                                                prepare: @escaping () async throws -> T,
                                                onUse: @escaping (T) -> Void) {
            guard !isFinishing else { return }
            isFinishing = true
            parent.isImporting = true
            picker.view.isUserInteractionEnabled = false
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.accessibilityLabel = isVideo ? String(localized: "Preparing recorded video") : String(localized: "Preparing photo")
            picker.view.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: picker.view.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: picker.view.centerYAnchor)
            ])
            spinner.startAnimating()
            // Keep the review screen until the capture is safe in the draft.
            // Photo encoding and movie copying run off the UI executor.
            Task { @MainActor in
                do {
                    let capture = try await prepare()
                    parent.isImporting = false
                    onUse(capture)
                } catch {
                    parent.isImporting = false
                    isFinishing = false
                    picker.view.isUserInteractionEnabled = true
                    spinner.removeFromSuperview()
                    let alert = UIAlertController(
                        title: isVideo ? String(localized: "Could not attach video") : String(localized: "Could not attach photo"),
                        message: isVideo ? String(localized: "Your recording is still here. You can retry or discard it.") : String(localized: "Your photo is still here. You can retry or discard it."),
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: String(localized: "Retry"), style: .default) { [weak alert] _ in
                        alert?.dismiss(animated: true) {
                            self.attachCapture(picker: picker, isVideo: isVideo, prepare: prepare, onUse: onUse)
                        }
                    })
                    alert.addAction(UIAlertAction(title: isVideo ? String(localized: "Discard recording") : String(localized: "Discard photo"), style: .destructive) { _ in
                        self.parent.onCancel()
                    })
                    picker.present(alert, animated: true)
                }
            }
        }
    }
}

enum RecordedVideoFile {
    static func copy(from source: URL) async throws -> URL {
        try await videoFileWork {
            let destination = TemporaryMediaFiles.shared.makeURL(extension: "mov")
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                return destination
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
    }
}
