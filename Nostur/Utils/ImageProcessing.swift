//
//  ImageProcessing.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/03/2023.
//

import SwiftUI
import Nuke

class ImageProcessing {
    // Disk cache size
    static let PFP_SIZE_MB = IS_CATALYST ? 3000 : 1500
    static let CONTENT_SIZE_MB = IS_CATALYST ? 1000 : 500
    static let BANNER_SIZE_MB = IS_CATALYST ? 500 : 250
    
    static public let shared = ImageProcessing()
    
    var pfp: ImagePipeline
    var banner: ImagePipeline
    var content: ImagePipeline
    var communities: ImagePipeline
    var badges: ImagePipeline
    var video: ImagePipeline
    
    var contentPrefetcher: ImagePrefetcher
    var pfpPrefetcher: ImagePrefetcher
    
    private init() {
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
        
        pfp = ImagePipeline {
//            $0.isUsingPrepareForDisplay = true
//            $0.isProgressiveDecodingEnabled = true
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())

            let dataCache = try! DataCache(name: "com.nostur.image.pfp")
            dataCache.sizeLimit = 1_048_576 * Self.PFP_SIZE_MB

            $0.imageCache = ImageCache(costLimit: 104_857_600)
            $0.dataCache = dataCache
//            $0.dataCachePolicy = .storeEncodedImages
            $0.dataCachePolicy = .automatic
        }
        
        banner = ImagePipeline {
//            $0.isUsingPrepareForDisplay = true
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.image.banner")
            dataCache.sizeLimit = 1_048_576 * Self.BANNER_SIZE_MB
            
            $0.imageCache = ImageCache(costLimit: 10_485_760)
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
        }
        
        content = ImagePipeline {
//            $0.isUsingPrepareForDisplay = true
            $0.isProgressiveDecodingEnabled = false
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.image.content")
            dataCache.sizeLimit = 1_048_576 * Self.CONTENT_SIZE_MB
            
            $0.imageCache = ImageCache(costLimit: 104_857_600, countLimit: 1000)
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
        }
        
        communities = ImagePipeline {
//            $0.isUsingPrepareForDisplay = true
            $0.isProgressiveDecodingEnabled = true
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.image.communities")
            dataCache.sizeLimit = 524_288_000
            
            $0.imageCache = ImageCache(costLimit: 104_857_600, countLimit: 1000)
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
        }
        
        badges = ImagePipeline {
            $0.isProgressiveDecodingEnabled = true
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.image.badges")
            dataCache.sizeLimit = 104_857_600
            
            $0.imageCache = ImageCache(costLimit: 26_214_400, countLimit: 200)  // 100 MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
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
    
}


// Force processing to 50x50 so we always get the same from cache and not redownload, do scaling down to 20x20 (or other) in SwiftUI if needed (.resizable())
func pfpImageRequestFor(_ pictureUrl: URL) -> ImageRequest {
#if DEBUG
    L.og.debug("pfpImageRequestFor: \(pictureUrl.absoluteString) -[LOG]-")
#endif
    //    thumbOptions.createThumbnailFromImageAlways = true
    //    thumbOptions.shouldCacheImmediately = true
    let options: ImageRequest.Options = SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : []

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


// Use this function to make sure the image request is same in SingleImageViewer, SmoothList prefetch and SmoothList cancel prefetch.
// else Nuke will prefetch wrong request
func makeImageRequest(_ url: URL, label: String = "", overrideLowDataMode: Bool = false, size: CGFloat? = nil) -> ImageRequest {
#if DEBUG
    L.og.debug("ImageRequest: \(url.absoluteString), \(label) -[LOG]-")
#endif
    return ImageRequest(url: url,
                 processors: [
                    .resize(size: CGSize(width: size ?? ScreenSpace.shared.screenSize.width, height: size ?? ScreenSpace.shared.screenSize.height), contentMode: .aspectFit, upscale: false)
                 ],
                options: (!overrideLowDataMode && SettingsStore.shared.lowDataMode) ? [.returnCacheDataDontLoad] : [],
                userInfo: [.scaleKey: UIScreen.main.scale]
    )
}
