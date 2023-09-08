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

struct ProfileImage: View {
    let imageState: ProfileModel.ImageState

    var body: some View {
        switch imageState {
        case .success(let image):
            image.resizable()
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

struct EditableCircularProfileImage: View {
    @ObservedObject var viewModel: ProfileModel

    var body: some View {
        CircularProfileImage(imageState: viewModel.imageState)
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

@MainActor
class ProfileModel: ObservableObject {
    
    @Binding var picture:String
    @Binding var newPicture:UIImage?

    init(_ picture:Binding<String>, newPicture:Binding<UIImage?>) {
        _picture = picture
        _newPicture = newPicture
        if (picture.wrappedValue != "") {
            loadExistingImage(picture.wrappedValue)
        }
    }
    
    func loadExistingImage(_ picture:String) {
        let request = ImageRequest(
            url: URL(string: picture),
            processors: [.resize(width: 75, upscale: true)],
            priority: .high,
            userInfo: [.scaleKey: UIScreen.main.scale]
        )
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

    struct ProfileImage: Transferable {
        let image: Image
        let uiImage: UIImage

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .image) { data in
            #if canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw TransferError.importFailed
                }
                let image = Image(uiImage: uiImage)
                return ProfileImage(image: image, uiImage: uiImage)
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

struct ProfilePicPicker: View {

    @StateObject var viewModel:ProfileModel

    init(_ picture:Binding<String>, newPicture:Binding<UIImage?>) {
        _viewModel = StateObject(wrappedValue: ProfileModel(picture, newPicture: newPicture))
    }

    var body: some View {
        EditableCircularProfileImage(viewModel: viewModel)
    }
}

struct MediaPicker_Previews: PreviewProvider {
    @State static var picture = "https://nostur.com/fabian/profile.jpg"
    @State static var newPicture:UIImage?
    static var previews: some View {
        PreviewContainer {
            ProfilePicPicker($picture, newPicture:$newPicture)
                .hCentered()
                .listRowBackground(Color(.systemGroupedBackground))
        }
    }
}
