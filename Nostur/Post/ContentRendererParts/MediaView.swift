//
//  MediaView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2025.
//

import SwiftUI
import NukeUI
import Nuke

struct MediaContentView: View {
    public var galleryItem: GalleryItem
    public var availableWidth: CGFloat
    public var placeholderAspect: CGFloat? // to reduce jumping
    public var maxHeight: CGFloat = 4000.0
    public var contentMode: ContentMode = .fit // if placeholderHeight is set, probably should use fill!!
    public var fullScreen: Bool = false
    
    public var galleryItems: [GalleryItem]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    public var upscale: Bool = false
    public var autoload: Bool = false
    public var isNSFW: Bool = false
    public var imageInfo: ImageInfo? = nil
    public var gifInfo: GifInfo? = nil
    public var usePFPpipeline: Bool = false
    
    // will sendNotification with image dimensions / blurhash 
    public var generateIMeta: Bool = false
    
    public var zoomableId: String = "Default"
    
    // The actual dimensions, once the image is actually processed and loaded, should be set after download/processing
    @State private var realDimensions: CGSize?
    
    // Force fill and clip if image is too long
    private var shouldForceToFill: Bool {
        if fullScreen { return false }
        if let realDimensions { // use aspect from actual dimensions from real image
            let aspect = realDimensions.width / realDimensions.height
            if availableWidth > (maxHeight * aspect) {
                return true
            }
        }
        else if let metaAspect = galleryItem.aspect { // use aspect from imeta
            if availableWidth > (maxHeight * metaAspect) {
                return true
            }
        }
        else if let placeholderAspect { // use aspect from placeholder
            if availableWidth > (maxHeight * placeholderAspect) {
                return true
            }
        }
        return false
    }
    
    var body: some View {
        MediaPlaceholder(
            galleryItem: galleryItem,
            blurHash: galleryItem.blurhash,
            availableWidth: availableWidth,
            placeholderAspect: placeholderAspect,
            maxHeight: maxHeight,
            contentMode: shouldForceToFill ? .fill : contentMode,
            fullScreen: fullScreen,
            galleryItems: galleryItems,
            realDimensions: $realDimensions,
            upscale: upscale,
            autoload: autoload,
            isNSFW: isNSFW,
            imageInfo: imageInfo,
            gifInfo: gifInfo,
            usePFPpipeline: usePFPpipeline,
            generateIMeta: generateIMeta,
            zoomableId: zoomableId
        )
    }
}

