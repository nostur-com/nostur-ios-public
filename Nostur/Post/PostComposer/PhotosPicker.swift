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

    @Published var newImages: [SelectedImage] = []
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

    private func loadTransferables() async -> [SelectedImage] {
        var newImages: [SelectedImage] = []
        for imageSelection in self.imageSelection {
            if let image = await loadTransferable(from: imageSelection) {
                newImages.append(image)
            }
        }
        return newImages
    }

    private func loadTransferable(from imageSelection: PhotosPickerItem) async -> SelectedImage? {
        await withCheckedContinuation { continuation in
            imageSelection.loadTransferable(type: SelectedImage.self) { result in
                switch result {
                case .success(let selectedImage?):
                    continuation.resume(returning: selectedImage)
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
    struct SelectedImage: Transferable, Equatable {
        let uiImage: UIImage
        let rawData: Data

        static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
            lhs.rawData == rhs.rawData
        }

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .image) { data in
            #if canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw TransferError.importFailed
                }
                return SelectedImage(uiImage: uiImage, rawData: data)
            #else
                throw TransferError.importFailed
            #endif
            }
        }
    }
}
