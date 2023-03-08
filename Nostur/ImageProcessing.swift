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
            $0.dataCache = try? DataCache(name: "com.nostur.2140.picture")
            $0.dataCachePolicy = .storeEncodedImages
            $0.imageCache = ImageCache(costLimit: 500)
        }
        
        bannerPipeline = ImagePipeline {
            $0.dataCache = try? DataCache(name: "com.nostur.2140.banner")
            $0.dataCachePolicy = .storeEncodedImages
        }
        
        postContentPipeline = ImagePipeline {
            $0.dataCache = try? DataCache(name: "com.nostur.2140.postcontent")
            $0.dataCachePolicy = .storeAll
            $0.imageCache = ImageCache(countLimit: 100)
        }
    }
    
}