struct MediaPlaceholder: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.feedImageRequestTargetSize) private var feedImageRequestTargetSize
    @Environment(\.cropImageRequestToTarget) private var cropImageRequestToTarget
    @Environment(\.feedLayoutStabilizer) private var feedLayoutStabilizer
    @StateObject private var vm = MediaViewVM()
    @Environment(\.theme) private var theme
    
    public let galleryItem: GalleryItem
    public var blurHash: String?
    public let availableWidth: CGFloat
    public let placeholderAspect: CGFloat?
    public let maxHeight: CGFloat
    public var contentMode: ContentMode = .fit
    public var fullScreen: Bool = false
    public var galleryItems: [GalleryItem]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    @Binding var realDimensions: CGSize?
    @State private var gifIsPlaying = false
    
    public var upscale: Bool = false
    public var autoload: Bool = false
    public var isNSFW: Bool = false
    public var imageInfo: ImageInfo? = nil
    public var gifInfo: GifInfo? = nil
    public var usePFPpipeline: Bool = false
    public var generateIMeta: Bool = false
    public var zoomableId: String = "Default"
    
    @State private var blurImage: UIImage?
    
    private var aspect: CGFloat {
        if let realDimensions { // real aspect
            return realDimensions.width / realDimensions.height
        }
        
        if let metaAspect = galleryItem.aspect { // aspect from imeta
            return metaAspect
        }
        
        // Aspect from placeholder param, else just guess 4:3
        return placeholderAspect ?? 4/3
    }
    
    private var height: CGFloat {
        // if .fill, we fill to placeholder height (derived from placeholder aspect)
        
        if contentMode == .fill {
            let fillHeight: CGFloat? = if let placeholderAspect {
                availableWidth / placeholderAspect
            }
            else { nil }
            
            // but not bigger than maxHeight
            return min(maxHeight, fillHeight ?? maxHeight)
        }

        // if .fit scale up height, but not bigger than maxHeight
        return min(availableWidth / aspect, maxHeight)
    }

    private var imageRequestTargetSize: CGSize? {
        if fullScreen {
            return CGSize(
                width: max(1, availableWidth),
                height: max(1, maxHeight)
            )
        }
        return feedImageRequestTargetSize
    }
    
    var body: some View {
        if contentMode == .fit {
            mediaPlaceholder
                .frame(
                    width: availableWidth,
                    height: height
                )
//                .debugDimensions()
//                .overlay(alignment: .center) {
//                    Text("fit: aW:\(availableWidth), aspect:\(aspect) h:\(height)")
//                        .foregroundColor(Color.yellow)
//                        .background(Color.black)
//                        .font(.footnote)
//                }
        }
        else {
          mediaPlaceholder
                .frame(
                    width: availableWidth,
                    height: height
                )
                .clipped()
                .contentShape(Rectangle().inset(by: 10)) // needed or tap outside is buggy
//                .debugDimensions()
//                .overlay(alignment: .center) {
//                    Text("fit: aW:\(availableWidth), aspect:\(aspect) h:\(height)")
//                        .foregroundColor(Color.yellow)
//                        .background(Color.black)
//                        .font(.footnote)
//                }
        }
    }

    private func updateRealDimensions(_ dimensions: CGSize) {
        guard dimensions.width > 0, dimensions.height > 0,
              realDimensions != dimensions else { return }

        let update = {
            realDimensions = dimensions
        }

        // Fill-mode media keeps the placeholder's fixed frame, and fullscreen media is not a
        // self-sizing feed row. Only fit-mode discoveries can change the feed row's height.
        guard contentMode == .fit, !fullScreen else {
            update()
            return
        }

        let previousAspect = realDimensions.map { $0.width / $0.height }
            ?? galleryItem.aspect
            ?? placeholderAspect
            ?? 4 / 3
        let resolvedAspect = dimensions.width / dimensions.height
        let previousHeight = min(availableWidth / previousAspect, maxHeight)
        let resolvedHeight = min(availableWidth / resolvedAspect, maxHeight)

        guard abs(previousHeight - resolvedHeight) > 1 else {
            update()
            return
        }

        if let feedLayoutStabilizer {
            feedLayoutStabilizer.performAnchored(reason: "media row resized", update)
        } else {
            update()
        }
    }

    /// A fit-mode image must not be revealed inside a placeholder with a different aspect.
    /// During scrolling, the feed stabilizer can defer the row-height update; showing the image
    /// before that update makes portrait media appear narrow and then snap to full width.
    private func needsResolvedLayout(for dimensions: CGSize) -> Bool {
        guard contentMode == .fit, !fullScreen, realDimensions == nil,
              dimensions.width > 0, dimensions.height > 0 else { return false }

        let placeholderAspect = galleryItem.aspect ?? self.placeholderAspect ?? 4 / 3
        let resolvedAspect = dimensions.width / dimensions.height
        let placeholderHeight = min(availableWidth / placeholderAspect, maxHeight)
        let resolvedHeight = min(availableWidth / resolvedAspect, maxHeight)
        return abs(placeholderHeight - resolvedHeight) > 1
    }

    private var unresolvedLayoutPlaceholder: some View {
        theme.background.opacity(0.7)
            .overlay {
                if let blurImage {
                    Image(uiImage: blurImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: availableWidth, height: height)
                        .clipped()
                }
            }
            .frame(width: availableWidth, height: height)
    }
    
    
    @ViewBuilder
    private var mediaPlaceholder: some View {
        switch vm.state {
        case .loading(let percentage), .paused(let percentage):
            theme.background.opacity(0.7)
                .overlay {
                    if let blurImage {
                        Image(uiImage: blurImage)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: availableWidth,
                                height: height
                            )
                            .clipped()
                    }
                }
                .frame(
                    width: availableWidth,
                    height: height
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if case .loading(_) = vm.state {
                        pauseLoad()
                    }
                    else {
                        load(forceLoad: true)
                    }
                }
                .overlay(alignment:. topTrailing) {
                    Text(percentage, format: .percent)
                    .padding(5)
                }
                .overlay {
                    if case .paused(_) = vm.state {
                        Button("Resume") {
                            load(forceLoad: true)
                        }
                    }
                }
        case .lowDataMode:
            if let blurHash, let blurImage = UIImage(blurHash: blurHash, size: CGSize(width: 32, height: 32)) {
                Image(uiImage: blurImage)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: availableWidth,
                        height: height
                    )
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        load(forceLoad: true)
                    }
                    .overlay(alignment: .center) {
                        VStack(alignment: .center) {
                            Text("Loading paused (Low data mode)", comment: "Displayed when media in a post is blocked")
                                .fontWeightBold()
                            Text(galleryItem.url.absoluteString)
                                .fontItalic()
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button(String(localized: "Load anyway", comment: "Button to show the blocked content anyway")) {
                                load(forceLoad: true)
                            }
                            .padding(.bottom, 10)
                        }
                        .padding(10)
                    }
            }
            else {
                theme.background.opacity(0.7)
                    .frame(
                        width: availableWidth,
                        height: height
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        load(forceLoad: true)
                    }
                    .overlay(alignment: .center) {
                        VStack(alignment: .center) {
                            Text("Loading paused (Low data mode)", comment: "Displayed when media in a post is blocked")
                                .fontWeightBold()
                            Text(galleryItem.url.absoluteString)
                                .fontItalic()
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button(String(localized: "Load anyway", comment: "Button to show the blocked content anyway")) {
                                load(forceLoad: true)
                            }
                            .padding(.bottom, 10)
                        }
                        .padding(10)
                    }
            }
        case .httpBlocked:
            VStack {
                Text("non-https media blocked", comment: "Displayed when an image in a post is blocked")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(galleryItem.url.absoluteString)
                    .truncationMode(.middle)
                    .fontItalic()
                    .foregroundColor(theme.accent)
                Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
                    load(forceLoad: true)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
            }
            .padding(.horizontal, 10)
        case .dontAutoLoad:
            theme.background.opacity(0.7)
                .overlay {
                    if let blurImage {
                        Image(uiImage: blurImage)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: availableWidth,
                                height: height
                            )
                            .clipped()
                            .contentShape(Rectangle())
                    }
                }
                .frame(
                    width: availableWidth,
                    height: height
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    load(forceLoad: true)
                }
                .overlay(alignment: .center) {
                    VStack {
                        if isNSFW {
                            Text("NSFW")
                                .fontWeightBold()
                        }
                        Text("Tap to load media", comment: "An image placeholder the user can tap to load media (usually an image or gif)")
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text(galleryItem.url.absoluteString)
                            .foregroundColor(theme.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .fontItalic()
                            .font(.footnote)
                            .onTapGesture {
                                load(forceLoad: true)
                            }
                            .padding(3)
                    }
                }
        case .image(let imageInfo):
            if needsResolvedLayout(for: imageInfo.realDimensions) {
                unresolvedLayoutPlaceholder
                    .onAppear {
                        updateRealDimensions(imageInfo.realDimensions)
                    }
            }
            else if fullScreen {
                Image(uiImage: imageInfo.uiImage)
                    .resizable()
                    .scaledToFit()
                    .onAppear {
                        // Communicate back to set container frame
                        updateRealDimensions(imageInfo.realDimensions)
                    }
//                    .debugDimensions(".image fullscreen", alignment: .top)
            }
            else if contentMode == .fit {
                ZoomableItem(id: zoomableId) {
                    Image(uiImage: imageInfo.uiImage)
                        .resizable()
                        .scaledToFit()
                        .animation(.smooth(duration: 0.5), value: vm.state)
                } detailContent: {
                    GalleryFullScreenSwiper(
                        initialIndex: galleryItems?.firstIndex(where: { $0.url == galleryItem.url }) ?? 0,
                        items: galleryItems?.map {
                            GalleryItem(
                                url: $0.url,
                                pubkey: $0.pubkey,
                                eventId: $0.eventId,
                                dimensions: $0.url.absoluteString == galleryItem.url.absoluteString
                                    ? (cropImageRequestToTarget ? $0.dimensions : imageInfo.realDimensions)
                                    : nil,
                                blurhash: $0.url.absoluteString == galleryItem.url.absoluteString ? blurHash : nil,
                                // A grid image is an aspect-fill crop. Do not seed fullscreen with
                                // it; load the aspect-fit request just like pages reached by swiping.
                                imageInfo: $0.url.absoluteString == galleryItem.url.absoluteString && !cropImageRequestToTarget
                                    ? imageInfo
                                    : nil
                            )
                        } ?? [GalleryItem(
                            url: galleryItem.url,
                            pubkey: galleryItem.pubkey,
                            eventId: galleryItem.eventId,
                            dimensions: cropImageRequestToTarget ? galleryItem.dimensions : imageInfo.realDimensions,
                            blurhash:  galleryItem.blurhash ?? blurHash,
                            imageInfo: cropImageRequestToTarget ? nil : imageInfo)]
                    )
                }
                .onAppear {
                    // Communicate back to set container frame
                    updateRealDimensions(imageInfo.realDimensions)
                }
            }
            else {
                ZoomableItem(id: zoomableId) {
                    Image(uiImage: imageInfo.uiImage)
                        .resizable()
                        .scaledToFill()
                        .animation(.smooth(duration: 0.5), value: vm.state)
                        .frame(width: availableWidth, height: height, alignment: .center)
                } detailContent: {
                    GalleryFullScreenSwiper(
                        initialIndex: galleryItems?.firstIndex(where: { $0.url == galleryItem.url }) ?? 0,
                        items: galleryItems?.map {
                            GalleryItem(
                                url: $0.url,
                                pubkey: $0.pubkey,
                                eventId: $0.eventId,
                                dimensions: $0.url.absoluteString == galleryItem.url.absoluteString
                                    ? (cropImageRequestToTarget ? $0.dimensions : imageInfo.realDimensions)
                                    : nil,
                                blurhash: $0.url.absoluteString == galleryItem.url.absoluteString ? blurHash : nil,
                                // A grid image is an aspect-fill crop. Do not seed fullscreen with
                                // it; load the aspect-fit request just like pages reached by swiping.
                                imageInfo: $0.url.absoluteString == galleryItem.url.absoluteString && !cropImageRequestToTarget
                                    ? imageInfo
                                    : nil
                            )
                        } ?? [GalleryItem(
                            url: galleryItem.url,
                            pubkey: galleryItem.pubkey,
                            eventId: galleryItem.eventId,
                            dimensions: cropImageRequestToTarget ? galleryItem.dimensions : imageInfo.realDimensions,
                            blurhash:  galleryItem.blurhash ?? blurHash,
                            imageInfo: cropImageRequestToTarget ? nil : imageInfo)]
                    )
                }
                .onAppear {
                    // Communicate back to set container frame
                    updateRealDimensions(imageInfo.realDimensions)
                }
            }
        case .gif(let gifInfo):
            // gifInfo.gifData may contain either a GIF or an animated WebP
            let isWebP = isAnimatedWebPData(gifInfo.gifData)
            if needsResolvedLayout(for: gifInfo.realDimensions) {
                unresolvedLayoutPlaceholder
                    .onAppear {
                        updateRealDimensions(gifInfo.realDimensions)
                    }
            }
            else if fullScreen {
                // Create a touch-responsive wrapper around the animated image
                ZStack {
                    // Black background to maintain visual consistency during gestures
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    // Animated image content with hit testing disabled
                    if isWebP {
                        AnimatedWebPImage(data: gifInfo.gifData, isPlaying: $gifIsPlaying)
                            .animation(.smooth(duration: 0.5), value: vm.state)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        GIFImage(data: gifInfo.gifData, isPlaying: $gifIsPlaying)
                            .animation(.smooth(duration: 0.5), value: vm.state)
                            .aspectRatio(contentMode: .fit)
//                        .debugDimensions(".gif fullscreen", alignment: .top)
                    }
                }
                .onAppear {
                    // Communicate back to set container frame
                    updateRealDimensions(gifInfo.realDimensions)
                }
                .task(id: galleryItem.url.absoluteString) {
                    try? await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
                    gifIsPlaying = true
                }
                .onDisappear {
                    gifIsPlaying = false
                }
            }
            else if contentMode == .fit {
                ZoomableItem(id: zoomableId) {
                    if nxViewingContext.contains(.screenshot), let flatGif = UIImage(data: gifInfo.gifData) {
                        Image(uiImage: flatGif)
                            .resizable()
                            .scaledToFit()
                            .frame(width: availableWidth, height: height)
                            .contentShape(Rectangle())
                    }
                    else if isWebP {
                        AnimatedWebPImage(data: gifInfo.gifData, isPlaying: $gifIsPlaying)
                            .animation(.smooth(duration: 0.5), value: vm.state)
                            .aspectRatio(contentMode: .fit)
                            .contentShape(Rectangle())
                            .task(id: galleryItem.url.absoluteString) {
                                try? await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
                                gifIsPlaying = true
                            }
                            .onDisappear {
                                gifIsPlaying = false
                            }
                    }
                    else {
                        GIFImage(data: gifInfo.gifData, isPlaying: $gifIsPlaying)
                        .animation(.smooth(duration: 0.5), value: vm.state)
                        .aspectRatio(contentMode: .fit)
                        .contentShape(Rectangle())
                        .task(id: galleryItem.url.absoluteString) {
                            try? await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
                            gifIsPlaying = true
                        }
                        .onDisappear {
                            gifIsPlaying = false
                        }
                    }
                } detailContent: {
                    GalleryFullScreenSwiper(
                        initialIndex: galleryItems?.firstIndex(where: { $0.url == galleryItem.url }) ?? 0,
                        items: galleryItems?.map {
                            GalleryItem(
                                url: $0.url,
                                pubkey: $0.pubkey,
                                eventId: $0.eventId,
                                dimensions: $0.url.absoluteString == galleryItem.url.absoluteString ? gifInfo.realDimensions : nil,
                                blurhash: $0.url.absoluteString == galleryItem.url.absoluteString ? blurHash : nil,
                                gifInfo: $0.url.absoluteString == galleryItem.url.absoluteString ? gifInfo : nil
                            )
                        } ?? [GalleryItem(
                            url: galleryItem.url,
                            pubkey: galleryItem.pubkey,
                            eventId: galleryItem.eventId,
                            dimensions: gifInfo.realDimensions,
                            blurhash:  galleryItem.blurhash ?? blurHash,
                            gifInfo: gifInfo)]
                    )
                }
                .onAppear {
                    // Communicate back to set container frame
                    updateRealDimensions(gifInfo.realDimensions)
                }
            }
            else {
                ZoomableItem(id: zoomableId) {
                    if nxViewingContext.contains(.screenshot), let flatGif = UIImage(data: gifInfo.gifData) {
                        Image(uiImage: flatGif)
                            .resizable()
                            .scaledToFill()
                            .frame(width: availableWidth, height: height)
                            .contentShape(Rectangle())
                    }
                    else if isWebP {
                        AnimatedWebPImage(data: gifInfo.gifData, isPlaying: $gifIsPlaying)
                            .animation(.smooth(duration: 0.5), value: vm.state)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: availableWidth, height: height, alignment: .center)
                            .contentShape(Rectangle())
                            .task(id: galleryItem.url.absoluteString) {
                                try? await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
                                gifIsPlaying = true
                            }
                            .onDisappear {
                                gifIsPlaying = false
                            }
                    }
                    else {
                        GIFImage(data: gifInfo.gifData, isPlaying: $gifIsPlaying)
                            .animation(.smooth(duration: 0.5), value: vm.state)
                            .scaledToFill()
                            .frame(width: availableWidth, height: height, alignment: .center)
                            .contentShape(Rectangle())
                            .task(id: galleryItem.url.absoluteString) {
                                try? await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
                                gifIsPlaying = true
                            }
                            .onDisappear {
                                gifIsPlaying = false
                            }
                    }
                } detailContent: {
                    GalleryFullScreenSwiper(
                        initialIndex: galleryItems?.firstIndex(where: { $0.url == galleryItem.url }) ?? 0,
                        items: galleryItems?.map {
                            GalleryItem(
                                url: $0.url,
                                pubkey: $0.pubkey,
                                eventId: $0.eventId,
                                dimensions: $0.url.absoluteString == galleryItem.url.absoluteString ? gifInfo.realDimensions : nil,
                                blurhash: $0.url.absoluteString == galleryItem.url.absoluteString ? blurHash : nil,
                                gifInfo: $0.url.absoluteString == galleryItem.url.absoluteString ? gifInfo : nil
                            )
                        } ?? [GalleryItem(
                            url: galleryItem.url,
                            pubkey: galleryItem.pubkey,
                            eventId: galleryItem.eventId,
                            dimensions: gifInfo.realDimensions,
                            blurhash:  galleryItem.blurhash ?? blurHash,
                            gifInfo: gifInfo)]
                    )
                }
                .onAppear {
                    // Communicate back to set container frame
                    updateRealDimensions(gifInfo.realDimensions)
                }
            }
        case .imageTooLarge:
            failedImageView {
                VStack {
                    Label("Image is larger than 50 MB, not loaded.", systemImage: "exclamationmark.triangle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button("Load anyway") {
                        load(forceLoad: true, loadAnyway: true)
                    }
                }
            }
        case .error(_):
            failedImageView {
                VStack {
                    Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(galleryItem.url.absoluteString)
                        .truncationMode(.middle)
                        .fontItalic()
                        .foregroundColor(theme.accent)
                    Button(String(localized: "Try again", comment: "Button try again")) {
                        load(forceLoad: true)
                    }
                }
            }
        default:
            if let imageInfo {
                Color.clear
                    .onAppear {
                        vm.state = .image(imageInfo)
                        if fullScreen,
                           !usePFPpipeline,
                           needsFullscreenUpgrade(imageInfo) {
                            load(forceLoad: true, preserveCurrentImage: true)
                        }
                    }
            }
            else if let gifInfo {
                Color.clear
                    .onAppear {
                        vm.state = .gif(gifInfo)
                    }
            }
            else if (!autoload || isNSFW) && !fullScreen {
                Color.clear
                    .onAppear {
                        if let blurHash, let blurImage = UIImage(blurHash: blurHash, size: CGSize(width: 32, height: 32)) {
                            self.blurImage = blurImage
                        }
                        vm.state = .dontAutoLoad
                    }
            }
            else if let blurHash, let blurImage = UIImage(blurHash: blurHash, size: CGSize(width: 32, height: 32)) {
                Image(uiImage: blurImage)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: availableWidth,
                        height: height
                    )
                    .clipped()
                    .contentShape(Rectangle())
                    .onAppear {
                        self.blurImage = blurImage // reuse in other view states
                        load(forceLoad: fullScreen)
                    }
            }
            else {
                Color.clear
                    .onAppear {
                        load(forceLoad: fullScreen)
                    }
            }
        }
    }

    @ViewBuilder
    private func failedImageView<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
            theme.background.opacity(0.7)
                .overlay {
                    if let blurImage {
                        Image(uiImage: blurImage)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: availableWidth,
                                height: height
                            )
                            .clipped()
                            .contentShape(Rectangle())
                    }
                }
                .frame(
                    width: availableWidth,
                    height: height
                )
                .clipped()
                .contentShape(Rectangle())
                .overlay(alignment: .center) {
                    content()
                }
    }
    
    @MainActor
    private func load(
        forceLoad: Bool = false,
        loadAnyway: Bool = false,
        preserveCurrentImage: Bool = false
    ) {
        Task { @MainActor in
            await vm.load(
                galleryItem.url,
                forceLoad: forceLoad,
                loadAnyway: loadAnyway,
                generateIMeta: generateIMeta,
                usePFPpipeline: usePFPpipeline,
                targetSize: imageRequestTargetSize,
                cropToTarget: cropImageRequestToTarget && !fullScreen,
                preserveCurrentImage: preserveCurrentImage
            )
        }
    }

    private func needsFullscreenUpgrade(_ imageInfo: ImageInfo) -> Bool {
        guard let targetSize = imageRequestTargetSize,
              imageInfo.realDimensions.width > 0,
              imageInfo.realDimensions.height > 0
        else { return false }

        let imageAspect = imageInfo.realDimensions.width / imageInfo.realDimensions.height
        let targetAspect = targetSize.width / targetSize.height
        let fittedSize = if imageAspect > targetAspect {
            CGSize(width: targetSize.width, height: targetSize.width / imageAspect)
        }
        else {
            CGSize(width: targetSize.height * imageAspect, height: targetSize.height)
        }

        return imageInfo.uiImage.size.width + 1 < fittedSize.width
            || imageInfo.uiImage.size.height + 1 < fittedSize.height
    }
    
    @MainActor // Pause is because onDisappear, and will resume automatically on onAppear
    private func pauseLoad() {
        guard case .loading(let progress) = vm.state else { return }
        vm.pause(progress)
    }
}


