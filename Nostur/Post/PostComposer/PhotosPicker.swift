//
//  PhotosPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/06/2023.
//

import SwiftUI
import PhotosUI

struct MediaImage: View {
    let imageState: ImagePickerModel.ImageState

    var body: some View {
        switch imageState {
        case .success(let image):
            image.resizable()
        case .loading:
            ProgressView()
        case .empty:
            Rectangle()
                .foregroundColor(.gray)
        case .failure:
            Rectangle()
                .foregroundColor(.gray)
        }
    }
}

class ImagePickerModel: ObservableObject {
    
    enum ImageState {
        case empty
        case loading(Progress)
        case success(Image)
        case failure(Error)
    }

    enum TransferError: Error {
        case importFailed
    }

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

    @Published var photoPickerShown = false
    @Published private(set) var imageState: ImageState = .empty

    @Published var newImage:UIImage?
    @Published var imageSelection: PhotosPickerItem? = nil {
        didSet {
            if let imageSelection {
                let progress = loadTransferable(from: imageSelection)
                imageState = .loading(progress)
            } else {
                imageState = .empty
            }
        }
    }

    // MARK: - Private Methods

    private func loadTransferable(from imageSelection: PhotosPickerItem) -> Progress {
        return imageSelection.loadTransferable(type: SelectedImage.self) { result in
            DispatchQueue.main.async {
                guard imageSelection == self.imageSelection else {
                    print("Failed to get the selected item.")
                    return
                }
                switch result {
                case .success(let selectedImage?):
                    self.imageState = .success(selectedImage.image)
                    self.newImage = selectedImage.uiImage
                case .success(nil):
                    self.imageState = .empty
                case .failure(let error):
                    self.imageState = .failure(error)
                }
            }
        }
    }
}
