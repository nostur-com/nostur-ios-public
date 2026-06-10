//
//  GalleryFullScreenSwiper.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/12/2023.
//

import SwiftUI
import Photos

private struct ShareableGalleryMedia: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

struct GalleryFullScreenSwiper: View {
    @Environment(\.theme) private var theme
    @Environment(\.fullScreenSize) var fullScreenSize: CGSize

    public var initialIndex: Int
    public var items: [GalleryItem]
    public var isEncrypted: Bool = false
    public var usePFPpipeline: Bool = false // set true to load fixed PFP from cache (else nothing in cache)
    
    @State private var activeIndex: Int?
    @State private var sharableImage: UIImage? = nil
    @State private var sharableGif: Data? = nil
    @State private var shareableGalleryMedia: ShareableGalleryMedia? = nil
    @State private var temporarySharedMediaURL: URL? = nil
    
    // Save state variables
    @State private var isSaving = false
    @State private var didSave = false
    
    // Zoom and pan state
    private let minScale: CGFloat = 1.0 // fit-to-screen
    private let maxScale: CGFloat = 4.0
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var position: CGSize = .zero
    @State private var newPosition: CGSize = .zero

    // Interactive dismissal state
    @State private var dismissOffset: CGFloat = 0 // tracks the finger 1:1 during swipe-down
    @State private var isDraggingToDismiss = false
    @State private var isDismissing = false

    // 0...1 over half a screen of downward drag; drives the background fade and chrome opacity
    private var dismissProgress: CGFloat {
        min(1.0, max(0, dismissOffset / max(1, fullScreenSize.height * 0.5)))
    }
    
