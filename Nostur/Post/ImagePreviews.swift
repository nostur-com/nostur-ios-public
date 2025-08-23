//
//  ImagePreviews.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/04/2023.
//

import SwiftUI
import UIKit

struct ImagePreviews: View {
    @Binding var pastedImages: [PostedImageMeta]
    public var showButtons: Bool = true
    public var vertical: Bool = false
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        if !vertical {
            HStack {
                ForEach(pastedImages) { pastedImage in
                    if pastedImage.type == .gif {
                        GIFImage(data: pastedImage.data, isPlaying: .constant(true))
                            .aspectRatio(contentMode: .fit)
                            .contentShape(Rectangle())
                            .overlay(alignment: .topTrailing) {
                                if showButtons {
                                    Image(systemName: "xmark.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.black)
                                        .background(Circle().foregroundColor(.white))
                                        .frame(width: 20, height: 20)
                                        .padding(5)
                                        .onTapGesture {
                                            pastedImages.removeAll { $0.uniqueId == pastedImage.uniqueId }
                                        }
                                }
                            }
                            .id(pastedImage.uniqueId)
                            .onAppear {
                                if pastedImages.count == 1 {
                                    sendNotification(.newPostFirstImageAppeared)
                                }
                            }
                    }
                    else if let imageData = pastedImage.uiImage {
                        Image(uiImage: imageData)
                            .resizable()
                            .scaledToFit()
                            .overlay(alignment: .center) {
                                if pastedImage.isGifPlaceholder {
                                    ProgressView()
                                        .frame(width: 40, height: 40)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if showButtons {
                                    Image(systemName: "xmark.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.black)
                                        .background(Circle().foregroundColor(.white))
                                        .frame(width: 20, height: 20)
                                        .padding(5)
                                        .onTapGesture {
                                            pastedImages.removeAll { $0.uniqueId == pastedImage.uniqueId }
                                        }
                                }
                            }
                            .id(pastedImage.uniqueId)
                            .onAppear {
                                if pastedImages.count == 1 {
                                    sendNotification(.newPostFirstImageAppeared)
                                }
                            }
                    }
                }
            }
        }
        else {
            VStack {
                ForEach(pastedImages) { pastedImage in
                    if pastedImage.type == .gif {
                        GIFImage(data: pastedImage.data, isPlaying: .constant(true))
                            .aspectRatio(contentMode: .fit)
                            .contentShape(Rectangle())
                            .overlay(alignment: .topTrailing) {
                                if showButtons {
                                    Image(systemName: "xmark.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.black)
                                        .background(Circle().foregroundColor(.white))
                                        .frame(width: 20, height: 20)
                                        .padding(5)
                                        .onTapGesture {
                                            pastedImages.removeAll { $0.uniqueId == pastedImage.uniqueId }
                                        }
                                }
                            }
                            .id(pastedImage.uniqueId)
                            .onAppear {
                                if pastedImages.count == 1 {
                                    sendNotification(.newPostFirstImageAppeared)
                                }
                            }
                    }
                    else if let imageData = pastedImage.uiImage {
                        Image(uiImage: imageData)
                            .resizable()
                            .scaledToFit()
                            .overlay(alignment: .center) {
                                if pastedImage.isGifPlaceholder {
                                    ProgressView()
                                        .frame(width: 40, height: 40)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if showButtons {
                                    Image(systemName: "xmark.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.black)
                                        .background(Circle().foregroundColor(.white))
                                        .frame(width: 20, height: 20)
                                        .padding(5)
                                        .onTapGesture {
                                            pastedImages.removeAll { $0.uniqueId == pastedImage.uniqueId }
                                        }
                                }
                            }
                            .id(pastedImage.uniqueId)
                            .onAppear {
                                if pastedImages.count == 1 {
                                    sendNotification(.newPostFirstImageAppeared)
                                }
                            }
                    }
                }
            }
        }
    }
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
