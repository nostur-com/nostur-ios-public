//
//  ImageProcessing.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/03/2023.
//

import Foundation
import Nuke


class ImageProcessing {
    static public var shared = ImageProcessing()
    
    var pfp:ImagePipeline
    var banner:ImagePipeline
    var content:ImagePipeline
    var badges:ImagePipeline
    var video:ImagePipeline
    var linkPreview:ImagePipeline
    
    init() {
        //        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
        
        linkPreview = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.image.linkpreview")
            dataCache.sizeLimit = 1024 * 1024 * 25
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 25)  // 25 MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeEncodedImages
        }
        
        pfp = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.image.pfp")
            dataCache.sizeLimit = 1024 * 1024 * 150
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 150)  // 150 MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeAll
        }
        
        banner = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.image.banner")
            dataCache.sizeLimit = 1024 * 1024 * 50
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 50)  // 50 MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeOriginalData
        }
        
        content = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.image.content")
            dataCache.sizeLimit = 1024 * 1024 * 100
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 50, countLimit: 100)  // 100 MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeOriginalData
        }
        
        badges = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.image.badges")
            dataCache.sizeLimit = 1024 * 1024 * 100
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 50, countLimit: 200)  // 100 MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeAll
        }
        
        video = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())
            
            let dataCache = try! DataCache(name: "com.nostur.video.content")
            dataCache.sizeLimit = 1024 * 1024 * 100
            
            $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 50, countLimit: 100)  // 100 MB
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeOriginalData
        }
        
    }
    
}
