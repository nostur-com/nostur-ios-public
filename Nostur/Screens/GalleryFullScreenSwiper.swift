//
//  GalleryFullScreenSwiper.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/12/2023.
//

import SwiftUI

struct GalleryFullScreenSwiper: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var screenSpace: ScreenSpace

    public var initialIndex: Int
    public var items: [GalleryItem]
    
    @State private var mediaPostPreview = true
    @State private var activeIndex: Int?
    @State private var sharableImage: UIImage? = nil
    @State private var sharableGif: Data? = nil
    
    // Zoom and pan state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var position: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    @State private var gestureStartTime: Date?
    
    // Interactive dismissal state
    @State private var dismissProgress: CGFloat = 0
    @State private var isDraggingToDismiss = false
    
    var body: some View {
        if #available(iOS 17.0, *) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(items.indices, id:\.self) { index in
                        MediaContentView(
                            media: MediaContent(
                                url: items[index].url,
                                dimensions: items[index].dimensions,
                                blurHash: items[index].blurhash
                            ),
                            availableWidth: screenSpace.screenSize.width,
                            placeholderHeight: screenSpace.screenSize.height,
                            maxHeight: screenSpace.screenSize.height,
                            contentMode: .fit,
                            fullScreen: true,
                            autoload: true,
                            imageInfo: items[index].imageInfo,
                            gifInfo: items[index].gifInfo
                        )
                        .frame(width: screenSpace.screenSize.width, height: screenSpace.screenSize.height)
                        .scaleEffect(scale * (1.0 - (0.2 * dismissProgress)))
                        .offset(position)
                        .offset(y: dismissProgress * 200)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            withAnimation {
                                self.scale = 1.0
                                self.position = .zero
                                self.newPosition = .zero
                            }
                        }

                        // 1. Drag down to dismiss
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                .onChanged { value in
                                    // Only handle vertical drags when not zoomed alot
                                    if scale <= 1.3 && value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) {
                                        if gestureStartTime == nil {
                                            gestureStartTime = Date()
                                            isDraggingToDismiss = true
                                        }
                                        
                                        // Calculate dismiss progress (0 to 1)
                                        let progress = min(1.0, max(0, value.translation.height / 200))
                                        dismissProgress = progress
                                    }
                                }
                                .onEnded { value in
                                    if isDraggingToDismiss {
                                        guard let startTime = gestureStartTime else { return }
                                        let duration = Date().timeIntervalSince(startTime)
                                        let quickSwipeThreshold: TimeInterval = 0.25
                                        let dismissThreshold: CGFloat = 0.3
                                        
                                        let shouldDismiss = (duration < quickSwipeThreshold && value.translation.height > 30) || 
                                                          dismissProgress > dismissThreshold
                                        
                                        if shouldDismiss {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                dismissProgress = 1.0
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                sendNotification(.closeFullscreenGallery)
                                            }
                                        } else {
                                            withAnimation(.spring(duration: 0.3)) {
                                                dismissProgress = 0
                                            }
                                        }
                                    }
                                    gestureStartTime = nil
                                    isDraggingToDismiss = false
                                }
                        )

                        // 2. Gestures for zoom and pan
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / self.lastScale
                                    self.lastScale = value
                                    self.scale *= delta
                                }
                                .onEnded { value in
                                    self.lastScale = 1.0
                                }
                        )
                        
                        
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        // When zoomed, allow free panning
                                        self.position.width = self.newPosition.width + value.translation.width
                                        self.position.height = self.newPosition.height + value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if scale > 1.0 {
                                        self.newPosition = self.position
                                    }
                                }
                        )
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeIndex)
            .frame(width: screenSpace.screenSize.width, height: screenSpace.screenSize.height)
            .scrollDisabled(items.count == 1 || scale > 1.0 || isDraggingToDismiss)  // Also disable scroll while dismissing
            .background(Color.black.opacity(1 - dismissProgress)) // Fade out background
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
//                .toolbar {
//                    ToolbarItem(placement: .topBarLeading) {
//                        Button("Close", systemImage: "multiply") {
//                            dismiss()
//                        }
//                        .font(.title2)
//                        .buttonStyle(.borderless)
//                        .foregroundColor(themes.theme.accent)
//                    }
//                    ToolbarItem(placement: .topBarTrailing) {
//                        if let sharableImage {
//                            ShareMediaButton(sharableImage: sharableImage)
//                        }
//                        else if let sharableGif {
//                            ShareGifButton(sharableGif: sharableGif)
//                        }
//                    }
//                }
            .onAppear {
                activeIndex = initialIndex
            }
        }
        else {
            EmptyView()
        }
    }
}


struct MediaSwiper: View {
    
    let firstImage: UIImage
    
    var body: some View {
        Image(uiImage: firstImage)
            .resizable()
            .scaledToFit()
    }
}