struct MediaPostPreview: View {
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    @Binding private var showMiniProfile: Bool
    
    init(_ nrPost: NRPost, showMiniProfile: Binding<Bool>) {
        self.nrPost = nrPost
        self.nrContact = NRContact.instance(of: nrPost.pubkey)
        _showMiniProfile = showMiniProfile
    }
    
    var body: some View {
        HStack(alignment: .center) {
            ZappablePFP(pubkey: nrPost.pubkey, contact: nrPost.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
            
            VStack(alignment: .leading) {
                
                Text(nrContact.anyName)
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                    .onTapGesture {
                        dismiss()
                        navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, context: containerID)
                    }
                    .onAppear {
                        // TODO: check .missingPs instead of .contact?
                        guard nrPost.contact.metadata_created_at == 0 else { return }
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "FullImageViewer.001")
                            QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                        }
                    }
                    .onDisappear {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                    }
                
                if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                    NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                            .layoutPriority(3)
                }
                
                
                Text("Posted on \(nrPost.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .onTapGesture {
                        dismiss()
                        navigateTo(nrPost, context: containerID)
                    }
            }
            
            Image(systemName: "chevron.right")
                .padding(10)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                    navigateTo(nrPost, context: containerID)
                }
        }
        .font(.custom("Charter", size: 18))
        .padding(.vertical, 10)
        .lineLimit(1)
        .foregroundColor(Color.secondary)
    }
    
    func dismiss() {
        sendNotification(.closeFullscreenGallery)
    }
}

