//
//  ImageProcessing.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/03/2023.
//

import SwiftUI
import Nuke

/// Prevents profile-picture responses from growing without bound in Nuke's
/// in-memory download buffer. The Content-Length check is only an optimization;
/// `LimitedDataLoader` also counts the bytes actually received.
final class LimitedDataLoader: DataLoading, @unchecked Sendable {
    enum Error: Swift.Error, LocalizedError {
        case responseTooLarge(limit: Int)

        var errorDescription: String? {
            switch self {
            case .responseTooLarge(let limit):
                return "Image response exceeds the \(limit)-byte limit"
            }
        }
    }

    private let underlying: any DataLoading
    private let byteLimit: Int

    init(underlying: any DataLoading, byteLimit: Int) {
        self.underlying = underlying
        self.byteLimit = byteLimit
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping (Data, URLResponse) -> Void,
        completion: @escaping (Swift.Error?) -> Void
    ) -> any Cancellable {
        let state = LimitedDataLoadState(byteLimit: byteLimit, completion: completion)
        let cancellable = underlying.loadData(with: request) { data, response in
            if state.accept(dataCount: data.count, response: response) {
                didReceiveData(data, response)
            }
            else {
                state.cancelUnderlying()
            }
        } completion: { error in
            state.finish(error)
        }
        state.setCancellable(cancellable)
        return LimitedDataLoadCancellable(state: state)
    }
}

private final class LimitedDataLoadState: @unchecked Sendable {
    private let lock = NSLock()
    private let byteLimit: Int
    private let completion: (Swift.Error?) -> Void
    private var receivedByteCount = 0
    private var isFinished = false
    private var cancellable: (any Cancellable)?

    init(byteLimit: Int, completion: @escaping (Swift.Error?) -> Void) {
        self.byteLimit = byteLimit
        self.completion = completion
    }

    func accept(dataCount: Int, response: URLResponse) -> Bool {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return false
        }

        let declaredLength = response.expectedContentLength
        guard declaredLength <= 0 || declaredLength <= Int64(byteLimit) else {
            isFinished = true
            lock.unlock()
            completion(LimitedDataLoader.Error.responseTooLarge(limit: byteLimit))
            return false
        }

        let (newCount, overflow) = receivedByteCount.addingReportingOverflow(dataCount)
        guard !overflow, newCount <= byteLimit else {
            isFinished = true
            lock.unlock()
            completion(LimitedDataLoader.Error.responseTooLarge(limit: byteLimit))
            return false
        }
        receivedByteCount = newCount
        lock.unlock()
        return true
    }

    func finish(_ error: Swift.Error?) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        lock.unlock()
        completion(error)
    }

    func setCancellable(_ cancellable: any Cancellable) {
        lock.lock()
        self.cancellable = cancellable
        let shouldCancel = isFinished
        lock.unlock()
        if shouldCancel {
            cancellable.cancel()
        }
    }

    func cancelUnderlying() {
        lock.lock()
        let cancellable = cancellable
        lock.unlock()
        cancellable?.cancel()
    }

    func cancel() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let cancellable = cancellable
        lock.unlock()
        cancellable?.cancel()
        completion(CancellationError())
    }
}

private final class LimitedDataLoadCancellable: Cancellable, @unchecked Sendable {
    private let state: LimitedDataLoadState

    init(state: LimitedDataLoadState) {
        self.state = state
    }

    func cancel() {
        state.cancel()
    }
}

private struct LimitedImageDecoder: ImageDecoding {
    enum Error: Swift.Error {
        case unsafeImageDimensions
    }

    let underlying: any ImageDecoding
    let policy: ProfileImageSafety.Policy

    var isAsynchronous: Bool { underlying.isAsynchronous }

    func decode(_ data: Data) throws -> ImageContainer {
        guard ProfileImageSafety.isSafeAnimatedImage(data, policy: policy) else {
            throw Error.unsafeImageDimensions
        }
        return try underlying.decode(data)
    }

