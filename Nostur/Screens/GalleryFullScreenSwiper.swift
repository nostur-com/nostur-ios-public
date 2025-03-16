//
//  GalleryFullScreenSwiper.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/12/2023.
//

import SwiftUI
import Photos

struct GalleryFullScreenSwiper: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var screenSpace: ScreenSpace

    public var initialIndex: Int
    public var items: [GalleryItem]
    
    @State private var mediaPostPreview = true
    @State private var activeIndex: Int?
    @State private var sharableImage: UIImage? = nil
    @State private var sharableGif: Data? = nil
    
    // Save state variables
    @State private var isSaving = false
    @State private var didSave = false
    
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
            mainContentView
        }
        else {
            mainContentIOS16
        }
    }
    
    @available(iOS 17.0, *)
    private var mainContentView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(items.indices, id:\.self) { index in
                    mediaItemView(for: index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $activeIndex)
        .frame(width: screenSpace.screenSize.width, height: screenSpace.screenSize.height)
        .scrollDisabled(items.count == 1 || scale > 1.0 || isDraggingToDismiss)
        .background(Color.black.opacity(1 - dismissProgress))
        .overlay(alignment: .leading) { navigationLeftButton }
        .overlay(alignment: .trailing) { navigationRightButton }
        .overlay(alignment: .topTrailing) { saveButton }
        .onAppear {
            activeIndex = initialIndex
        }
    }
    
    private var mainContentIOS16: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(items.indices, id:\.self) { index in
                    mediaItemView(for: index)
                }
            }
        }
        .frame(width: screenSpace.screenSize.width, height: screenSpace.screenSize.height)
        .background(Color.black.opacity(1 - dismissProgress))
        .overlay(alignment: .leading) { navigationLeftButton }
        .overlay(alignment: .trailing) { navigationRightButton }
        .overlay(alignment: .topTrailing) { saveButton }
        .onAppear {
            activeIndex = initialIndex
        }
    }
    
    private func mediaItemView(for index: Int) -> some View {
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
        .simultaneousGesture(dismissDragGesture)
        .simultaneousGesture(zoomGesture)
        .simultaneousGesture(panGesture)
        .id(index)
    }
    
    private var navigationLeftButton: some View {
        Group {
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
    }
    
    private var navigationRightButton: some View {
        Group {
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
    }
    
    private var saveButton: some View {
        // Save button
        Menu(content: {
            Button("Save to Photo Library") {
                saveCurrentImageToPhotos()
            }
            .foregroundColor(themes.theme.accent)
            
            if let activeIndex = activeIndex, activeIndex < items.count {
                Button("Copy image URL") {
                    UIPasteboard.general.string = items[activeIndex].url.absoluteString
                    sendNotification(.anyStatus, ("Image URL copied to clipboard", "APP_NOTICE"))
                }
                .foregroundColor(themes.theme.accent)
            }
        }, label: {
            Group {
                if isSaving {
                    ProgressView()
                        .foregroundColor(.white)
                        .tint(.white)
                        .padding(10)
                }
                else if didSave {
                    Image(systemName: "square.and.arrow.down.badge.checkmark.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .offset(y: -2)
                }
                else {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(.white)
                        .padding(10)
                        .offset(y: -6)
                }
            }
        }, primaryAction: saveCurrentImageToPhotos)
        .disabled(isSaving)
        .font(.title2)
        .padding(.trailing, 10)
        .padding(.top, 10)
        .opacity(1.0 - dismissProgress)
    }
    
    // MARK: - Gestures
    
    private var dismissDragGesture: some Gesture {
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
    }
    
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / self.lastScale
                self.lastScale = value
                self.scale *= delta
            }
            .onEnded { value in
                self.lastScale = 1.0
            }
    }
    
    private var panGesture: some Gesture {
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
    }
    
    func saveCurrentImageToPhotos() {
        guard !didSave else { return }
        guard let index = activeIndex, index < items.count else { return }
        
        isSaving = true
        didSave = false
        
        // Check what we're saving and delegate to appropriate function
        let item = items[index]
        
        if let imageInfo = item.imageInfo {
            saveImageToPhotoLibrary(imageInfo)
        } 
        else if let gifInfo = item.gifInfo {
            saveGifToPhotoLibrary(gifInfo)
        }
        else {
            // No media to save
            sendNotification(.anyStatus, ("No media to save", "APP_NOTICE"))
            isSaving = false
        }
    }
    
    private func saveImageToPhotoLibrary(_ imageInfo: ImageInfo) {
        requestPhotoLibraryAccess { granted in
            if granted {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: imageInfo.uiImage)
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            self.didSave = true
                            sendNotification(.anyStatus, ("Saved to Photo Library", "APP_NOTICE"))
                        } else {
                            sendNotification(.anyStatus, ("Failed to save image: \(error?.localizedDescription ?? "Unknown error")", "APP_NOTICE"))
                        }
                        self.isSaving = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    sendNotification(.anyStatus, ("Photo Library access was denied", "APP_NOTICE"))
                    self.isSaving = false
                }
            }
        }
    }
    
    private func saveGifToPhotoLibrary(_ gifInfo: GifInfo) {
        requestPhotoLibraryAccess { granted in
            if granted {
                self.writeGifAndSave(gifInfo.gifData)
            } else {
                DispatchQueue.main.async {
                    sendNotification(.anyStatus, ("Photo Library access was denied", "APP_NOTICE"))
                    self.isSaving = false
                }
            }
        }
    }
    
    private func writeGifAndSave(_ gifData: Data) {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let gifFileURL = temporaryDirectory.appendingPathComponent("temp_gif.gif")
        
        do {
            try gifData.write(to: gifFileURL)
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: gifFileURL)
            }) { success, error in
                DispatchQueue.main.async {
                    try? FileManager.default.removeItem(at: gifFileURL)
                    if success {
                        self.didSave = true
                        sendNotification(.anyStatus, ("Saved to Photo Library", "APP_NOTICE"))
                    } else {
                        sendNotification(.anyStatus, ("Failed to save GIF: \(error?.localizedDescription ?? "Unknown error")", "APP_NOTICE"))
                    }
                    self.isSaving = false
                }
            }
        } catch {
            DispatchQueue.main.async {
                sendNotification(.anyStatus, ("Failed to save GIF: \(error.localizedDescription)", "APP_NOTICE"))
                self.isSaving = false
            }
        }
    }
    
    func requestPhotoLibraryAccess(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            completion(false)
        }
    }
}
