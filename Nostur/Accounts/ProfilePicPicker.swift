//
//  ProfilePicPicker.swift
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
struct ProfileImage: View {
    let imageState: ProfileModel.ImageState

    var body: some View {
        switch imageState {
        case .success(let image):
            image.resizable()
        case .gifData(let data):
            GIFImage(data: data, isPlaying: .constant(true))
                .scaledToFill()
        case .loading:
            ProgressView()
        case .empty:
            Image(systemName: "person.fill")
                .font(.system(size: 40))
                .foregroundColor(.white)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.white)
        }
    }
}

@available(iOS 16.0, *)
struct CircularProfileImage: View {
    let imageState: ProfileModel.ImageState

    var body: some View {
        ProfileImage(imageState: imageState)
            .scaledToFill()
            .clipShape(Circle())
            .frame(width: 75, height: 75)
            .background {
                Circle().fill(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.systemBackground, lineWidth: 2)
            )
    }
}

@available(iOS 16.0, *)
struct EditableCircularProfileImage: View {
    @ObservedObject var viewModel: ProfileModel

    var body: some View {
        CircularProfileImage(imageState: viewModel.imageState)
            .overlay(alignment: .bottomTrailing) {
                if #available(iOS 16.0, *) {
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
}

@available(iOS 16.0, *)
@MainActor
class ProfileModel: ObservableObject {
    
    @Binding var picture:String
    @Binding var newPicture:UIImage?
    @Binding var newPictureData:Data?

    init(_ picture:Binding<String>, newPicture:Binding<UIImage?>, newPictureData:Binding<Data?>) {
        _picture = picture
        _newPicture = newPicture
        _newPictureData = newPictureData
        if (picture.wrappedValue != "") {
            loadExistingImage(picture.wrappedValue)
        }
    }
    
    func loadExistingImage(_ picture: String) {
        let request = makeImageRequest(URL(string: picture)!, label: "ProfileModel")
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
        case gifData(Data)
        case failure(Error)
    }

    enum TransferError: Error {
        case importFailed
    }

    struct ProfileImage: Transferable {
        let image: Image
        let uiImage: UIImage
        let rawData: Data

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .image) { data in
            #if canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw TransferError.importFailed
                }
                let image = Image(uiImage: uiImage)
                return ProfileImage(image: image, uiImage: uiImage, rawData: data)
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
        return imageSelection.loadTransferable(type: ProfileImage.self) { result in
            DispatchQueue.main.async {
                guard imageSelection == self.imageSelection else {
//                    print("Failed to get the selected item.")
                    return
                }
                switch result {
                case .success(let profileImage?):
                    self.newPicture = profileImage.uiImage
                    self.newPictureData = profileImage.rawData
                    if isAnimatedGIF(profileImage.rawData) {
                        self.imageState = .gifData(profileImage.rawData)
                    } else {
                        self.imageState = .success(profileImage.image)
                    }
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
struct ProfilePicPicker: View {

    @StateObject var viewModel:ProfileModel

    init(_ picture:Binding<String>, newPicture:Binding<UIImage?>, newPictureData:Binding<Data?>) {
        _viewModel = StateObject(wrappedValue: ProfileModel(picture, newPicture: newPicture, newPictureData: newPictureData))
    }

    var body: some View {
        EditableCircularProfileImage(viewModel: viewModel)
    }
}

@available(iOS 16.0, *)
struct MediaPicker_Previews: PreviewProvider {
    @State static var picture = "https://nostur.com/fabian/profile.jpg"
    @State static var newPicture:UIImage?
    @State static var newPictureData:Data?
    static var previews: some View {
        PreviewContainer {
            ProfilePicPicker($picture, newPicture:$newPicture, newPictureData:$newPictureData)
                .hCentered()
                .listRowBackground(Color(.systemGroupedBackground))
        }
    }
}