    // Do not progressively decode untrusted image data before complete
    // dimensions and frame counts can be validated.
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        nil
    }
}

class ImageProcessing {
    static let PFP_DOWNLOAD_SIZE_LIMIT = 15 * 1_048_576
    static let BANNER_DOWNLOAD_SIZE_LIMIT = 25 * 1_048_576
    static let CONTENT_DOWNLOAD_SIZE_LIMIT = 50 * 1_048_576
    static let CONTENT_LOAD_ANYWAY_SIZE_LIMIT = 250 * 1_048_576
    static let COMMUNITY_DOWNLOAD_SIZE_LIMIT = 10 * 1_048_576
    static let BADGE_DOWNLOAD_SIZE_LIMIT = 10 * 1_048_576
    static let EMOJI_DOWNLOAD_SIZE_LIMIT = 2 * 1_048_576

    // Disk cache size
    static let PFP_SIZE_MB = IS_CATALYST ? 3000 : 1500
    static let CONTENT_SIZE_MB = IS_CATALYST ? 1000 : 500
    static let BANNER_SIZE_MB = IS_CATALYST ? 500 : 250
    
    static public let shared = ImageProcessing()
    
    var pfp: ImagePipeline
    var banner: ImagePipeline
    var content: ImagePipeline
    var contentLoadAnyway: ImagePipeline
    var communities: ImagePipeline
    var badges: ImagePipeline
    var emoji: ImagePipeline
    var video: ImagePipeline
    
    var contentPrefetcher: ImagePrefetcher
    var pfpPrefetcher: ImagePrefetcher
    
