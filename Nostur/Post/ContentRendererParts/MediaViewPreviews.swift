//
//  MediaViewPreviews.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/03/2025.
//

import SwiftUI



#Preview("Portrait too big") {
    let url = URL(string: "https://i.nostr.build/kLi6lHtXzjiEMmBX.jpg")!
    let galleryItem = GalleryItem(url: url)
    let boxHeight: CGFloat = 200

    ScrollView {
        VStack {
            Box {
                GeometryReader { geo in
                    MediaContentView(
                        galleryItem: galleryItem,
                        availableWidth: geo.size.width,
                        maxHeight: boxHeight,
                        contentMode: .fit,
                        autoload: true
                    )
                }
                .frame(height: boxHeight)
                .overlay(alignment: .topTrailing) { Text("FIT") }
            }
            
            Box {
                GeometryReader { geo in
                    MediaContentView(
                        galleryItem: galleryItem,
                        availableWidth: geo.size.width,
                        maxHeight: boxHeight,
                        contentMode: .fill,
                        autoload: true
                    )
                }
                .frame(height: boxHeight)
                .overlay(alignment: .topTrailing) { Text("FILL") }
            }
        }
        .environmentObject(Themes.default)
    }
}

#Preview("Landscape too big") {
    let url = URL(string: "https://m.primal.net/PjXm.png")!
    let galleryItem = GalleryItem(url: url)
    let boxHeight: CGFloat = 200

    VStack {
        Box {
            GeometryReader { geo in
                MediaContentView(
                    galleryItem: galleryItem,
                    availableWidth: geo.size.width,
                    maxHeight: boxHeight,
                    contentMode: .fit,
                    autoload: true
                )
            }
            .frame(height: boxHeight)
            .overlay(alignment: .topTrailing) { Text("FIT") }
        }
        
        Box {
            GeometryReader { geo in
                MediaContentView(
                    galleryItem: galleryItem,
                    availableWidth: geo.size.width,
                    maxHeight: boxHeight,
                    contentMode: .fill,
                    autoload: true
                )
            }
            .frame(height: boxHeight)
            .overlay(alignment: .topTrailing) { Text("FILL") }
        }
        
    }
    .environmentObject(Themes.default)
}
