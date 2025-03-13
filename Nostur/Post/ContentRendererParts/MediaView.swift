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
    public var availableWidth: CGFloat?
    public var placeholderHeight: CGFloat? // Don't set availableHeight AND placeholderHeight, set only 1!!
    public var contentMode: ContentMode = .fit // if placeholderHeight is set, probably should use fill!!
    
    public var imageUrls: [URL]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    public var upscale: Bool = false
    public var autoload: Bool = false
    
    var body: some View {
        MediaView(
            url: media.url,
            blurHash: media.blurHash,
            imageWidth: media.dimensions?.width,
            imageHeight: media.dimensions?.height,
            availableWidth: availableWidth,
            placeholderHeight: placeholderHeight,
            contentMode: contentMode,
            imageUrls: imageUrls,
            upscale: upscale,
            autoload: autoload
        )
    }
}

struct MediaView: View {
    public let url: URL
    public var blurHash: String?
    
    // Dimensions about the image/video from metadata/imeta
    public var imageWidth: CGFloat?
    public var imageHeight: CGFloat?
    
    // Available space provided by parent (optional)
    public var availableWidth: CGFloat?
    
    // To prevent jumping, if we don't know availableHeight, shouldn't be 0 points
    public var placeholderHeight: CGFloat?
    
    public var contentMode: ContentMode = .fit
    
    public var imageUrls: [URL]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    public var upscale: Bool = false
    public var autoload: Bool = false
    
    // The actual dimensions, once the image is actually processed and loaded, should be set after download/processing
    @State private var realDimensions: CGSize?
    
    // availableWidth/availableHeight from param or GeometryReader
    func expectedImageSize(availableWidth: CGFloat, availableHeight: CGFloat) -> CGSize {
        let metaSize: CGSize? = if let imageWidth, let imageHeight {
            CGSize(width: imageWidth, height: imageHeight)
        }
        else { nil }
        
        // realDimensions load last, when we finally have them we use them instead of the info further down
        if let realDimensions {
            let aspect = realDimensions.height / realDimensions.width
            return CGSize(
                width: availableWidth,
                height: availableWidth * aspect
            )
        }
        
        // We have availableWidth
        // We have meta dimensions?
        //    OK scale to make it fit or fill (only if too wide)   (try to make DEFAULT KIND1BOTH available height high so we always have good scaled width
        
        if let metaSize, metaSize.width > availableWidth {
            let aspect = metaSize.height / metaSize.width
            return CGSize(
                width: availableWidth,
                height: availableWidth * aspect
            )
        }

        // Don't have meta dimensions
        //    OK scale to make it fit or fill to placeholder height
        // placeholder height comes from param or geo
        return CGSize(
            width: availableWidth,
            height: availableHeight
        )
    }