#Preview("Scale test") {
//    ScrollView {
        VStack {
            MediaContentView(
                galleryItem: GalleryItem(
                    url: URL(string: "https://i.nostr.build/baSKxXnbK9aQpuGv.jpg")!,
//                    dimensions: CGSize(width: 2539, height: 3683)
                    blurhash: "^SIz^+Iox^xZxvtQtlxuayaxayWC?^n$MxR+V?j]xut7ayWBayoef5jvV?WVR,j@WWWVjZaeoeofRjkCogoJt7azsoWBR+oeWBWXn%oLbaR*WBj["
                ),
                availableWidth: 360,
//                placeholderHeight: 360,
                contentMode: .fit
            )
            .border(Color.blue)
            .frame(width: 360, height: 200)
            
            Color.red
                .frame(width: 360, height: 200)
                .overlay {
                    Text("360x200")
                        .foregroundColor(.white)
                }
            
            MediaContentView(
                galleryItem: GalleryItem(
                    url:  URL(string: "https://i.nostr.build/baSKxXnbK9aQpuGv.jpg")!
//                    dimensions: CGSize(width: 2539, height: 3683)
//                    blurHash: "^SIz^+Iox^xZxvtQtlxuayaxayWC?^n$MxR+V?j]xut7ayWBayoef5jvV?WVR,j@WWWVjZaeoeofRjkCogoJt7azsoWBR+oeWBWXn%oLbaR*WBj["
                ),
                availableWidth: 360,
//                placeholderHeight: 360,
                contentMode: .fit
            )
            .border(Color.blue)
            .frame(width: 360, height: 200)
        }
