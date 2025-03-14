//
//  BannerPicPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/04/2023.
//

import SwiftUI
import Nuke
import NukeUI
import PhotosUI
import CoreTransferable

@available(iOS 16.0, *)
struct BannerImage: View {
    let imageState: BannerModel.ImageState
    let width:CGFloat

    var body: some View {
        switch imageState {
        case .success(let image):
            image.resizable()
        case .loading:
            ProgressView()
        case .empty:
                GeometryReader { geo in
                    Rectangle()
                        .foregroundColor(.gray)
                        .frame(width: width, height: 150)
                }
        case .failure:
                GeometryReader { geo in
                    Rectangle()
                        .foregroundColor(.gray)
                        .frame(width: width, height: 150)
                }
        }
    }
}

@available(iOS 16.0, *)
struct BlablaBannerImage: View {
    let imageState: BannerModel.ImageState
    let width:CGFloat
    
    init(imageState: BannerModel.ImageState, width: CGFloat) {
        self.imageState = imageState
        self.width = width
    }

    var body: some View {
        GeometryReader { geo in
            BannerImage(imageState: imageState, width: width)
                .scaledToFill()
                .frame(width: width, height: 150)
        }
    }
}

@available(iOS 16.0, *)
struct EditableBannerImage: View {
    @ObservedObject var viewModel: BannerModel
    let width:CGFloat

    var body: some View {
        BlablaBannerImage(imageState: viewModel.imageState, width: width)
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(selection: $viewModel.imageSelection,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Image(systemName: "pencil.circle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 30))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
            }
    }
}

@available(iOS 16.0, *)
@MainActor
class BannerModel: ObservableObject {
    
    @Binding var picture:String
    @Binding var newPicture:UIImage?
    let width:CGFloat

    init(_ picture:Binding<String>, newPicture:Binding<UIImage?>, width:CGFloat) {
        self.width = width
        _picture = picture
        _newPicture = newPicture
        if (picture.wrappedValue != "") {
            loadExistingImage(picture.wrappedValue)
        }
    }
    
    func loadExistingImage(_ picture: String) {
        let request = makeImageRequest(URL(string: picture)!, label: "Banner.01")
        Task {
            let image = try await ImageProcessing.shared.pfp.image(for: request)
            imageState = .success(Image(uiImage: image))
        }
    }

    // MARK: - Profile Image

    enum ImageState {
        case empty
        case loading(Progress)
        case success(Image)
        case failure(Error)
    }

    enum TransferError: Error {
        case importFailed
    }

    struct BannerImage: Transferable {
        let image: Image
        let uiImage: UIImage

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .image) { data in
            #if canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw TransferError.importFailed
                }
                let image = Image(uiImage: uiImage)
                return BannerImage(image: image, uiImage: uiImage)
            #else
                throw TransferError.importFailed
            #endif
            }
        }
    }

    @Published private(set) var imageState: ImageState = .empty

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
        return imageSelection.loadTransferable(type: BannerImage.self) { result in
            DispatchQueue.main.async {
                guard imageSelection == self.imageSelection else {
//                    print("Failed to get the selected item.")
                    return
                }
                switch result {
                case .success(let profileImage?):
                    self.imageState = .success(profileImage.image)
                    self.newPicture = profileImage.uiImage
                case .success(nil):
                    self.imageState = .empty
                case .failure(let error):
                    self.imageState = .failure(error)
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct BannerPicPicker: View {

    @StateObject var viewModel:BannerModel
    let width:CGFloat

    init(_ picture:Binding<String>, newPicture:Binding<UIImage?>, width:CGFloat) {
        self.width = width
        _viewModel = StateObject(wrappedValue: BannerModel(picture, newPicture: newPicture, width: width))
    }

    var body: some View {
        EditableBannerImage(viewModel: viewModel, width:width)
    }
}

@available(iOS 16.0, *)
struct BannerPicPicker_Previews: PreviewProvider {
//    @State static var picture = "https://nostur.com/fabian/banner.jpg"
    @State static var picture = "https://profilepics.nostur.com/062daf266de13f0195f611675d4b7309b32f743012f539979c104b803591dc86/banner.jpg"
    @State static var newPicture:UIImage?
    static var previews: some View {
        GeometryReader { geo in
            BannerPicPicker($picture, newPicture:$newPicture, width: geo.size.width)
                .frame(height: 150)
                .clipped()
                .hCentered()
                .listRowBackground(Color(.systemGroupedBackground))
        }
    }
}