    // Media Post Preview
    @State private var mediaPostPreview = false
    @State private var post: NRPost? = nil
    @State private var showMiniProfile = false
    
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
                        .onAppear {
                            loadMediaPostPreview(for: index)
                            prefetchNextImage(currentIndex: index)
                        }
                        .highPriorityGesture(TapGesture().onEnded({ _ in
                            withAnimation {
                                mediaPostPreview.toggle()
                                scale = 1.0
                            }
                        }))
                }
            }
            .scrollTargetLayout()
        }
        
        .simultaneousGesture(dismissDragGesture)
        .simultaneousGesture(zoomGesture)
        .simultaneousGesture(panGesture)
        
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $activeIndex)
        .frame(width: fullScreenSize.width, height: fullScreenSize.height)
        .scrollDisabled(items.count == 1 || scale > 1.0 || isDraggingToDismiss)
        .background(Color.black.opacity(isDismissing ? 0 : 1 - (0.5 * dismissProgress)))
        .overlay(alignment: .leading) { navigationLeftButton }
        .overlay(alignment: .trailing) { navigationRightButton }
        .overlay(alignment: .topTrailing) { saveButton }
        .onAppear {
            activeIndex = initialIndex
        }
        .overlay(alignment: .bottomLeading) {
            if let post = post, mediaPostPreview && !showMiniProfile {
                MediaPostPreview(post, showMiniProfile: $showMiniProfile)
                    .padding(10)
                    .background(.ultraThinMaterial)
            }
        }
    }
    
    private func loadMediaPostPreview(for index: Int) {
        post = nil
        mediaPostPreview = false
        guard items.count > index else { return }
        let galleryItem = items[index]
        
        bg().perform {
            guard let eventId = galleryItem.eventId,
                  let event = Event.fetchEvent(id: eventId, context: bg())
            else { return }
            
            let nrPost = NRPost(event: event)
            Task { @MainActor in
                self.post = nrPost
            }
        }
    }
    
    private func prefetchNextImage(currentIndex: Int) {
        if items.count > (currentIndex + 1) {
            let prefetchRequest = makeImageRequest(
                items[currentIndex + 1].url,
                label: "prefetchNextImage"
            )
            ImageProcessing.shared.contentPrefetcher.startPrefetching(with: [prefetchRequest])
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
        .frame(width: fullScreenSize.width, height: fullScreenSize.height)
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
            galleryItem: items[index],
            availableWidth: fullScreenSize.width,
            maxHeight: fullScreenSize.height,
            contentMode: .fit,
            fullScreen: true,
            // Already fullscreen, so don't load "galleryItems" recursively
            autoload: true,
            imageInfo: items[index].imageInfo,
            gifInfo: items[index].gifInfo,
            usePFPpipeline: usePFPpipeline
        )
        .frame(width: fullScreenSize.width, height: fullScreenSize.height)
        .scaleEffect(scale * (1.0 - (0.2 * dismissProgress)))
        .offset(position)
        .offset(y: dismissOffset)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation {
                self.scale = 1.0
                self.position = .zero
                self.newPosition = .zero
            }
        }
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
                .opacity(activeIndex != 0 ? 1.0 : 0)
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
                .opacity(activeIndex != items.count-1 ? 1.0 : 0)
            }
        }
    }
    
    private var saveButton: some View {
        // Save button
        Menu(content: {
            Button("Save to Photo Library") {
                saveCurrentImageToPhotos()
            }
            .foregroundColor(theme.accent)
            
            if !isEncrypted, let activeIndex = activeIndex, activeIndex < items.count {
                Button("Copy image URL") {
                    UIPasteboard.general.string = items[activeIndex].url.absoluteString
                    sendNotification(.anyStatus, ("Image URL copied to clipboard", "APP_NOTICE"))
                }
                .foregroundColor(theme.accent)
            }
            
            Button("Share...") {
                shareCurrentMedia()
            }
            .foregroundColor(theme.accent)
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
        })
        .disabled(isSaving)
        .font(.title2)
        .padding(.trailing, 10)
        .padding(.top, 10)
        .opacity(1.0 - dismissProgress)
        .sheet(item: $shareableGalleryMedia, onDismiss: cleanupTemporarySharedMedia) { shareableGalleryMedia in
            ActivityView(activityItems: shareableGalleryMedia.activityItems)
        }
    }
    
    // MARK: - Sharing
    
    private func shareCurrentMedia() {
        guard let index = activeIndex, index < items.count else { return }
        
        let item = items[index]
        
        if let imageInfo = item.imageInfo {
            shareableGalleryMedia = ShareableGalleryMedia(activityItems: [imageInfo.uiImage])
        }
        else if let gifInfo = item.gifInfo {
            shareGif(gifInfo.gifData)
        }
        else {
            sendNotification(.anyStatus, ("No media to share", "APP_NOTICE"))
        }
    }
    
    private func shareGif(_ gifData: Data) {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let gifFileURL = temporaryDirectory.appendingPathComponent("nostur_shared_\(UUID().uuidString).gif")
        
        do {
            try gifData.write(to: gifFileURL)
            temporarySharedMediaURL = gifFileURL
            shareableGalleryMedia = ShareableGalleryMedia(activityItems: [gifFileURL])
        } catch {
            sendNotification(.anyStatus, ("Failed to share GIF: \(error.localizedDescription)", "APP_NOTICE"))
        }
    }
    
    private func cleanupTemporarySharedMedia() {
        guard let temporaryFileURL = temporarySharedMediaURL else { return }
        try? FileManager.default.removeItem(at: temporaryFileURL)
        temporarySharedMediaURL = nil
    }
    
    // MARK: - Gestures
    
    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                // Only start on a mostly-vertical downward drag when not zoomed (much)
                if !isDraggingToDismiss {
                    guard scale <= 1.3 && value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width)
                    else { return }
                    isDraggingToDismiss = true
                }
                // Track the finger 1:1; rubber-band when dragged back up past the start point
                let height = value.translation.height
                dismissOffset = height >= 0 ? height : -(3 * sqrt(-height))
            }
            .onEnded { value in
                guard isDraggingToDismiss else { return }
                isDraggingToDismiss = false

                // predictedEndTranslation projects ~250ms of deceleration, so this approximates pt/s
                let velocity = (value.predictedEndTranslation.height - value.translation.height) * 4
                let shouldDismiss = velocity > 800 || (dismissOffset > fullScreenSize.height * 0.25 && velocity > -100)

                if shouldDismiss {
                    // Hand the release velocity to the spring so the image keeps the finger's speed
                    let remaining = max(1, fullScreenSize.height - dismissOffset)
                    withAnimation(.interpolatingSpring(stiffness: 120, damping: 20, initialVelocity: max(0, velocity) / remaining)) {
                        dismissOffset = fullScreenSize.height
                        isDismissing = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        sendNotification(.closeFullscreenGallery)
                    }
                }
                else {
                    withAnimation(.spring(duration: 0.3)) {
                        dismissOffset = 0
                    }
                }
            }
    }
    
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / self.lastScale
                self.lastScale = value
                let newScale = self.scale * delta
                // Rubber-band resistance beyond min/max, snaps back in .onEnded
                if newScale < minScale {
                    self.scale = minScale * sqrt(newScale / minScale)
                }
                else if newScale > maxScale {
                    self.scale = maxScale * sqrt(newScale / maxScale)
                }
                else {
                    self.scale = newScale
                }
            }
            .onEnded { value in
                self.lastScale = 1.0
                if self.scale < minScale {
                    withAnimation(.spring(duration: 0.3)) {
                        self.scale = minScale
                        self.position = .zero
                    }
                    self.newPosition = .zero
                }
                else if self.scale > maxScale {
                    withAnimation(.spring(duration: 0.3)) {
                        self.scale = maxScale
                    }
                }
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
                    // Keep the image on screen, snap back if dragged too far
                    let clamped = self.clampedPosition(self.position)
                    withAnimation(.spring(duration: 0.3)) {
                        self.position = clamped
                    }
                    self.newPosition = clamped
                }
            }
    }

    private func clampedPosition(_ position: CGSize) -> CGSize {
        let maxX = max(0, (scale - 1) * fullScreenSize.width / 2)
        let maxY = max(0, (scale - 1) * fullScreenSize.height / 2)
        return CGSize(
            width: min(maxX, max(-maxX, position.width)),
            height: min(maxY, max(-maxY, position.height))
        )
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
