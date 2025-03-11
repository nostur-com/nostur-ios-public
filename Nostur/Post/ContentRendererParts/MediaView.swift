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
    public var contentMode: ContentMode = .fit
    
    var body: some View {
        MediaView(
            url: media.url,
            imageWidth: media.dimensions?.width,
            imageHeight: media.dimensions?.height,
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            contentMode: contentMode
        )
    }
}

struct MediaView: View {
    public let url: URL
    
    // Dimensions about the image/video from metadata
    public var imageWidth: CGFloat?
    public var imageHeight: CGFloat?
    
    // Available space provided by parent (optional)
    public var availableWidth: CGFloat?
    public var availableHeight: CGFloat?
    
    public var contentMode: ContentMode = .fit

    var body: some View {
        if contentMode == .fit {
            // Check if we have explicit available dimensions
            if let availableWidth, let availableHeight {
                MediaPlaceholder(
                    url: url,
                    frameWidth: calculatedSize(width: availableWidth, height: availableHeight).width,
                    frameHeight: calculatedSize(width: availableWidth, height: availableHeight).height,
                    contentMode: contentMode
                )
            } else {
                // Fall back to GeometryReader when no explicit dimensions are provided
                GeometryReader { geometry in
                    MediaPlaceholder(
                        url: url,
                        frameWidth: calculatedSize(width: geometry.size.width, height: geometry.size.height).width,
                        frameHeight: calculatedSize(width: geometry.size.width, height: geometry.size.height).height,
                        contentMode: contentMode
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
        else { // Same but with .fill and .clipped() instead
            // Check if we have explicit available dimensions
            if let availableWidth, let availableHeight {
                MediaPlaceholder(
                    url: url,
                    frameWidth: calculatedSize(width: availableWidth, height: availableHeight).width,
                    frameHeight: calculatedSize(width: availableWidth, height: availableHeight).height,
                    contentMode: .fill
                )
            } else {
                // Fall back to GeometryReader when no explicit dimensions are provided
                GeometryReader { geometry in
                    MediaPlaceholder(
                        url: url,
                        frameWidth: calculatedSize(width: geometry.size.width, height: geometry.size.height).width,
                        frameHeight: calculatedSize(width: geometry.size.width, height: geometry.size.height).height,
                        contentMode: .fill
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
       
    }

    private func calculatedSize(width maxWidth: CGFloat, height maxHeight: CGFloat) -> (width: CGFloat, height: CGFloat) {
        // Handle missing or invalid image dimensions
        guard let imageWidth, let imageHeight,
              imageWidth > 0, imageHeight > 0 else {
            return (maxWidth, maxHeight)
        }
        
        // Ensure we don't work with zero or negative sizes
        let safeMaxWidth = max(maxWidth, 1.0)
        let safeMaxHeight = max(maxHeight, 1.0)
        
        // Calculate scale factors for both dimensions
        let widthScale = safeMaxWidth / imageWidth
        let heightScale = safeMaxHeight / imageHeight
        
        // Use the smaller scale factor to ensure fit within bounds
        let scale = min(widthScale, heightScale)
        
        // Calculate final dimensions
        let targetWidth = imageWidth * scale
        let targetHeight = imageHeight * scale
        
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
                .border(Color.red)
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
        case .image(let image):
            if contentMode == .fit {
                image
                    .resizable()
                    .scaledToFit()
                    .overlay(alignment: .top) {
                        Text(".image.fit \(frameWidth)x\(frameHeight)")
                            .foregroundColor(.white)
                            .background(Color.black)
                    }
            }
            else {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(alignment: .top) {
                        Text(".image.fill \(frameWidth)x\(frameHeight)")
                            .foregroundColor(.white)
                            .background(Color.black)
                    }
            }
        case .gif(let gifData):
            if contentMode == .fit {
                GIFImage(data: gifData, isPlaying: .constant(true))
                    .aspectRatio(contentMode: .fit)
                    .overlay(alignment: .top) {
                        Text(".gif.fit \(frameWidth)x\(frameHeight)")
                            .foregroundColor(.white)
                            .background(Color.black)
                    }
            }
            else {
                GIFImage(data: gifData, isPlaying: .constant(true))
                    .aspectRatio(contentMode: .fill)
                    .overlay(alignment: .top) {
                        Text(".gif.fill \(frameWidth)x\(frameHeight)")
                            .foregroundColor(.white)
                            .background(Color.black)
                    }
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
            Color.green
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
