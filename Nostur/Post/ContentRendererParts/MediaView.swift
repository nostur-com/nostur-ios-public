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
    public var media: MediaContent
    public var availableWidth: CGFloat
    public var placeholderHeight: CGFloat? // to reduce jumping
    public var maxHeight: CGFloat = 4000.0
    public var contentMode: ContentMode = .fit // if placeholderHeight is set, probably should use fill!!
    
    public var imageUrls: [URL]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    public var upscale: Bool = false
    public var autoload: Bool = false
    
    // will sendNotification with image dimensions / blurhash 
    public var generateIMeta: Bool = false
    
    // The actual dimensions, once the image is actually processed and loaded, should be set after download/processing
    @State private var realDimensions: CGSize?
    
    var body: some View {
        MediaPlaceholder(
            url: media.url,
            blurHash: media.blurHash,
            expectedImageSize: expectedImageSize(availableWidth: availableWidth, maxHeight: maxHeight),
            maxHeight: maxHeight,
            contentMode: contentMode,
            imageUrls: imageUrls,
            realDimensions: $realDimensions,
            upscale: upscale,
            autoload: autoload,
            generateIMeta: generateIMeta
        )
    }
    
    func expectedImageSize(availableWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        // Keep it simple
        // 1. Always scale to available width
        // 2. If .fit and height > maxHeight, the scale down
        
        
        // realDimensions load last, when we finally have them we use them instead of the info further down
        if let realDimensions {
            let aspect = realDimensions.width / realDimensions.height // 200 / 100 = 2
            //let isPortrait = aspect < 1 // 2 < 1 = false
            
            if contentMode == .fill { // 200x100 -> 400x200
                return CGSize(
                    width: availableWidth, // 400
                    height: availableWidth / aspect // 400 / 2 = // 200
                )
            }
            
            // if 200 > 100
            if realDimensions.height > maxHeight { // 200 > 100 so 100x200 -> 50x100
                return CGSize(
                    width: maxHeight / aspect, // 100 / 2 = 50
                    height: maxHeight // = 100
                )
            }
            
            // uhh, same as fill? We can reorganize this logic then...
            return CGSize(
                width: availableWidth, // 400
                height: availableWidth / aspect // 400 / 2 = // 200
            )
        }
        
        let metaSize: CGSize? = if let imageWidth = media.dimensions?.width, let imageHeight = media.dimensions?.height {
            CGSize(width: imageWidth, height: imageHeight)
        }
        else { nil }
        

        if let metaSize {
            let aspect = metaSize.width / metaSize.height // 200 / 100 = 2
            //let isPortrait = aspect < 1 // 2 < 1 = false
            
            if contentMode == .fill { // 200x100 -> 400x200
                return CGSize(
                    width: availableWidth, // 400
                    height: availableWidth / aspect // 400 / 2 = // 200
                )
            }
            
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
    
    public let url: URL
    public var blurHash: String?
    public let expectedImageSize: CGSize
    public let maxHeight: CGFloat
    public var contentMode: ContentMode = .fit
    public var fullScreen: Bool = false
    public var imageUrls: [URL]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    @Binding var realDimensions: CGSize?
    @State private var gifIsPlaying = false
    
    public var upscale: Bool = false
    public var autoload: Bool = false
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
        case .loading(let percentage):
            themes.theme.listBackground.opacity(0.2)
                .onDisappear {
                    guard case .loading(let percentage) = vm.state else { return }
                    if percentage < 98 {
                        cancelLoad()
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
                        Text(url.absoluteString)
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
                        Text(url.absoluteString)
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
                Text(url.absoluteString)
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
                        Text(url.absoluteString)
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
            if contentMode == .fit {
                Image(uiImage: imageInfo.uiImage)
                    .resizable()
                    .scaledToFit()
                    .animation(.smooth(duration: 0.5), value: vm.state)
//                Color.red
//                    .overlay(alignment: .top) {
//                        VStack {
//                            Text(".image.fit \(expectedImageSize.width)x\(expectedImageSize.height)")
//                                .font(.footnote)
//                            Text("real: \(imageInfo.realDimensions.width)x\(imageInfo.realDimensions.height)")
//                                .font(.footnote)
//                        }
//                            .foregroundColor(.white)
//                            .background(Color.black)
//                    }
                    .onAppear {
                        // Communicate back to set container frame
                        realDimensions = imageInfo.realDimensions
                    }
                    .onTapGesture { imageTap() }
            }
            else {
                Image(uiImage: imageInfo.uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .animation(.smooth(duration: 0.5), value: vm.state)
//                    .debugDimensions("Image", alignment: .topLeading)
//                    .overlay(alignment: .top) {
//                        VStack {
//                            Text(".image.fill \(expectedImageSize.width)x\(expectedImageSize.height)")
//                                .font(.footnote)
//                            Text("real: \(imageInfo.realDimensions.width)x\(imageInfo.realDimensions.height)")
//                                .font(.footnote)
//                        }
//                            .foregroundColor(.white)
//                            .background(Color.black)
//                    }
                    .onAppear {
                        // Communicate back to set container frame
                        realDimensions = imageInfo.realDimensions
                    }
                    .onTapGesture { imageTap() }
            }
        case .gif(let gifData):
            if contentMode == .fit {
                GIFImage(data: gifData.gifData, isPlaying: $gifIsPlaying)
                    .animation(.smooth(duration: 0.5), value: vm.state)
                    .aspectRatio(contentMode: .fit)
//                    .overlay(alignment: .top) {
//                        VStack {
//                            Text(".gif.fit \(expectedImageSize.width)x\(expectedImageSize.height)")
//                            Text("real: \(gifData.realDimensions.width)x\(gifData.realDimensions.height)")
//                        }
//                            .foregroundColor(.white)
//                            .background(Color.black)
//                    }
                    .onAppear {
                        // Communicate back to set container frame
                        realDimensions = gifData.realDimensions
                    }
                    .task(id: url.absoluteString) {
                        try? await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
                        gifIsPlaying = true
                    }
                    .onDisappear {
                        gifIsPlaying = false
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { imageTap() }
            }
            else {
                GIFImage(data: gifData.gifData, isPlaying: $gifIsPlaying)
                    .animation(.smooth(duration: 0.5), value: vm.state)
                    .aspectRatio(contentMode: .fill)
//                    .overlay(alignment: .top) {
//                        VStack {
//                            Text(".gif.fill \(expectedImageSize.width)x\(expectedImageSize.height)")
//                            Text("real: \(gifData.realDimensions.width)x\(gifData.realDimensions.height)")
//                        }
//                            .foregroundColor(.white)
//                            .background(Color.black)
//                    }
                    .onAppear {
                        // Communicate back to set container frame
                        realDimensions = gifData.realDimensions
                    }
                    .task(id: url.absoluteString) {
                        try? await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
                        gifIsPlaying = true
                    }
                    .onDisappear {
                        gifIsPlaying = false
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { imageTap() }
            }
        case .error(_):
            VStack {
                Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(url.absoluteString)
                    .truncationMode(.middle)
                    .fontItalic()
                    .foregroundColor(themes.theme.accent)
                Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
                    debounceLoad()
                }
            }
        default:
            if !autoload {
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
                        debounceLoad()
                    }
            }
            else {
                Color.clear
                    .onAppear {
                        debounceLoad()
                    }
            }
        }
    }
    
    @MainActor
    private func debounceLoad(forceLoad: Bool = false) {
        // Cancel any existing load task
        cancelLoad()
        
        // Create a new debounced load task
        loadTask = Task {
            // Wait for a short delay to debounce rapid scrolling
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Check if the task was cancelled during the delay
            if Task.isCancelled { return }
            
            // Check if the view is still visible
            if !isVisible && !forceLoad { return }
            
            // Proceed with loading
            await vm.load(url, expectedImageSize: expectedImageSize, contentMode: contentMode, upscale: upscale, forceLoad: forceLoad, generateIMeta: generateIMeta)
        }
    }
    
    @MainActor
    private func load(forceLoad: Bool = false) {
        Task {
            await vm.load(url, expectedImageSize: expectedImageSize, contentMode: contentMode, upscale: upscale, forceLoad: forceLoad, generateIMeta: generateIMeta)
        }
    }
    
    @MainActor
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        guard case .loading(_) = vm.state else { return }
        vm.cancel()
    }
    
    private func imageTap() {
        if let imageUrls, imageUrls.count > 1, #available(iOS 17, *) {
            let items: [GalleryItem] = imageUrls.map { GalleryItem(url: $0) }
            let index: Int = imageUrls.firstIndex(of: url) ?? 0
            sendNotification(.fullScreenView17, FullScreenItem17(items: items, index: index))
        }
        else {
            sendNotification(.fullScreenView, FullScreenItem(url: url))
        }
    }
}

#Preview("Scale test") {
//    ScrollView {
        VStack {
            MediaContentView(
                media: MediaContent(
                    url:  URL(string: "https://i.nostr.build/baSKxXnbK9aQpuGv.jpg")!,
//                    dimensions: CGSize(width: 2539, height: 3683)
                    blurHash: "^SIz^+Iox^xZxvtQtlxuayaxayWC?^n$MxR+V?j]xut7ayWBayoef5jvV?WVR,j@WWWVjZaeoeofRjkCogoJt7azsoWBR+oeWBWXn%oLbaR*WBj["
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
                media: MediaContent(
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
                    media: MediaContent(
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
                    media: MediaContent(
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

