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
    public var placeholderHeight: CGFloat? // to reduce jumping
    public var maxHeight: CGFloat = 4000.0
    public var contentMode: ContentMode = .fit // if placeholderHeight is set, probably should use fill!!
    public var fullScreen: Bool = false
    
    public var galleryItems: [GalleryItem]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    public var upscale: Bool = false
    public var autoload: Bool = false
    public var imageInfo: ImageInfo? = nil
    public var gifInfo: GifInfo? = nil
    
    // will sendNotification with image dimensions / blurhash 
    public var generateIMeta: Bool = false
    
    // The actual dimensions, once the image is actually processed and loaded, should be set after download/processing
    @State private var realDimensions: CGSize?
    
    var body: some View {
        MediaPlaceholder(
            galleryItem: galleryItem,
            blurHash: galleryItem.blurhash,
            expectedImageSize: expectedImageSize(availableWidth: availableWidth, maxHeight: maxHeight),
            maxHeight: maxHeight,
            contentMode: contentMode,
            fullScreen: fullScreen,
            galleryItems: galleryItems,
            realDimensions: $realDimensions,
            upscale: upscale,
            autoload: autoload,
            imageInfo: imageInfo,
            gifInfo: gifInfo,
            generateIMeta: generateIMeta
        )
    }
    
    func expectedImageSize(availableWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        // Keep it simple
        // 1. Always scale to available width
        // 2. If .fit and height > maxHeight, the scale down
        
        // If .fill just return availableWidth + min(placeholderHeight/maxHeight)
        
        if contentMode == .fill {
            return CGSize(width: availableWidth, height: min(placeholderHeight ?? maxHeight, maxHeight))
        }
        
        
        // realDimensions load last, when we finally have them we use them instead of the info further down
        if let realDimensions {
            let aspect = realDimensions.width / realDimensions.height // 200 / 100 = 2
            
            // if 200 > 100
            if realDimensions.height > maxHeight { // 200 > 100 so 100x200 -> 50x100
                return CGSize(
                    width: maxHeight / aspect, // 100 / 2 = 50
                    height: maxHeight // = 100
                )
            }
            
            return CGSize(
                width: availableWidth, // 400
                height: availableWidth / aspect // 400 / 2 = // 200
            )
        }
        
        let metaSize: CGSize? = if let imageWidth = galleryItem.dimensions?.width, let imageHeight = galleryItem.dimensions?.height {
            CGSize(width: imageWidth, height: imageHeight)
        }
        else { nil }
        

        if let metaSize {
            let aspect = metaSize.width / metaSize.height // 200 / 100 = 2
                        
            let availableAspect = availableWidth / maxHeight
            
            if availableAspect < aspect { // Fit horizontal or vertical?
                // Fit: scale width down if needed
                if metaSize.width > availableWidth {
                    return CGSize(
                        width: availableWidth,
                        height: availableWidth / aspect
                    )
                }
            }
            else {
                // Fit: scale height down if needed
                if metaSize.height > maxHeight {
                    return CGSize(
                        width: maxHeight / aspect,
                        height: maxHeight
                    )
                }
            }
            
            // Already fits, use max width
            return CGSize(
                width: availableWidth,
                height: availableWidth / aspect
            )
        }
        

        // Don't have meta dimensions
        // So scale to placeholder height or try 1:1 using availableWidth
        return CGSize(
            width: availableWidth,
            height: placeholderHeight ?? availableWidth // (1:1 if we dont have placeholderHeight)
        )
    }
}

struct MediaPlaceholder: View {
    
    @StateObject private var vm = MediaViewVM()
    @EnvironmentObject private var themes: Themes
    
    public let galleryItem: GalleryItem
    public var blurHash: String?
    public let expectedImageSize: CGSize
    public let maxHeight: CGFloat
    public var contentMode: ContentMode = .fit
    public var fullScreen: Bool = false
    public var galleryItems: [GalleryItem]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    @Binding var realDimensions: CGSize?
    @State private var gifIsPlaying = false
    
    public var upscale: Bool = false
    public var autoload: Bool = false
    public var imageInfo: ImageInfo? = nil
    public var gifInfo: GifInfo? = nil
    public var generateIMeta: Bool = false
    