    var body: some View {
        if contentMode == .fit {
            // Check if we have explicit available dimensions
            if let availableWidth, let availableHeight = placeholderHeight {
                MediaPlaceholder(
                    url: url,
                    blurHash: blurHash,
                    expectedImageSize: expectedImageSize(availableWidth: availableWidth, availableHeight: availableHeight),
                    contentMode: contentMode,
                    imageUrls: imageUrls,
                    realDimensions: $realDimensions,
                    upscale: upscale,
                    autoload: autoload
                )
//                .overlay(alignment: .center) {
//                    Text("fit: \(expectedImageSize(availableWidth: availableWidth, availableHeight: availableHeight))")
//                        .foregroundColor(Color.yellow)
//                        .background(Color.black)
//                        .font(.footnote)
//                }
            }
            else {
                // Fall back to GeometryReader when no explicit dimensions are provided
                GeometryReader { geometry in
                    MediaPlaceholder(
                        url: url,
                        blurHash: blurHash,
                        expectedImageSize: expectedImageSize(availableWidth: geometry.size.width, availableHeight: placeholderHeight ?? geometry.size.height),
                        contentMode: contentMode,
                        imageUrls: imageUrls,
                        realDimensions: $realDimensions,
                        upscale: upscale,
                        autoload: autoload
                    )
//                    .overlay(alignment: .center) {
//                        Text("geo.fit: \(expectedImageSize(availableWidth: geometry.size.width, availableHeight: placeholderHeight ?? geometry.size.height))")
//                            .foregroundColor(Color.yellow)
//                            .background(Color.black)
//                            .font(.footnote)
//                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
        else { // Same but with .fill and .clipped() instead
            // Check if we have explicit available dimensions
            if let availableWidth, let availableHeight = placeholderHeight {
                MediaPlaceholder(
                    url: url,
                    blurHash: blurHash,
                    expectedImageSize: expectedImageSize(availableWidth: availableWidth, availableHeight: availableHeight),
                    contentMode: .fill,
                    imageUrls: imageUrls,
                    realDimensions: $realDimensions,
                    upscale: upscale,
                    autoload: autoload
                )
//                .overlay(alignment: .center) {
//                    Text("fill: \(expectedImageSize(availableWidth: availableWidth, availableHeight: availableHeight))")
//                        .foregroundColor(Color.yellow)
//                        .background(Color.black)
//                        .font(.footnote)
//                }
            }
            else {
                // Fall back to GeometryReader when no explicit dimensions are provided
                GeometryReader { geometry in
                    MediaPlaceholder(
                        url: url,
                        blurHash: blurHash,
                        expectedImageSize: expectedImageSize(availableWidth: geometry.size.width, availableHeight: placeholderHeight ?? geometry.size.height),
                        contentMode: .fill,
                        imageUrls: imageUrls,
                        realDimensions: $realDimensions,
                        upscale: upscale,
                        autoload: autoload
                    )
//                    .overlay(alignment: .center) {
//                        Text("geo.fill: \(expectedImageSize(availableWidth: geometry.size.width, availableHeight: placeholderHeight ?? geometry.size.height))")
//                            .foregroundColor(Color.yellow)
//                            .background(Color.black)
//                            .font(.footnote)
//                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
    }
}

struct MediaPlaceholder: View {
    
    @StateObject private var vm = MediaViewVM()
    @EnvironmentObject private var themes: Themes
    
    public let url: URL
    public var blurHash: String?
    public let expectedImageSize: CGSize
    public var contentMode: ContentMode = .fit
    public var imageUrls: [URL]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    @Binding var realDimensions: CGSize?
    @State private var gifIsPlaying = false
    
    public var upscale: Bool = false
    public var autoload: Bool = false
    
    @State private var blurImage: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var isVisible = false
    
    var body: some View {
        if contentMode == .fit {
            mediaPlaceholder
                .frame(
                    width: expectedImageSize.width,
                    height: expectedImageSize.height
                )
                .onAppear { isVisible = true }
                .onDisappear { isVisible = false }
//                .border(Color.green)
        }
        else {
            mediaPlaceholder
                .frame(
                    width: expectedImageSize.width,
                    height: expectedImageSize.height
                )
                .onAppear { isVisible = true }
                .onDisappear { isVisible = false }
//                .border(Color.red)
//                .border(Color.green)
                .clipped()
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
                                height: expectedImageSize.height
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
                        height: expectedImageSize.height
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
                        height: expectedImageSize.height
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
                                height: expectedImageSize.height
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
                        height: expectedImageSize.height
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
            await vm.load(url, expectedImageSize: expectedImageSize, contentMode: contentMode, upscale: upscale, forceLoad: forceLoad)
        }
    }
    
    @MainActor
    private func load(forceLoad: Bool = false) {
        Task {
            await vm.load(url, expectedImageSize: expectedImageSize, contentMode: contentMode, upscale: upscale, forceLoad: forceLoad)
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

#Preview {
    ScrollView {
        VStack {
            let testUrl = URL(string: "https://nostur.com/screenshots/c2/longform-dark.jpg")!
            // Test with explicit available space and image dimensions  (no GeometryReader needed)
            MediaView(
                url: testUrl,
                imageWidth: 480,
                imageHeight: 480,
                availableWidth: 360
            )
            .border(Color.blue)
            .frame(width: 360, height: 150)

            // Test with image dimensions but no available space (uses GeometryReader)
            MediaView(
                url: testUrl,
                imageWidth: 480,
                imageHeight: 480
            )
            .border(Color.blue)
            .frame(width: 360, height: 150)
            
            
            // Test with no data at all (uses GeometryReader)
            MediaView(
                url: testUrl
            )
            .border(Color.blue)
            .frame(width: 360, height: 150)
            
            
            // Test with explicit available space but no image dimensions  (no GeometryReader needed)
            MediaView(
                url: testUrl,
                availableWidth: 360
            )
            .border(Color.blue)
            .frame(width: 360, height: 150)
        }
    }
    .environmentObject(Themes.default)
}

