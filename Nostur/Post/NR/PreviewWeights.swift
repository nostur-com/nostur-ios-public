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
    
    var weight: Double {
        var weight  = (posts * 0.8)
            weight += (videos * 0.8)
            weight += (pictures * 0.8)
            weight += (linkPreviews * 0.3)
            weight += (other * 0.8)
            weight += (Double(characters) * 0.0029)
        
        return weight
    }
    
    var moreItems: Bool {
        (morePosts + moreVideos + morePictures + moreLinkPreviews + moreOther) > 0
    }
    
    var moreItemsCount: Int {
        (morePosts + moreVideos + morePictures + moreLinkPreviews + moreOther)
    }
    
    var morePosts = 0
    var moreVideos = 0
    var morePictures = 0
    var moreLinkPreviews = 0
    var moreOther = 0
    var moreText = 0
    
    var characters: Int = 0
    
    var sizeEstimate: RowSizeEstimate = .small
    
    public var textOnly: Bool {
        return (posts + videos + pictures + linkPreviews + other) == 0
    }
    
    public var hasLargeItem: Bool {
        return moreItems || (videos + pictures + other) > 0 // removed "posts", because too many times small posts makes it become .large when it should be .medium
    }
}

let PREVIEW_WEIGHT_LIMIT = 2

enum RowSizeEstimate: CGFloat {
    case small = 30
    case medium = 100
    case large = 240 // 450 
}

func filteredForPreview(_ contentElements:[ContentElement]) -> ([ContentElement], PreviewWeights) {
    let w = PreviewWeights()
    var isFirst = true
    
    let previewElements = contentElements.filter { element in
        switch element {
        case .note1, .nrPost:
            w.posts += 1;
            guard isFirst || w.weight < 2 else {
                w.morePosts += 1
                return false
            }
            isFirst = false
            return true
        case .noteHex:
            w.posts += 1;
            guard isFirst || w.weight < 2 else {
                w.morePosts += 1
                return false
            }
            isFirst = false
            return true
        case .lnbc, .cashu:
            w.other += 1;
            guard isFirst || w.weight < 2 else {
                w.moreOther += 1
                return false
            }
            isFirst = false
            return true
        case .image:
            w.pictures += 1;
            guard isFirst || w.weight < 2 else {
                w.morePictures += 1
                return false
            }
            isFirst = false
            return true
        case .video:
            w.videos += 1;
            guard isFirst || w.weight < 2 else {
                w.moreVideos += 1
                return false
            }
            isFirst = false
            return true
        case .linkPreview:
            w.linkPreviews += 1;
            guard isFirst || w.weight < 2 else {
                w.moreLinkPreviews += 1
                return false
            }
            isFirst = false
            return true
        case .postPreviewImage:
            return true
        case .nevent1:
            w.posts += 1;
            guard isFirst || w.weight < 2 else {
                w.morePosts += 1
                return false
            }
            isFirst = false
            return true
        case .nprofile1, .npub1:
            w.other += 1;
            guard isFirst || w.weight < 2 else {
                w.moreOther += 1
                return false
            }
            isFirst = false
            return true
        case .text(let attributedStringWithPs):
            if let output = attributedStringWithPs.output {
                w.characters += output.length
            }
            else if let nxOutput = attributedStringWithPs.nxOutput {
                w.characters += nxOutput.characters.count
            }
            w.characters += (attributedStringWithPs.input.utf8.lazy.count { $0 == 10 } * 40) // count newlines 40 characters
            w.text += 1;
            guard isFirst || w.weight < 2 else {
                w.moreText += 1
                return false
            }
            isFirst = false
            return true
        default:
            w.other += 1;
            guard isFirst || w.weight < 2 else {
                w.moreOther += 1
                return false
            }
            isFirst = false
            return true
        }
    }
    
    // Text only?
    if w.textOnly {
        if w.characters < 200 {
            w.sizeEstimate = .small
        }
        else if w.characters < 500 || w.linkPreviews > 0 || w.morePosts > 0 {
            w.sizeEstimate = .medium
        }
        else {
            w.sizeEstimate = .large
        }
    }
    else if w.hasLargeItem {
        w.sizeEstimate = .large
    }
    
    return (previewElements, w)
}
