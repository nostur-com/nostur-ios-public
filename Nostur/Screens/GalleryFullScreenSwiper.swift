//
//  GalleryFullScreenSwiper.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/12/2023.
//

import SwiftUI

struct GalleryFullScreenSwiper: View {
    @EnvironmentObject private var themes: Themes

    public var initialIndex: Int
    public var items: [GalleryItem]
    
    @State private var mediaPostPreview = true
    @State private var activeIndex: Int?
    
    var body: some View {
        if #available(iOS 17.0, *) {
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(items.indices, id:\.self) { index in
                            FullImageViewer(fullImageURL: items[index].url, galleryItem: items[index], mediaPostPreview: $mediaPostPreview)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $activeIndex)
                .overlay(alignment: .leading) {
                    if IS_CATALYST {
                        Button("", systemImage: "chevron.compact.backward") {
                            guard let activeIndex, activeIndex > 0 else { return }
                            withAnimation {
                                self.activeIndex = activeIndex - 1
                            }
                        }
                        .font(.system(size: 50))
                        .padding(.leading, 10)
                        .opacity(mediaPostPreview && activeIndex != 0 ? 1.0 : 0)
                    }
                }
                .overlay(alignment: .trailing) {
                    if IS_CATALYST {
                        Button("", systemImage: "chevron.compact.forward") {
                            guard let activeIndex, activeIndex < items.count else { return }
                            withAnimation {
                                self.activeIndex = activeIndex + 1
                            }
                        }
                        .font(.system(size: 50))
                        .padding(.trailing, 10)
                        .opacity(mediaPostPreview && activeIndex != items.count-1 ? 1.0 : 0)
                    }
                }
                .onAppear {
                    activeIndex = initialIndex
                }
            }
        }
        else {
            EmptyView()
        }
    }
}