//    }
    .environmentObject(Themes.default)
}

#Preview("Media view") {
    Zoomable {
        ScrollView {
            VStack {
                let testUrl = URL(string: "https://nostur.com/screenshots/c2/longform-dark.jpg")!
                // Test with explicit available space and image dimensions  (no GeometryReader needed)
                MediaContentView(
                    galleryItem: GalleryItem(
                        url: testUrl,
                        dimensions: .init(width: 1500, height: 1338)
                    ),
                    availableWidth: 360,
//                    placeholderHeight: 150,
                    
                    contentMode: .fit,
                    autoload: true
                )
                .border(Color.blue)
                .frame(width: 360)

                
////                // Test with no data at all (uses GeometryReader)
//                MediaContentView(
//                    media: MediaContent(
//                        url: testUrl,
//                        dimensions: .init(width: 1500, height: 1338)
//                    ),
////                    placeholderHeight: 150,
//                    autoload: true
//                )
//                .border(Color.blue)
//                .frame(width: 360, height: 150)
//////                .clipped()
////                
//                // Test with explicit available space but no image dimensions  (no GeometryReader needed)
                MediaContentView(
                    galleryItem: GalleryItem(
                        url: testUrl,
                        dimensions: .init(width: 1500, height: 1338)
                    ),
                    availableWidth: 360,
//                    placeholderHeight: 150,
                    maxHeight: 150,
                    contentMode: .fill,
                    autoload: true
                )
                .border(Color.blue)
                .frame(width: 360, height: 150)
////                .clipped()
            }
        }
    }
    .environmentObject(Themes.default)
}
