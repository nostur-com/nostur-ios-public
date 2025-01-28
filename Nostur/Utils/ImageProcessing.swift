//
//  ImageProcessing.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/03/2023.
//

import Foundation
import Nuke

class ImageProcessing {
    // Disk cache size
    static let PFP_SIZE_MB = IS_CATALYST ? 3000 : 1500
    static let CONTENT_SIZE_MB = IS_CATALYST ? 1000 : 500
    static let BANNER_SIZE_MB = IS_CATALYST ? 500 : 250
    
    static public var shared = ImageProcessing()
    
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
            dataCache.sizeLimit = 1024 * 1024 * Self.PFP_SIZE_MB

            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 100)
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
            dataCache.sizeLimit = 1024 * 1024 * Self.BANNER_SIZE_MB
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 10)
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
            dataCache.sizeLimit = 1024 * 1024 * Self.CONTENT_SIZE_MB
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 100, countLimit: 1000)
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
            dataCache.sizeLimit = 1024 * 1024 * 500
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 100, countLimit: 1000)
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
            dataCache.sizeLimit = 1024 * 1024 * 100
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 25, countLimit: 200)  // 100 MB
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
            dataCache.sizeLimit = 1024 * 1024 * 200
            
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
