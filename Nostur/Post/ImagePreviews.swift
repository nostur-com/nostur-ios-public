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
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        HStack {
            ForEach(pastedImages) { pastedImage in
                Image(uiImage: pastedImage.imageData)
                    .resizable()
                    .scaledToFit()
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
                    
            }
        }
    }
}

struct ImagePreviews_Previews: PreviewProvider {
    @State static var images:[PostedImageMeta] = [
        PostedImageMeta(index: 0, imageData: UIImage(named:"NosturLogo")!, type: .jpeg, uniqueId: UUID().uuidString),
        PostedImageMeta(index: 1, imageData: UIImage(named:"NosturLogoFull")!, type: .jpeg, uniqueId: UUID().uuidString)
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