    private init() {
        var sharedConfiguration = ImagePipeline.Configuration.withDataCache
        sharedConfiguration.dataLoader = Self.makeLimitedDataLoader(
            byteLimit: Self.CONTENT_DOWNLOAD_SIZE_LIMIT
        )
        sharedConfiguration.makeImageDecoder = Self.makeLimitedImageDecoder(policy: .post)
        ImagePipeline.shared = ImagePipeline(configuration: sharedConfiguration)
        
        pfp = ImagePipeline {
//            $0.isUsingPrepareForDisplay = true
//            $0.isProgressiveDecodingEnabled = true
            $0.dataLoader = Self.makeLimitedDataLoader(byteLimit: Self.PFP_DOWNLOAD_SIZE_LIMIT)
            $0.makeImageDecoder = Self.makeLimitedImageDecoder(policy: .profilePicture)

            let dataCache = try! DataCache(name: "com.nostur.image.pfp")
            dataCache.sizeLimit = 1_048_576 * Self.PFP_SIZE_MB

            $0.imageCache = ImageCache(costLimit: 104_857_600)
            $0.dataCache = dataCache
//            $0.dataCachePolicy = .storeEncodedImages
            $0.dataCachePolicy = .automatic
        }
        
        banner = ImagePipeline {
//            $0.isUsingPrepareForDisplay = true
            $0.dataLoader = Self.makeLimitedDataLoader(byteLimit: Self.BANNER_DOWNLOAD_SIZE_LIMIT)
            $0.makeImageDecoder = Self.makeLimitedImageDecoder(policy: .banner)
            
            let dataCache = try! DataCache(name: "com.nostur.image.banner")
            dataCache.sizeLimit = 1_048_576 * Self.BANNER_SIZE_MB
            
            $0.imageCache = ImageCache(costLimit: 10_485_760)
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
        }
        
        content = ImagePipeline {
//            $0.isUsingPrepareForDisplay = true
            $0.isProgressiveDecodingEnabled = false
            $0.dataLoader = Self.makeLimitedDataLoader(byteLimit: Self.CONTENT_DOWNLOAD_SIZE_LIMIT)
            $0.makeImageDecoder = Self.makeLimitedImageDecoder(policy: .post)
            
            let dataCache = try! DataCache(name: "com.nostur.image.content")
            dataCache.sizeLimit = 1_048_576 * Self.CONTENT_SIZE_MB
            
            $0.imageCache = ImageCache(costLimit: 104_857_600, countLimit: 1000)
            $0.dataCache = dataCache
            // storeOriginalData ensures raw bytes are always preserved in the data cache,
            // even when processors (e.g. resize) run. This is required so animated WebP
            // detection can read the original bytes via the data cache.
            $0.dataCachePolicy = .storeOriginalData
        }

        // User-initiated override for post media that exceeds the normal 50 MB
        // limit. Keep a higher hard ceiling so a malicious URL still can't grow
        // Nuke's in-memory buffer without bound.
        contentLoadAnyway = ImagePipeline {
            $0.isProgressiveDecodingEnabled = false
            $0.dataLoader = Self.makeLimitedDataLoader(
                byteLimit: Self.CONTENT_LOAD_ANYWAY_SIZE_LIMIT
            )
            $0.makeImageDecoder = Self.makeLimitedImageDecoder(policy: .post)
            $0.imageCache = ImageCache(costLimit: 104_857_600, countLimit: 1000)
            let dataCache = try! DataCache(name: "com.nostur.image.content")
            dataCache.sizeLimit = 1_048_576 * Self.CONTENT_SIZE_MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeOriginalData
        }
        
        communities = ImagePipeline {
//            $0.isUsingPrepareForDisplay = true
            $0.isProgressiveDecodingEnabled = true
            $0.dataLoader = Self.makeLimitedDataLoader(byteLimit: Self.COMMUNITY_DOWNLOAD_SIZE_LIMIT)
            $0.makeImageDecoder = Self.makeLimitedImageDecoder(policy: .badge)
            
            let dataCache = try! DataCache(name: "com.nostur.image.communities")
            dataCache.sizeLimit = 524_288_000
            
            $0.imageCache = ImageCache(costLimit: 104_857_600, countLimit: 1000)
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
        }
        
        badges = ImagePipeline {
            $0.isProgressiveDecodingEnabled = true
            $0.dataLoader = Self.makeLimitedDataLoader(byteLimit: Self.BADGE_DOWNLOAD_SIZE_LIMIT)
            $0.makeImageDecoder = Self.makeLimitedImageDecoder(policy: .badge)
            
            let dataCache = try! DataCache(name: "com.nostur.image.badges")
            dataCache.sizeLimit = 104_857_600
            
            $0.imageCache = ImageCache(costLimit: 26_214_400, countLimit: 200)  // 100 MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
        }

        emoji = ImagePipeline {
            $0.dataLoader = Self.makeLimitedDataLoader(byteLimit: Self.EMOJI_DOWNLOAD_SIZE_LIMIT)
            $0.makeImageDecoder = Self.makeLimitedImageDecoder(policy: .emoji)
            $0.imageCache = ImageCache(costLimit: 10_485_760, countLimit: 500)
            let dataCache = try! DataCache(name: "com.nostur.image.emoji")
            dataCache.sizeLimit = 20_971_520
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeOriginalData
        }
        
        video = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.video.content")
            dataCache.sizeLimit = 209_715_200
            
//            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 50, countLimit: 100)  // 100 MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeOriginalData
        }
     
        contentPrefetcher = ImagePrefetcher(pipeline: content)
        contentPrefetcher.priority = .normal
        
        pfpPrefetcher = ImagePrefetcher(pipeline: pfp)
        pfpPrefetcher.priority = .high
    }

    private static func makeLimitedDataLoader(byteLimit: Int) -> LimitedDataLoader {
        let configuration = DataLoader.defaultConfiguration
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return LimitedDataLoader(
            underlying: DataLoader(configuration: configuration),
            byteLimit: byteLimit
        )
    }

    private static func makeLimitedImageDecoder(
        policy: ProfileImageSafety.Policy
    ) -> @Sendable (ImageDecodingContext) -> (any ImageDecoding)? {
        { context in
            guard context.isCompleted,
                  let decoder = ImageDecoderRegistry.shared.decoder(for: context) else {
                return nil
            }
            return LimitedImageDecoder(underlying: decoder, policy: policy)
        }
    }
}


