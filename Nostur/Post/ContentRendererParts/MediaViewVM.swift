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
    
    
    public func load(_ url: URL, expectedImageSize: CGSize, contentMode: ContentMode = .fit,
                                upscale: Bool = false, forceLoad: Bool = false) async {
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
        

        let imageRequest = makeImageRequest(url,
                                            width: expectedImageSize.width,
                                            height: expectedImageSize.height,
                                            contentMode: contentMode == .fit ? .aspectFit : .aspectFill,
                                            upscale: upscale,
                                            label: "MediaViewVM.load",
                                            overrideLowDataMode: forceLoad
        )
        let task = ImageProcessing.shared.content.imageTask(with: imageRequest)
        
        for await progress in task.progress {
            Task { @MainActor in
                state = .loading(Int(ceil(progress.fraction * 100)))
            }
        }
        
        do {
            let response = try await task.response
            if response.container.type == .gif, let gifData = response.container.data {
                Task { @MainActor in
                    state = .gif(GifInfo(gifData: gifData, realDimensions: response.container.image.size))
                }
            }
            else {
                Task { @MainActor in
                    state = .image(ImageInfo(uiImage: response.image, realDimensions: response.image.size))
                }
            }
        }
        catch {
            Task { @MainActor in
                state = .error(error.localizedDescription)
            }
        }
    }
}

enum MediaViewState {
    case initial
    case lowDataMode
    case loading(Int) // Progress percentage
    case httpBlocked
    case dontAutoLoad
    case blurhashLoading
    case image(ImageInfo)
    case gif(GifInfo)
    case error(String) // error message
    case cancelled
}

struct ImageInfo {
    let uiImage: UIImage
    let realDimensions: CGSize
}

struct GifInfo {
    let gifData: Data
    let realDimensions: CGSize
}

// Need context
// Are we in screenshot? to disable gif animation
// Full width needed here or not?


#Preview("PNG") {
         VStack {
             let mediaContent = MediaContent(url: URL(string: "https://m.primal.net/Pbct.jpg")!)
             
             MediaContentView(
                 media: mediaContent
             )
             .border(Color.blue)
             .frame(width: 360, height: 360)
             
             
             MediaContentView(
                 media: mediaContent,
                 contentMode: .fill
             )
             .border(Color.blue)
             .frame(width: 360, height: 160)
             
             Button("Clear cache") {
                 ImageProcessing.shared.content.cache.removeAll()
             }
         }
         .environmentObject(Themes.default)
         .environmentObject(DIMENSIONS.shared)
}

#Preview("GM") {
         VStack {
             let mediaContent = MediaContent(
                url: URL(string: "https://m.primal.net/PbPR.jpg")!,
                dimensions: CGSize(
                    width: 1024,
                    height: 768
                )
             )
            
             
             
             MediaContentView(
                 media: mediaContent,
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
         .environmentObject(Themes.default)
         .environmentObject(DIMENSIONS.shared)
}


#Preview("Good night") {
         VStack {
             let mediaContent = MediaContent(
                url: URL(string: "https://i.nostr.build/3ZAA1HdMP7doa8nv.jpg")!,
                dimensions: CGSize(
                    width: 1776,
                    height: 1184
                )
             )
             
             MediaContentView(
                 media: mediaContent,
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
         .environmentObject(Themes.default)
         .environmentObject(DIMENSIONS.shared)
}


#Preview("GIF") {
    VStack {
        let mediaContent = MediaContent(url: URL(string: "https://media.tenor.com/8ZwnfDCNcUoAAAAC/doctor-dr.gif")!)
        
        MediaContentView(
            media: mediaContent,
            contentMode: .fill
        )
        .border(Color.blue)
        .frame(width: 360, height: 360)
        
        MediaContentView(
            media: mediaContent
        )
        .border(Color.blue)
        .frame(width: 360, height: 360)
        
        Button("Clear cache") {
            ImageProcessing.shared.content.cache.removeAll()
        }
    }
    .environmentObject(Themes.default)
    .environmentObject(DIMENSIONS.shared)
}