    @State private var blurImage: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var isVisible = false
    
    var body: some View {
        if contentMode == .fit {
            mediaPlaceholder
                .frame(
                    width: expectedImageSize.width,
                    height: min(expectedImageSize.height, maxHeight)
                )
                .onAppear { isVisible = true }
                .onDisappear { isVisible = false }
//                .overlay(alignment: .center) {
//                    Text("fit: \(expectedImageSize.width)x\(expectedImageSize.height)")
//                        .foregroundColor(Color.yellow)
//                        .background(Color.black)
//                        .font(.footnote)
//                }
        }
        else {
          mediaPlaceholder
                .frame(
                    width: expectedImageSize.width,
                    height: min(expectedImageSize.height, maxHeight)
                )
                .onAppear { isVisible = true }
                .onDisappear { isVisible = false }
                .clipped()
//                .debugDimensions()
//                .overlay(alignment: .center) {
//                    Text("fill: \(expectedImageSize.width)x\(expectedImageSize.height)")
//                        .foregroundColor(Color.yellow)
//                        .background(Color.black)
//                        .font(.footnote)
//                }
        }
    }
    
    
    @ViewBuilder
    private var mediaPlaceholder: some View {
        switch vm.state {
        case .loading(let percentage), .paused(let percentage):
            themes.theme.listBackground.opacity(0.2)
                .onAppear {
                    guard case .paused(let percentage) = vm.state else { return }
                    debounceLoad(forceLoad: true)
                }
                .onDisappear {
                    guard case .loading(let percentage) = vm.state else { return }
                    if percentage < 98 {
                        pauseLoad()
                    }
                }
                .overlay {
                    if let blurImage {
                        Image(uiImage: blurImage)
                            .resizable()
//                            .animation(.smooth(duration: 0.2), value: vm.state)
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: expectedImageSize.width,
                                height: min(expectedImageSize.height, maxHeight)
                            )
                            .clipped()
                    }
                }
                .frame(
                    width: expectedImageSize.width,
                    height: expectedImageSize.height
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    debounceLoad(forceLoad: true)
                }
                .overlay(alignment:. topTrailing) {
                    HStack {
                        Image(systemName: "hourglass.tophalf.filled")
                        Text(percentage, format: .percent)
                    }
                    .padding(5)
                }
        case .lowDataMode:
            if let blurHash, let blurImage = UIImage(blurHash: blurHash, size: CGSize(width: 32, height: 32)) {
                Image(uiImage: blurImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: expectedImageSize.width,
                        height: min(expectedImageSize.height, maxHeight)
                    )
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        debounceLoad(forceLoad: true)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text(galleryItem.url.absoluteString)
                            .foregroundColor(themes.theme.accent)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .font(.footnote)
                            .onTapGesture {
                                debounceLoad(forceLoad: true)
                            }
                            .padding(3)
                    }
            }
            else {
                themes.theme.listBackground.opacity(0.2)
                    .frame(
                        width: expectedImageSize.width,
                        height: min(expectedImageSize.height, maxHeight)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        debounceLoad(forceLoad: true)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text(galleryItem.url.absoluteString)
                            .foregroundColor(themes.theme.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.footnote)
                            .onTapGesture {
                                debounceLoad(forceLoad: true)
                            }
                            .padding(3)
                    }
            }
        case .httpBlocked:
            VStack {
                Text("non-https media blocked", comment: "Displayed when an image in a post is blocked")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(galleryItem.url.absoluteString)
                    .truncationMode(.middle)
                    .fontItalic()
                    .foregroundColor(themes.theme.accent)
                Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
                    debounceLoad(forceLoad: true)
                }
            }
        case .dontAutoLoad, .cancelled:
            themes.theme.listBackground.opacity(0.2)
                .overlay {
                    if let blurImage {
                        Image(uiImage: blurImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: expectedImageSize.width,
                                height: min(expectedImageSize.height, maxHeight)
                            )
                            .clipped()
                    }
                }
                .frame(
                    width: expectedImageSize.width,
                    height: min(expectedImageSize.height, maxHeight)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    debounceLoad(forceLoad: true)
                }
                .overlay(alignment: .center) {
                    VStack {
                        Text("Tap to load media", comment: "An image placeholder the user can tap to load media (usually an image or gif)")
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text(galleryItem.url.absoluteString)
                            .foregroundColor(themes.theme.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .fontItalic()
                            .font(.footnote)
                            .onTapGesture {
                                debounceLoad(forceLoad: true)
                            }
                            .padding(3)
                    }
                }
        case .image(let imageInfo):
            if fullScreen {
                Image(uiImage: imageInfo.uiImage)
                    .resizable()
                    .scaledToFit()
                    .onAppear {
                        // Communicate back to set container frame
                        realDimensions = imageInfo.realDimensions
                    }
            }
            else if contentMode == .fit {
                ZoomableItem {
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
                                dimensions: $0.url.absoluteString == galleryItem.url.absoluteString ? imageInfo.realDimensions : nil,
                                blurhash: $0.url.absoluteString == galleryItem.url.absoluteString ? blurHash : nil,
                                imageInfo: $0.url.absoluteString == galleryItem.url.absoluteString ? imageInfo : nil
                            )
                        } ?? [GalleryItem(
                            url: galleryItem.url,
                            pubkey: galleryItem.pubkey,
                            eventId: galleryItem.eventId,
                            dimensions: imageInfo.realDimensions,
                            blurhash:  galleryItem.blurhash ?? blurHash,
                            imageInfo: imageInfo)]
                    )
                }
                .onAppear {
                    // Communicate back to set container frame
                    realDimensions = imageInfo.realDimensions
                }
            }
            else {
                ZoomableItem {
                    Image(uiImage: imageInfo.uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .animation(.smooth(duration: 0.5), value: vm.state)
                } detailContent: {
                    GalleryFullScreenSwiper(
                        initialIndex: galleryItems?.firstIndex(where: { $0.url == galleryItem.url }) ?? 0,
                        items: galleryItems?.map {
                            GalleryItem(
                                url: $0.url,
                                pubkey: $0.pubkey,
                                eventId: $0.eventId,
                                dimensions: $0.url.absoluteString == galleryItem.url.absoluteString ? imageInfo.realDimensions : nil,
                                blurhash: $0.url.absoluteString == galleryItem.url.absoluteString ? blurHash : nil,
                                imageInfo: $0.url.absoluteString == galleryItem.url.absoluteString ? imageInfo : nil
                            )
                        } ?? [GalleryItem(
                            url: galleryItem.url,
                            pubkey: galleryItem.pubkey,
                            eventId: galleryItem.eventId,
                            dimensions: imageInfo.realDimensions,
                            blurhash:  galleryItem.blurhash ?? blurHash,
                            imageInfo: imageInfo)]
                    )
                }
                .onAppear {
                    // Communicate back to set container frame
                    realDimensions = imageInfo.realDimensions
                }
            }
        case .gif(let gifInfo):
            if fullScreen {
                // Create a touch-responsive wrapper around the GIF
                ZStack {
                    // Black background to maintain visual consistency during gestures
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    // GIF content with hit testing disabled
                    GIFImage(data: gifInfo.gifData, isPlaying: $gifIsPlaying)
                        .animation(.smooth(duration: 0.5), value: vm.state)
                        .aspectRatio(contentMode: .fit)
                }
                .onAppear {
                    // Communicate back to set container frame
                    realDimensions = gifInfo.realDimensions
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
                ZoomableItem {
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
                    realDimensions = gifInfo.realDimensions
                }
            }
            else {
                ZoomableItem {
                    GIFImage(data: gifInfo.gifData, isPlaying: $gifIsPlaying)
                        .animation(.smooth(duration: 0.5), value: vm.state)
                        .aspectRatio(contentMode: .fill)
                        .contentShape(Rectangle())
                        .task(id: galleryItem.url.absoluteString) {
                            try? await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
                            gifIsPlaying = true
                        }
                        .onDisappear {
                            gifIsPlaying = false
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
                    realDimensions = gifInfo.realDimensions
                }
            }
        case .error(_):
            themes.theme.listBackground.opacity(0.2)
                .overlay {
                    if let blurImage {
                        Image(uiImage: blurImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: expectedImageSize.width,
                                height: min(expectedImageSize.height, maxHeight)
                            )
                            .clipped()
                    }
                }
                .frame(
                    width: expectedImageSize.width,
                    height: min(expectedImageSize.height, maxHeight)
                )
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    debounceLoad(forceLoad: true)
                }
                .overlay(alignment: .center) {
                    VStack {
                        Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text(galleryItem.url.absoluteString)
                            .truncationMode(.middle)
                            .fontItalic()
                            .foregroundColor(themes.theme.accent)
                        Button(String(localized: "Try again", comment: "Button try again")) {
                            debounceLoad(forceLoad: true)
                        }
                    }
                }
        default:
            if let imageInfo {
                Color.clear
                    .onAppear {
                        vm.state = .image(imageInfo)
                    }
            }
            else if let gifInfo {
                Color.clear
                    .onAppear {
                        vm.state = .gif(gifInfo)
                    }
            }
            else if !autoload && !fullScreen {
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
                    .aspectRatio(contentMode: .fill)
//                    .animation(.smooth(duration: 0.2), value: vm.state)
                    .frame(
                        width: expectedImageSize.width,
                        height: min(expectedImageSize.height, maxHeight)
                    )
                    .clipped()
                    .contentShape(Rectangle())
                    .onAppear {
                        withAnimation {
                            self.blurImage = blurImage
                        }
                        debounceLoad(forceLoad: fullScreen)
                    }
            }
            else {
                Color.clear
                    .onAppear {
                        debounceLoad(forceLoad: fullScreen)
                    }
            }
        }
    }
    
    @MainActor
    private func debounceLoad(forceLoad: Bool = false) {
        // Cancel any existing load task
        cancelLoad()
        
        // Create a new debounced load task
        loadTask = Task.detached(priority: .low) {
            // Wait for a short delay to debounce rapid scrolling
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Check if the task was cancelled during the delay
            if Task.isCancelled { return }
            
            // Check if the view is still visible
            if !isVisible && !forceLoad { return }
            
            // Proceed with loading
            await vm.load(galleryItem.url, expectedImageSize: expectedImageSize, contentMode: contentMode, upscale: upscale, forceLoad: forceLoad, generateIMeta: generateIMeta)
        }
    }
    
    @MainActor
    private func load(forceLoad: Bool = false) {
        Task.detached(priority: .low) {
            await vm.load(galleryItem.url, expectedImageSize: expectedImageSize, contentMode: contentMode, upscale: upscale, forceLoad: forceLoad, generateIMeta: generateIMeta)
        }
    }
    
    @MainActor // Pause is because onDisappear, and will resume automatically on onAppear
    private func pauseLoad() {
        loadTask?.cancel()
        guard case .loading(let progress) = vm.state else { return }
        vm.pause(progress)
    }
    
    @MainActor // Cancel is by user
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        guard case .loading(_) = vm.state else { return }
        vm.cancel()
    }
}


