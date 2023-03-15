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
    
    var pipeline:ImagePipeline
    var bannerPipeline:ImagePipeline
    var postContentPipeline:ImagePipeline
    
    init() {
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)

        pipeline = ImagePipeline {
                    $0.dataLoader = DataLoader(configuration: {
                        // Disable disk caching built into URLSession
                        let conf = DataLoader.defaultConfiguration
                        conf.urlCache = nil
                        return conf
                    }())

                    $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 100)  // 100 MB
                    $0.dataCache = try! DataCache(name: "com.nostur.2140.picture")
                    $0.dataCachePolicy = .storeAll
                }
        
        bannerPipeline = ImagePipeline {
                    $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 100)  // 100 MB
                    $0.dataCache = try! DataCache(name: "com.nostur.image.banner")
                    $0.dataCachePolicy = .storeEncodedImages
                }
        
        postContentPipeline = ImagePipeline {
                    $0.imageCache = ImageCache(costLimit: 1024 * 1024 * 100, countLimit: 100)  // 100 MB
                    $0.dataCache = try! DataCache(name: "com.nostur.2140.postcontent")
                    $0.dataCachePolicy = .storeAll
                }
        
    }
    
}