// Force processing to 50x50 so we always get the same from cache and not redownload, do scaling down to 20x20 (or other) in SwiftUI if needed (.resizable())
func pfpImageRequestFor(_ pictureUrl: URL, overrideLowDataMode: Bool = false) -> ImageRequest {
#if DEBUG
    L.og.debug("pfpImageRequestFor: \(pictureUrl.absoluteString) -[LOG]-")
#endif
    //    thumbOptions.createThumbnailFromImageAlways = true
    //    thumbOptions.shouldCacheImmediately = true
    let options: ImageRequest.Options = (SettingsStore.shared.lowDataMode || overrideLowDataMode) ? [.returnCacheDataDontLoad] : []

    if !SettingsStore.shared.animatedPFPenabled || pictureUrl.absoluteString.suffix(4) != ".gif" {
        return ImageRequest(url: pictureUrl,
//                            userInfo: [.thumbnailKey: thumbOptions],
                            processors: [
                                .resize(size: CGSize(width: 50, height: 50), unit: .points, contentMode: .aspectFill,
                                        crop: true,
                                        upscale: true)
                            ],
                            options: options,
                            userInfo: [.scaleKey: UIScreen.main.scale]
//                            userInfo: [.scaleKey: 1, .thumbnailKey: thumbOptions]
//                            userInfo: [.scaleKey: UIScreen.main.scale, .thumbnailKey: thumbOptions]
        )
    }
    return ImageRequest(url: pictureUrl)
}


/// Uses coarse width buckets so small layout differences inside a feed row
/// still resolve to the exact same processed-image cache key as prefetching.
func feedImageRequestTargetSize(
    for availableWidth: CGFloat,
    availableHeight: CGFloat
) -> CGSize {
    let widthStep: CGFloat = 200
    let width = ceil(max(1, availableWidth) / widthStep) * widthStep
    let height = min(
        DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
        max(1, availableHeight)
    )
    return CGSize(width: width, height: height)
}

/// Grid cells are square and approximately half the feed media width. Feed
/// widths are bucketed in 200-point steps, so halving the bucket produces a
/// stable 100-point grid bucket shared by rendering and prefetching.
func gridImageRequestTargetSize(for feedTargetSize: CGSize) -> CGSize {
    let side = max(100, feedTargetSize.width / 2)
    return CGSize(width: side, height: side)
}

// Use this function to make sure the image request is same in SingleImageViewer, SmoothList prefetch and SmoothList cancel prefetch.
// else Nuke will prefetch wrong request
func makeImageRequest(
    _ url: URL,
    label: String = "",
    overrideLowDataMode: Bool = false,
    targetSize: CGSize? = nil,
    contentMode: ImageProcessingOptions.ContentMode = .aspectFit,
    crop: Bool = false
) -> ImageRequest {
#if DEBUG
    L.og.debug("ImageRequest: \(url.absoluteString), \(label) -[LOG]-")
#endif
    let options: ImageRequest.Options = (!overrideLowDataMode && SettingsStore.shared.lowDataMode) ? [.returnCacheDataDontLoad] : []
    let targetSize = targetSize ?? ScreenSpace.shared.screenSize
    return ImageRequest(url: url,
                 processors: [
                    .resize(
                        size: CGSize(
                            width: max(1, targetSize.width),
                            height: max(1, targetSize.height)
                        ),
                        contentMode: contentMode,
                        crop: crop,
                        upscale: false
                    )
                 ],
                options: options,
                userInfo: [.scaleKey: UIScreen.main.scale]
    )
}
