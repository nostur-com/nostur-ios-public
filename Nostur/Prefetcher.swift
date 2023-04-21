////
////  Prefetcher.swift
////  Nostur
////
////  Created by Fabian Lachman on 20/04/2023.
////
//
//import Foundation
//
//class Prefetcher {
//    static let shared = Prefetcher()
//    
//    var width:CGFloat = 600
//    
//    var queue:[MarkdownElement] =  []
//    
//    func prefetch(_ vPost:VPost) {
//        // prefetch images
//        
//        let mediaElements = vPost.renderedElements.filter {
//            if case .image = $0 {
//                    return true
//            }
//            if case .video = $0 {
//                    return true
//            }
//            if case .linkPreview = $0 {
//                    return true
//            }
//            return false
//        }
//        
//
//        
//        // prefetch link previews
//        
//        // estimate height maybe?
//    }
//    
//    func removeFromQueue(_ vPost:VPost) {
//        
//    }
//}
