//
//  ImagePreviews.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/04/2023.
//

import SwiftUI
import UIKit
import ImageIO

struct ImagePreviews: View {
    @Binding var pastedImages: [PostedImageMeta]
    @Binding var uploadStates: [String: ComposerMediaUploadState]
    public var showButtons: Bool = true
    public var vertical: Bool = false
    public var onRemove: ((PostedImageMeta) -> Void)? = nil

    init(
        pastedImages: Binding<[PostedImageMeta]>,
        uploadStates: Binding<[String: ComposerMediaUploadState]> = .constant([:]),
        showButtons: Bool = true,
        vertical: Bool = false,
        onRemove: ((PostedImageMeta) -> Void)? = nil
    ) {
        _pastedImages = pastedImages
        _uploadStates = uploadStates
        self.showButtons = showButtons
        self.vertical = vertical
        self.onRemove = onRemove
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        Group {
            if !vertical {
                HStack {
                    previewItems
                }
            }
            else {
                VStack {
                    previewItems
                }
            }
        }
    }

    @ViewBuilder
    private var previewItems: some View {
        ForEach(pastedImages) { pastedImage in
            preview(for: pastedImage)
                .id(pastedImage.uniqueId)
                .onAppear {
                    if pastedImages.count == 1 {
                        sendNotification(.newPostFirstImageAppeared)
                    }
                }
        }
    }

    @ViewBuilder
    private func preview(for pastedImage: PostedImageMeta) -> some View {
        if pastedImage.type == .gif {
            GIFImage(data: pastedImage.data, isPlaying: .constant(true))
                .aspectRatio(contentMode: .fit)
                .contentShape(Rectangle())
                .overlay(alignment: .center) {
                    if pastedImage.isGifPlaceholder {
                        ProgressView()
                            .frame(width: 40, height: 40)
                    }
                }
                .overlay(alignment: .center) {
                    uploadStateOverlay(for: pastedImage)
                }
                .overlay(alignment: .topTrailing) {
                    removeButton(for: pastedImage)
                }
        }
        else {
            ComposerPhotoPreview(image: pastedImage)
                .overlay(alignment: .center) {
                    if pastedImage.isGifPlaceholder {
                        ProgressView()
                            .frame(width: 40, height: 40)
                    }
                }
                .overlay(alignment: .center) {
                    uploadStateOverlay(for: pastedImage)
                }
                .overlay(alignment: .topTrailing) {
                    removeButton(for: pastedImage)
                }
        }
    }

    @ViewBuilder
    private func removeButton(for pastedImage: PostedImageMeta) -> some View {
        if showButtons {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(.black)
                .background(Circle().foregroundColor(.white))
                .frame(width: 20, height: 20)
                .padding(5)
                .onTapGesture {
                    if let onRemove {
                        onRemove(pastedImage)
                    }
                    else {
                        pastedImages.removeAll { $0.uniqueId == pastedImage.uniqueId }
                        uploadStates[pastedImage.uniqueId] = nil
                    }
                }
        }
    }

    @ViewBuilder
    private func uploadStateOverlay(for pastedImage: PostedImageMeta) -> some View {
        if let state = uploadStates[pastedImage.uniqueId] {
            switch state {
            case .idle:
                EmptyView()
            case .preparing:
                uploadBadge(title: "Preparing", systemImage: nil, progress: nil)
            case .uploading(let percentage):
                uploadBadge(title: percentage.map { "\($0)%" } ?? "Uploading", systemImage: nil, progress: percentage)
            case .uploaded:
                uploadBadge(title: "Uploaded", systemImage: "checkmark.circle.fill", progress: 100)
            case .failed(let message):
                uploadBadge(title: "Failed", systemImage: "exclamationmark.triangle.fill", progress: nil, message: message)
            }
        }
    }

    private func uploadBadge(title: String, systemImage: String?, progress: Int?, message: String? = nil) -> some View {
        VStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3)
            }
            else {
                ProgressView(value: progress.map(Double.init), total: 100)
                    .progressViewStyle(.linear)
                    .frame(width: 90)
            }
            Text(title)
                .font(.caption.bold())
            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundColor(.white)
        .padding(8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }
}

/// Upload progress changes only the overlays; photo decoding runs once per attachment.
private struct ComposerPhotoPreview: View {
    let image: PostedImageMeta
    @State private var decodedImage: UIImage?

    var body: some View {
        Group {
            if let decodedImage {
                Image(uiImage: decodedImage)
                    .resizable()
                    .scaledToFit()
            }
            else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .task(id: image.uniqueId) {
            let data = image.data
            let result = await prepareComposerPhotoPreview(data: data)
            guard !Task.isCancelled else { return }
            decodedImage = result
        }
    }
}

/// Bound preview memory and decode pixels before handing the image to SwiftUI.
func prepareComposerPhotoPreview(data: Data) async -> UIImage? {
    await Task.detached(priority: .userInitiated) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }.value
}

struct ImagePreviews_Previews: PreviewProvider {
    @State static var images:[PostedImageMeta] = [
        PostedImageMeta(index: 0, data: UIImage(named:"NosturLogo")!.pngData()!, type: .png, uniqueId: UUID().uuidString),
        PostedImageMeta(index: 1, data: UIImage(named:"NosturLogoFull")!.pngData()!, type: .png, uniqueId: UUID().uuidString)
    ]
    static var previews: some View {
        VStack {
            ImagePreviews(pastedImages: $images)
        }
    }
}

struct PostPreviewImages: View {
    public let images: [UIImage]
    
    var body: some View {
        ForEach(images.indices, id:\.self) { index in
            Image(uiImage: images[index])
                .resizable()
                .scaledToFit()
                .padding(.bottom, 10)
        }
    }
}