struct MediaPostPreview: View {
    @EnvironmentObject private var themes: Themes
    private let nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    @Binding private var showMiniProfile: Bool
    
    init(_ nrPost: NRPost, showMiniProfile: Binding<Bool>) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        _showMiniProfile = showMiniProfile
    }
    
    var body: some View {
        HStack(alignment: .center) {
            ZappablePFP(pubkey: nrPost.pubkey, pfpAttributes: pfpAttributes, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
            
            VStack(alignment: .leading) {
                
                Text(pfpAttributes.anyName)
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                    .onTapGesture {
                        dismiss()
                        if let nrContact = nrPost.contact {
                            navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                        }
                        else {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
                    }
                    .onAppear {
                        guard nrPost.contact == nil else { return }
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "FullImageViewer.001")
                            QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                        }
                    }
                    .onDisappear {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                    }
                
                if let nrContact = pfpAttributes.contact, nrContact.nip05verified, let nip05 = nrContact.nip05 {
                    NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly.lowercased())
                            .layoutPriority(3)
                }
                
                
                Text("Posted on \(nrPost.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .onTapGesture {
                        dismiss()
                        navigateTo(nrPost)
                    }
            }
            
            Image(systemName: "chevron.right")
                .padding(10)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                    navigateTo(nrPost)
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

