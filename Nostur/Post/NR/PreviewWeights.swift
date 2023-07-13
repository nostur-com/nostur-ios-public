//
//  PreviewWeights.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/05/2023.
//

import Foundation

class PreviewWeights {
    var posts = 0.0
    var videos = 0.0
    var pictures = 0.0
    var linkPreviews = 0.0
    var other = 0.0
    var text = 0.0
    
    var weight:Double {
        var weight  = (posts * 0.8)
            weight += (videos * 0.8)
            weight += (pictures * 0.8)
            weight += (linkPreviews * 0.3)
            weight += (other * 0.8)
            weight += (text * 0.0000001)
        
        return weight
    }
    
    var moreItems:Bool {
        (morePosts + moreVideos + morePictures + moreLinkPreviews + moreOther) > 0
    }
    
    var moreItemsCount:Int {
        (morePosts + moreVideos + morePictures + moreLinkPreviews + moreOther)
    }
    
    var morePosts = 0
    var moreVideos = 0
    var morePictures = 0
    var moreLinkPreviews = 0
    var moreOther = 0
    var moreText = 0
}

func filteredForPreview(_ contentElements:[ContentElement]) -> ([ContentElement], PreviewWeights) {
    let w = PreviewWeights()
    
    let previewElements = contentElements.filter { element in
        switch element {
        case .note1:
            w.posts += 1;
            guard w.weight < 1 else {
                w.morePosts += 1
                return false
            }
            return true
        case .noteHex:
            w.posts += 1;
            guard w.weight < 1 else {
                w.morePosts += 1
                return false
            }
            return true
        case .lnbc:
            w.other += 1;
            guard w.weight < 1 else {
                w.moreOther += 1
                return false
            }
            return true
        case .image:
            w.pictures += 1;
            guard w.weight < 1 else {
                w.morePictures += 1
                return false
            }
            return true
        case .video:
            w.videos += 1;
            guard w.weight < 1 else {
                w.moreVideos += 1
                return false
            }
            return true
        case .linkPreview:
            w.linkPreviews += 1;
            guard w.weight < 1 else {
                w.moreLinkPreviews += 1
                return false
            }
            return true
        case .postPreviewImage:
            return true
        case .nevent1:
            w.posts += 1;
            guard w.weight < 1 else {
                w.morePosts += 1
                return false
            }
            return true
        case .nprofile1:
            w.other += 1;
            guard w.weight < 1 else {
                w.moreOther += 1
                return false
            }
            return true
        case .text:
            w.text += 1;
            guard w.weight < 1 else {
                w.moreText += 1
                return false
            }
            return true
        default:
            w.other += 1;
            guard w.weight < 1 else {
                w.moreOther += 1
                return false
            }
            return true
        }
    }
    
    return (previewElements, w)
}
