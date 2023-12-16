//
//  ImagePreviews.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/04/2023.
//

import SwiftUI
import UIKit

struct ImagePreviews: View {
    @Binding var pastedImages:[PostedImageMeta]
    var previewImages:[Image] {
        pastedImages.map { Image(uiImage: $0.imageData) }
    }
    
    var body: some View {
        HStack {
            ForEach(previewImages.indices, id:\.self) { index in
                previewImages[index]
                    .resizable()
                    .scaledToFit()
                    .overlay(
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.black)
                            .background(Circle().foregroundColor(.white))
                            .frame(width: 20, height: 20)
                            .padding(5)
                            .onTapGesture {
                                _ = pastedImages.remove(at: index)
                                L.og.debug("remove: \(index)")
                            },
                        alignment: .topTrailing
                    )
            }
        }
    }
}

struct ImagePreviews_Previews: PreviewProvider {
    @State static var images:[PostedImageMeta] = [
        PostedImageMeta(index: 0, imageData: UIImage(named:"NosturLogo")!, type: .jpeg),
        PostedImageMeta(index: 1, imageData: UIImage(named:"NosturLogoFull")!, type: .jpeg)
    ]
    static var previews: some View {
        VStack {
            ImagePreviews(pastedImages: $images)
        }
    }
}

struct PostPreviewImages: View {
    let images:[UIImage]
    init(_ images:[UIImage]) {
        self.images = images
    }
    var body: some View {
        ForEach(images.indices, id:\.self) { index in
            Image(uiImage: images[index])
                .resizable()
                .scaledToFit()
                .padding(.bottom, 10)
        }
    }
}
