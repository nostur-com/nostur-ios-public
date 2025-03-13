//
//  PhotosPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/06/2023.
//

import SwiftUI
import PhotosUI

@available(iOS 16.0, *)
class MultipleImagePickerModel: ObservableObject {

    @Published var newImages: [UIImage] = []
    @Published var imageSelection: [PhotosPickerItem] = [] {
        didSet {
            guard !imageSelection.isEmpty else { return }
            Task {
                let newImages = await loadTransferables()
                Task { @MainActor in
                    self.newImages = newImages
                    self.imageSelection = []
                }
            }
        }
    }

    private func loadTransferables() async -> [UIImage] {
        var newImages: [UIImage] = []
        for imageSelection in self.imageSelection {
            if let image = await loadTransferable(from: imageSelection) {
                newImages.append(image)
            }
        }
        return newImages
    }

    private func loadTransferable(from imageSelection: PhotosPickerItem) async -> UIImage? {
        await withCheckedContinuation { continuation in
            imageSelection.loadTransferable(type: SelectedImage.self) { result in
                switch result {
                case .success(let selectedImage?):
                    continuation.resume(returning: selectedImage.uiImage)
                case .success(nil):
                    continuation.resume(returning: nil)
                case .failure(_):
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    enum TransferError: Error {
        case importFailed
    }

    @available(iOS 16.0, *)
    struct SelectedImage: Transferable {
        let image: Image
        let uiImage: UIImage

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .image) { data in
            #if canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw TransferError.importFailed
                }
                let image = Image(uiImage: uiImage)
                return SelectedImage(image: image, uiImage: uiImage)
            #else
                throw TransferError.importFailed
            #endif
            }
        }
    }
}
