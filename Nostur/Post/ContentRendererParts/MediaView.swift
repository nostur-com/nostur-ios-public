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
    public var availableHeight: CGFloat?
    public var placeholderHeight: CGFloat? // Don't set availableHeight AND placeholderHeight, set only 1!!
    public var contentMode: ContentMode = .fit
    
    public var imageUrls: [URL]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    var body: some View {
        MediaView(
            url: media.url,
            imageWidth: media.dimensions?.width,
            imageHeight: media.dimensions?.height,
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            placeholderHeight: placeholderHeight,
            contentMode: contentMode,
            imageUrls: imageUrls
        )
    }
}

struct MediaView: View {
    public let url: URL
    
    // Dimensions about the image/video from metadata/imeta
    public var imageWidth: CGFloat?
    public var imageHeight: CGFloat?
    
    // Available space provided by parent (optional)
    public var availableWidth: CGFloat?
    public var availableHeight: CGFloat?
    
    // To prevent jumping, if we don't know availableHeight, shouldn't be 0 points
    public var placeholderHeight: CGFloat?
    
    public var contentMode: ContentMode = .fit
    
    public var imageUrls: [URL]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    // The actual dimensions, once the image is actually processed and loaded, should be set after download/processing
    @State private var realDimensions: CGSize?

    var body: some View {
        if contentMode == .fit {
            // Check if we have explicit available dimensions
            if let availableWidth, let availableHeight = (availableHeight ?? placeholderHeight) {
                MediaPlaceholder(
                    url: url,
                    frameWidth: calculatedSize(width: availableWidth, height: availableHeight).width,
                    frameHeight: calculatedSize(width: availableWidth, height: availableHeight).height,
                    contentMode: contentMode,
                    imageUrls: imageUrls,
                    realDimensions: $realDimensions
                )
//                .overlay(alignment: .center) {
//                    Text("calculatedSize.fit: \(calculatedSize(width: availableWidth, height: availableHeight).width)x\(calculatedSize(width: availableWidth, height: availableHeight).height)")
//                        .foregroundColor(Color.yellow)
//                        .background(Color.black)
//                }
            }
            else {
                // Fall back to GeometryReader when no explicit dimensions are provided
                GeometryReader { geometry in
                    MediaPlaceholder(
                        url: url,
                        frameWidth: calculatedSize(width: geometry.size.width, height: geometry.size.height).width,
                        frameHeight: calculatedSize(width: geometry.size.width, height: geometry.size.height).height,
                        contentMode: contentMode,
                        imageUrls: imageUrls,
                        realDimensions: $realDimensions
                    )
//                    .overlay(alignment: .center) {
//                        Text("calculatedSize.fit2: \(calculatedSize(width: geometry.size.width, height: geometry.size.height).width).width)x\(calculatedSize(width: geometry.size.width, height: geometry.size.height).height)")
//                            .foregroundColor(Color.yellow)
//                            .background(Color.black)
//                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
        else { // Same but with .fill and .clipped() instead
            // Check if we have explicit available dimensions
            if let availableWidth, let availableHeight = (availableHeight ?? placeholderHeight) {
                MediaPlaceholder(
                    url: url,
                    frameWidth: calculatedSize(width: availableWidth, height: availableHeight).width,
                    frameHeight: calculatedSize(width: availableWidth, height: availableHeight).height,
                    contentMode: .fill,
                    imageUrls: imageUrls,
                    realDimensions: $realDimensions
                )
//                .overlay(alignment: .center) {
//                    Text("calculatedSize.fill: \(calculatedSize(width: availableWidth, height: availableHeight).width)x\(calculatedSize(width: availableWidth, height: availableHeight).height)")
//                        .foregroundColor(Color.yellow)
//                        .background(Color.black)
//                }
            }
            else {
                // Fall back to GeometryReader when no explicit dimensions are provided
                GeometryReader { geometry in
                    MediaPlaceholder(
                        url: url,
                        frameWidth: calculatedSize(width: geometry.size.width, height: geometry.size.height).width,
                        frameHeight: calculatedSize(width: geometry.size.width, height: geometry.size.height).height,
                        contentMode: .fill,
                        imageUrls: imageUrls,
                        realDimensions: $realDimensions
                    )
//                    .overlay(alignment: .center) {
//                        Text("calculatedSize.fill2: \(calculatedSize(width: geometry.size.width, height: geometry.size.height).width).width)x\(calculatedSize(width: geometry.size.width, height: geometry.size.height).height)")
//                            .foregroundColor(Color.yellow)
//                            .background(Color.black)
//                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
       
    }

    private func calculatedSize(width availableWidth: CGFloat, height availableHeight: CGFloat) -> (width: CGFloat, height: CGFloat) {
        
        // We get REAL dimensions from response of imageTask (passed through @Binding)
        // We use that if we have it, else use imeta
        let imageWidth: CGFloat? = realDimensions?.width ?? self.imageWidth
        let imageHeight: CGFloat? = realDimensions?.height ?? self.imageHeight
        
        // Handle missing or invalid image dimensions (this runs before imageTask)
        guard let imageWidth, let imageHeight,
              imageWidth > 0, imageHeight > 0 else {
            print("availableWidth: \(availableWidth) maxHeight: \(availableHeight)")
            return (availableWidth, placeholderHeight ?? availableHeight)
        }
        
        // Ensure we don't work with zero or negative sizes
        let safeMaxWidth = max(availableWidth, 1.0)
        let safeMaxHeight = if placeholderHeight != nil {
            max(imageHeight, 1.0) // placeHolderHeight was set, so that means we were waiting for actual image height
        }
        else {
            max(availableHeight, 1.0) // no placeholder so just use availableHeight
        }

        // Calculate scale factors for both dimensions
        let widthScale = safeMaxWidth / imageWidth
        let heightScale = safeMaxHeight / imageHeight
        
        // Use the smaller scale factor to ensure fit within bounds
        let scale = if placeholderHeight != nil {
            widthScale // placeHolderHeight was set, so that means we were waiting for actual image height, so we always scale to max width and don't care about the height, it can grow as large as necessary
        }
        else { // no placeHolderHeight set, so we need to scale to either width or height to make it fit
            min(widthScale, heightScale)
        }
        
        // Calculate final dimensions
        let targetWidth = imageWidth * scale
        let targetHeight = imageHeight * scale
//        
//        print("safeMaxWidth: \(safeMaxWidth) safeMaxHeight: \(safeMaxHeight) widthScale: \(widthScale) heightScale: \(heightScale)")
//        print("targetWidth: \(targetWidth) targetHeight: \(targetHeight) scale: \(scale)")
        
        return (targetWidth, targetHeight)
    }
}

struct MediaPlaceholder: View {
    
    @StateObject private var vm = MediaViewVM()
    @EnvironmentObject private var themes: Themes
    
    public let url: URL
    public let frameWidth: CGFloat
    public let frameHeight: CGFloat
    public var contentMode: ContentMode = .fit
    public var imageUrls: [URL]? = nil // In case of multiple images in originating post, we can use this swipe to next image
    
    @Binding var realDimensions: CGSize?
    @State private var gifIsPlaying = false
    
    var body: some View {
        if contentMode == .fit {
            mediaPlaceholder
                .frame(
                    width: frameWidth,
                    height: frameHeight
                )
        }
        else {
            mediaPlaceholder
                .frame(
                    width: frameWidth,
                    height: frameHeight
                )
//                .border(Color.red)
                .clipped()
        }
    }
    
    
    @ViewBuilder
    private var mediaPlaceholder: some View {
        switch vm.state {
        case .loading(let percentage):
            HStack {
                Image(systemName: "hourglass.tophalf.filled")
                Text(percentage, format: .percent)
            }
        case .lowDataMode:
            Text(url.absoluteString)
                .foregroundColor(themes.theme.accent)
                .truncationMode(.middle)
                .onTapGesture {
                    load(overrideLowDataMode: true)
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
                    load()
                }
            }
        case .dontAutoLoad, .cancelled:
            VStack {
                Text("Tap to load media", comment: "An image placeholder the user can tap to load media (usually an image or gif)")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(url.absoluteString)
                    .truncationMode(.middle)
                    .fontItalic()
                    .foregroundColor(themes.theme.accent)
                Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
                    load()
                }
            }
        case .blurhashLoading:
            Color.red
        case .image(let imageInfo):
            if contentMode == .fit {
                Image(uiImage: imageInfo.uiImage)
                    .resizable()
                    .scaledToFit()
//                    .overlay(alignment: .top) {
//                        VStack {
//                            Text(".image.fit \(frameWidth)x\(frameHeight)")
//                            Text("real: \(imageInfo.realDimensions.width)x\(imageInfo.realDimensions.height)")
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
//                    .overlay(alignment: .top) {
//                        VStack {
//                            Text(".image.fill \(frameWidth)x\(frameHeight)")
//                            Text("real: \(imageInfo.realDimensions.width)x\(imageInfo.realDimensions.height)")
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
                    .aspectRatio(contentMode: .fit)
//                    .overlay(alignment: .top) {
//                        VStack {
//                            Text(".gif.fit \(frameWidth)x\(frameHeight)")
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
                    .aspectRatio(contentMode: .fill)
//                    .overlay(alignment: .top) {
//                        VStack {
//                            Text(".gif.fill \(frameWidth)x\(frameHeight)")
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
                    load()
                }
            }
        default:
            Color.clear
                .onAppear {
                    load()
                }
        }
    }
    
    @MainActor
    private func load(overrideLowDataMode: Bool = false) {
        Task {
            await vm.load(url, width: frameWidth, height: frameHeight, contentMode: contentMode, overrideLowDataMode: overrideLowDataMode)
        }
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

#Preview {
    ScrollView {
        VStack {
            let testUrl = URL(string: "https://nostur.com/screenshots/c2/longform-dark.jpg")!
            // Test with explicit available space and image dimensions  (no GeometryReader needed)
            MediaView(
                url: testUrl,
                imageWidth: 480,
                imageHeight: 480,
                availableWidth: 360,
                availableHeight: 150
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
                availableWidth: 360,
                availableHeight: 150
            )
            .border(Color.blue)
            .frame(width: 360, height: 150)
        }
    }
    .environmentObject(Themes.default)
}
