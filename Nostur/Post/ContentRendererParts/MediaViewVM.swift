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
    private static let progressStep = 5
    private static let minimumProgressUpdateInterval: TimeInterval = 0.1

    @Published var state: MediaViewState = .initial
    private var task: ImageTask?
    
    @discardableResult
    public func load(
        _ url: URL,
        forceLoad: Bool = false,
        loadAnyway: Bool = false,
        generateIMeta: Bool = false,
        usePFPpipeline: Bool = false,
        targetSize: CGSize? = nil,
        cropToTarget: Bool = false,
        preserveCurrentImage: Bool = false,
        blossomAuthorPubkey: String? = nil,
        encryptedFile: FileMessageInfo? = nil,
        encryptedFileCacheId: String? = nil,
        reportFailure: Bool = true
    ) async -> Bool {
        // Start discovery alongside the normal retry. If the original server is back,
        // it still wins without waiting for the author's kind-10063 response.
        let blossomCandidatesTask: Task<[URL], Never>? = if encryptedFile == nil, let blossomAuthorPubkey,
                                                               BlossomMediaRecovery.hash(from: url) != nil {
            Task {
                await BlossomMediaRecovery.candidateURLs(
                    originalURL: url,
                    authorPubkey: blossomAuthorPubkey
                )
            }
        }
        else {
            nil
        }

        if SettingsStore.shared.lowDataMode && !forceLoad {
            Task { @MainActor in
                state = .lowDataMode
            }
            return false
        }
        
        if url.absoluteString.prefix(7) == "http://" && !forceLoad {
            Task { @MainActor in
                state = .httpBlocked
            }
            return false
        }

        let loadURL: URL
        if let encryptedFile {
            do {
                loadURL = try await DMFileCache.shared.previewURL(
                    fileInfo: encryptedFile,
                    conversationId: encryptedFileCacheId ?? encryptedFile.originalHash ?? url.absoluteString
                )
            }
            catch {
                if reportFailure {
                    await MainActor.run {
                        state = .error("Failed to decrypt image")
                    }
                }
                return false
            }
        }
        else {
            loadURL = url
        }
        
        let request = makeImageRequest(
            loadURL,
            label: "MediaViewVM.load",
            overrideLowDataMode: forceLoad,
            targetSize: targetSize,
            contentMode: cropToTarget ? .aspectFill : .aspectFit,
            crop: cropToTarget
        )
        self.task = if usePFPpipeline {
            ImageProcessing.shared.pfp.imageTask(with: pfpImageRequestFor(loadURL))
        }
        else if loadAnyway {
            ImageProcessing.shared.contentLoadAnyway.imageTask(with: request)
        }
        else {
            ImageProcessing.shared.content.imageTask(with: request)
        }
        
        guard let task = self.task else {
            guard !preserveCurrentImage else { return false }
            if reportFailure {
                await MainActor.run {
                    state = .error("Failed to load image")
                }
            }
            return false
        }
        
        let initialProgress = await MainActor.run {
            if preserveCurrentImage {
                return 0
            }

            // resume from paused?
            let progress = if case .paused(let progress) = state { progress }
            else { 0 } // resume from 0
            state = .loading(progress)
            return progress
        }

        if !preserveCurrentImage {
            var lastPublishedProgress = initialProgress
            var lastProgressUpdateTime = -Double.infinity

            for await progress in task.progress {
                guard progress.fraction.isFinite else { continue }
                let fraction = min(max(progress.fraction, 0), 1)
                let rawProgress = Int(ceil(fraction * 100))
                let steppedProgress = min(
                    95,
                    (rawProgress / Self.progressStep) * Self.progressStep
                )

                guard steppedProgress >= lastPublishedProgress + Self.progressStep
                else { continue }

                let now = ProcessInfo.processInfo.systemUptime
                guard now - lastProgressUpdateTime >= Self.minimumProgressUpdateInterval
                else { continue }

                let didPublish = await MainActor.run {
                    guard case .loading(let currentProgress) = state,
                          steppedProgress > currentProgress
                    else { return false }

                    state = .loading(steppedProgress)
                    return true
                }

                if didPublish {
                    lastPublishedProgress = steppedProgress
                    lastProgressUpdateTime = now
                }
            }
        }
    
        do {
            let response = try await task.response
            // WebP: After the resize processor runs, Nuke reports type as PNG, not WebP.
            // Detect WebP by URL extension instead, then fetch raw bytes from the data cache.
            if loadURL.pathExtension.lowercased() == "webp" {
                let request = ImageRequest(url: loadURL)
                let cacheKey = ImageProcessing.shared.content.cache.makeDataCacheKey(for: request)
                let rawData = ImageProcessing.shared.content.configuration.dataCache?.cachedData(for: cacheKey)
                    ?? response.container.data
                if let rawData,
                   isAnimatedWebPData(rawData),
                   ProfileImageSafety.isSafeAnimatedImage(rawData, policy: .post) {
                    Task { @MainActor in
                        state = .gif(GifInfo(gifData: rawData, realDimensions: response.container.image.size))
                        if generateIMeta {
                            let blurhash: String? = response.container.image.blurHash(numberOfComponents: (4, 3))
                            let pixelSize = CGSize(width: response.container.image.size.width * UIScreen.main.scale, height: response.container.image.size.height * UIScreen.main.scale)
                            let iMetaInfo = iMetaInfo(size: pixelSize, blurHash: blurhash)
                            Task { @MainActor in
                                sendNotification(.iMetaInfoForUrl, (url.absoluteString, iMetaInfo))
                            }
                        }
                    }
                    return true
                }
            }
            if response.container.type == .gif,
               let gifData = response.container.data,
               ProfileImageSafety.isSafeAnimatedImage(gifData, policy: .post) {
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
            return true
        }
        catch {
            guard !preserveCurrentImage else { return false }

            if let blossomCandidatesTask {
                for candidateURL in await blossomCandidatesTask.value {
                    if await load(
                        candidateURL,
                        forceLoad: true,
                        loadAnyway: loadAnyway,
                        generateIMeta: generateIMeta,
                        usePFPpipeline: usePFPpipeline,
                        targetSize: targetSize,
                        cropToTarget: cropToTarget,
                        preserveCurrentImage: false,
                        reportFailure: false
                    ) {
                        return true
                    }
                }
            }

            guard reportFailure else { return false }

            let finalFailureState: MediaViewState
            if Self.isDownloadSizeLimitError(error) {
                finalFailureState = .imageTooLarge
            }
            else if let blossomCandidatesTask {
                let mirrorCount = Self.mirrorCount(in: await blossomCandidatesTask.value)
                if mirrorCount == 0 {
                    finalFailureState = .error("Failed to load image (no mirrors found)")
                }
                else {
                    let mirrorLabel = mirrorCount == 1 ? "mirror" : "mirrors"
                    finalFailureState = .error("Failed to load image (tried \(mirrorCount) more \(mirrorLabel))")
                }
            }
            else {
                finalFailureState = .error("Failed to load image")
            }

            await MainActor.run {
                // Paused is not error
                if case .paused(_) = state { return }
                state = finalFailureState
            }
            return false
        }
    }

    private static func mirrorCount(in candidateURLs: [URL]) -> Int {
        Set(candidateURLs.map { url in
            var components = URLComponents()
            components.scheme = url.scheme
            components.host = url.host
            components.port = url.port
            return components.string ?? url.host ?? url.absoluteString
        }).count
    }

    private static func isDownloadSizeLimitError(_ error: Swift.Error) -> Bool {
        if error is LimitedDataLoader.Error {
            return true
        }
        if let pipelineError = error as? ImagePipeline.Error,
           pipelineError.dataLoadingError is LimitedDataLoader.Error {
            return true
        }
        return false
    }
    
    @MainActor
    public func pause(_ atProgress: Int = 0) {
        task?.cancel()
        if case .loading(_) = state { // only if loading, could be already finished so don't reset to paused
            state = .paused(atProgress)
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
    case imageTooLarge
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
