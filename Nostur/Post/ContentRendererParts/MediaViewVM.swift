//
//  MediaViewVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI
import NukeUI
import Nuke

class MediaViewVM: ObservableObject {
    @Published var state: MediaViewState = .initial
    private var task: ImageTask?
    
    public func load(_ url: URL, forceLoad: Bool = false, generateIMeta: Bool = false, usePFPpipeline: Bool = false) async {
        if SettingsStore.shared.lowDataMode && !forceLoad {
            Task { @MainActor in
                state = .lowDataMode
            }
            return
        }
        
        if url.absoluteString.prefix(7) == "http://" && !forceLoad {
            Task { @MainActor in
                state = .httpBlocked
            }
            return
        }
        
        self.task = usePFPpipeline
            ? ImageProcessing.shared.pfp.imageTask(with: pfpImageRequestFor(url))
            : ImageProcessing.shared.content.imageTask(with: makeImageRequest(url,
                                                                              label: "MediaViewVM.load",
                                                                              overrideLowDataMode: forceLoad))
        
        guard let task = self.task else {
            Task { @MainActor in
                state = .error("Error loading media")
            }
            return
        }
        
        Task { @MainActor in
            
            // resume from paused?
            let progress = if case .paused(let progress) = state { progress }
            else { 0 } // resume from 0
            
            state = .loading(progress)
        }
        
        for await progress in task.progress {            
            Task { @MainActor in
                // Don't update loading if not loading, (could already be finished) (because async out of order)
                if case .loading(let currentProgress) = state {
                    let newProgress = Int(ceil(progress.fraction * 100))
                    if currentProgress != newProgress { // Only rerender if progress actually changed
                        state = .loading(newProgress)
                    }
                }
            }
        }
    
        do {
            let response = try await task.response
            if response.container.type == .gif, let gifData = response.container.data {
                Task { @MainActor in
                    // Can't use withAnimation. Bug keeps sometimes stuck at loading %0
//                    withAnimation(.smooth(duration: 0.15)) {
                      state = .gif(GifInfo(gifData: gifData, realDimensions: response.container.image.size))
//                    }
                    if generateIMeta {
                        let blurhash: String? = response.container.image.blurHash(numberOfComponents: (4, 3))
                        let pixelSize = CGSize(width: response.container.image.size.width * UIScreen.main.scale, height: response.container.image.size.height * UIScreen.main.scale)
                        let iMetaInfo = iMetaInfo(size: pixelSize, blurHash: blurhash)
                        Task { @MainActor in
                            sendNotification(.iMetaInfoForUrl, (url.absoluteString, iMetaInfo))
                        }
                    }
                }
            }
            else {
                Task { @MainActor in
                    // Can't use withAnimation. Bug keeps sometimes stuck at loading %0
//                    withAnimation(.smooth(duration: 0.15)) {
                        state = .image(ImageInfo(uiImage: response.image, realDimensions: response.image.size))
//                    }
                }
                if generateIMeta {
                    let blurhash: String? = response.image.blurHash(numberOfComponents: (4, 3))
                    let pixelSize = await CGSize(width: response.image.size.width * UIScreen.main.scale, height: response.image.size.height * UIScreen.main.scale)
                    let iMetaInfo = iMetaInfo(size: pixelSize, blurHash: blurhash)
                    Task { @MainActor in
                        sendNotification(.iMetaInfoForUrl, (url.absoluteString, iMetaInfo))
                    }
                }
            }
        }
        catch {
            Task { @MainActor in
                
                // Paused is not error
                if case .paused(_) = state { return }
                
                state = .error(error.localizedDescription)
            }
        }
    }
    
    public func pause(_ atProgress: Int = 0) {
        task?.cancel()
        Task { @MainActor in
            if case .loading(_) = state { // only if loading, could be already finished so don't reset to paused
                state = .paused(atProgress)
            }
        }
    }
    
    deinit {
        task?.cancel()
        task = nil
    }
}

enum MediaViewState: Equatable {
    case initial
    case lowDataMode
    case loading(Int) // Progress percentage
    case paused(Int)
    case httpBlocked
    case dontAutoLoad
    case image(ImageInfo)
    case gif(GifInfo) // TODO: handle  if !dim.isScreenshot
    case error(String) // error message
}

struct ImageInfo: Equatable {
    let id = UUID()
    let uiImage: UIImage
    let realDimensions: CGSize
}

struct GifInfo: Equatable {
    let id = UUID()
    let gifData: Data
    let realDimensions: CGSize
}

// Need context
// Are we in screenshot? to disable gif animation
// Full width needed here or not?


#Preview("PNG") {
    VStack {
        let galleryItem = GalleryItem(url: URL(string: "https://m.primal.net/Pbct.jpg")!)
        
        MediaContentView(
            galleryItem: galleryItem,
            availableWidth: 360
        )
        .border(Color.blue)
        .frame(width: 360, height: 360)
        
        
        MediaContentView(
            galleryItem: galleryItem,
            availableWidth: 360,
            contentMode: .fill
        )
        .border(Color.blue)
        .frame(width: 360, height: 160)
        
        Button("Clear cache") {
            ImageProcessing.shared.content.cache.removeAll()
        }
    }
}

#Preview("GM") {
    VStack {
        let galleryItem = GalleryItem(url: URL(string: "https://m.primal.net/Pbct.jpg")!, dimensions: CGSize(
            width: 1024,
            height: 768
        ))
        
        MediaContentView(
            galleryItem: galleryItem,
            availableWidth: 381,
            contentMode: .fit
        )
        .border(Color.blue)
        //             .clipped()
        .frame(width: 381, height: 600)
        //             .clipped()
        
        
        .overlay(alignment: .bottom) {
            Text("360x660")
                .foregroundColor(.white)
                .background(Color.blue)
        }
        
        
        
        
        Button("Clear cache") {
            ImageProcessing.shared.content.cache.removeAll()
        }
    }
}


#Preview("Good night") {
    VStack {
        let galleryItem = GalleryItem(url: URL(string: "https://i.nostr.build/3ZAA1HdMP7doa8nv.jpg")!, dimensions: CGSize(
            width: 1776,
            height: 1184
        ))
        
        MediaContentView(
            galleryItem: galleryItem,
            availableWidth: 360,
            contentMode: .fit
        )
        .border(Color.blue)
        //             .clipped()
        .frame(width: 360, height: 5000)
        //             .clipped()
        
        
        .overlay(alignment: .bottom) {
            Text("360x5000")
                .foregroundColor(.white)
                .background(Color.blue)
        }
        
        
        
        
        Button("Clear cache") {
            ImageProcessing.shared.content.cache.removeAll()
        }
    }
}


#Preview("GIF") {
    VStack {
        let galleryItem = GalleryItem(url: URL(string: "https://media.tenor.com/8ZwnfDCNcUoAAAAC/doctor-dr.gif")!)
        
        MediaContentView(
            galleryItem: galleryItem,
            availableWidth: 360,
            contentMode: .fill
        )
        .border(Color.blue)
        .frame(width: 360, height: 360)
        
        MediaContentView(
            galleryItem: galleryItem,
            availableWidth: 360
        )
        .border(Color.blue)
        .frame(width: 360, height: 360)
        
        Button("Clear cache") {
            ImageProcessing.shared.content.cache.removeAll()
        }
    }
}
