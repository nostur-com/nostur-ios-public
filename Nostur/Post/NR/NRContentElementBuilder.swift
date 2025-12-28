//
//  NRContentElementBuilder.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import Foundation
import SwiftUI
import NostrEssentials

typealias FastTag = (String, String, String?, String?, String?, String?, String?, String?, String?, String?)

class NRContentElementBuilder {
    
    private init() { }
    static let shared = NRContentElementBuilder()
    let context = bg()
    
    func buildElements(input: String, fastTags: [FastTag], event: Event? = nil, primaryColor: Color? = nil, previewImages: [PostedImageMeta] = [], previewVideos: [PostedVideoMeta] = [], isPreviewContext: Bool = false) -> ([ContentElement], [URL], [GalleryItem]) {
        if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            L.og.info("☠️☠️☠️☠️ renderElements on MAIN thread....")
        }
        
        let range = NSRange(location: 0, length: input.utf16.count)
        
        var result: [ContentElement] = []
        var linkPreviewUrls: [URL] = []
        var galleryItems: [GalleryItem] = []
        var lastMatchEnd = 0
        
        (isPreviewContext ? Self.previewRegex : Self.regex).enumerateMatches(in: input, options: [], range: range) { match, _, _ in
            if let match = match {
                let matchRange = match.range
                let nonMatchRange = NSRange(location: lastMatchEnd, length: matchRange.location - lastMatchEnd)
                let nonMatch = (input as NSString).substring(with: nonMatchRange)
                let matchString = (input as NSString).substring(with: matchRange)
                
                if !nonMatch.isEmpty {
                    result.append(ContentElement.text(NRTextParser.shared.parseText(fastTags: fastTags, event: event, text:nonMatch, primaryColor: primaryColor)))
                }
                
                if !matchString.matchingStrings(regex: Self.imageUrlPattern).isEmpty {
                    if let url = URL(string: matchString) {
                        let iMeta: iMetaInfo? = findImeta(fastTags, url: matchString)
                        let galleryItem = GalleryItem(url: url, pubkey: event?.pubkey, eventId: event?.id, dimensions: iMeta?.size, blurhash: iMeta?.blurHash)
                        result.append(ContentElement.image(galleryItem))
                        galleryItems.append(galleryItem)
                    }
                    else {
                        result.append(ContentElement.text(NRTextParser.shared.parseText(fastTags: fastTags, event: event, text:matchString, primaryColor: primaryColor)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.videoUrlPattern).isEmpty {
                    if let url = URL(string: matchString) {
                        let iMeta: iMetaInfo? = findImeta(fastTags, url: matchString)
                        result.append(ContentElement.video(MediaContent(url: url, dimensions: iMeta?.size, blurHash: iMeta?.blurHash)))
                    }
                    else {
                        result.append(ContentElement.text(NRTextParser.shared.parseText(fastTags: fastTags, event: event, text:matchString, primaryColor: primaryColor)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.otherUrlsPattern).isEmpty {
                    if let url = URL(string: matchString) {
                        result.append(ContentElement.linkPreview(url))
                        linkPreviewUrls.append(url)
                    }
                    else {
                        result.append(ContentElement.text(NRTextParser.shared.parseText(fastTags: fastTags, event: event, text:matchString, primaryColor: primaryColor)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.npubPattern).isEmpty {
                    let match = matchString.replacingOccurrences(of: "\n", with: "")
                                            .replacingOccurrences(of: "@", with: "")
                    result.append(ContentElement.npub1(match))
                }
                else if !matchString.matchingStrings(regex: isPreviewContext ? Self.previewNotePattern : Self.notePattern).isEmpty {
                    let match = matchString.replacingOccurrences(of: "nostr:", with: "")
                                            .replacingOccurrences(of: "@", with: "")
                    result.append(ContentElement.note1(match))
                }
                else if !matchString.matchingStrings(regex: Self.previewImagePlaceholder).isEmpty {
                    let m = matchString.matchingStrings(regex: Self.previewImagePlaceholder)
                    if let index = Int(m[0][1]) {
                        if let p = previewImages[safe: index] {
                            result.append(ContentElement.postPreviewImage(p))
                        }
                    }
                }
                else if !matchString.matchingStrings(regex: Self.previewVideoPlaceholder).isEmpty {
                    let m = matchString.matchingStrings(regex: Self.previewVideoPlaceholder)
                    if let index = Int(m[0][1]) {
                        if let p = previewVideos[safe: index] {
                            result.append(ContentElement.postPreviewVideo(p))
                        }
                    }
                }
                else if !matchString.matchingStrings(regex: Self.codePattern).isEmpty {
                    let m = matchString.matchingStrings(regex: Self.codePattern)
                    if let code = m[0][safe: 1] {
                        result.append(ContentElement.code(code))
                    }
                }
                else if !matchString.matchingStrings(regex: isPreviewContext ? Self.previewNeventPattern : Self.neventPattern).isEmpty {
                    do {
                        let match = matchString.replacingOccurrences(of: "nostr:", with: "")
                                                .replacingOccurrences(of: "@", with: "")
                        let identifier = try ShareableIdentifier(match)
                        result.append(ContentElement.nevent1(identifier))
                        
                    }
                    catch {
                        L.og.notice("problem decoding nevent in event.id: \(event?.id ?? "?") - \(matchString)")
                        result.append(ContentElement.text(NRTextParser.shared.parseText(fastTags: fastTags, event: event, text:matchString, primaryColor: primaryColor)))
                    }
                }
                else if !matchString.matchingStrings(regex: isPreviewContext ? Self.previewNaddrPattern : Self.naddrPattern).isEmpty {
                    do {
                        let match = matchString.replacingOccurrences(of: "nostr:", with: "")
                                                .replacingOccurrences(of: "@", with: "")
                        let identifier = try ShareableIdentifier(match)
                        result.append(ContentElement.naddr1(identifier))
                        
                    }
                    catch {
                        L.og.notice("problem decoding naddr in event.id: \(event?.id ?? "?") - \(matchString)")
                        result.append(ContentElement.text(NRTextParser.shared.parseText(fastTags: fastTags, event: event, text:matchString, primaryColor: primaryColor)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.nprofilePattern).isEmpty {
                    do {
                        let match = matchString.replacingOccurrences(of: "\n", with: "")
                                                .replacingOccurrences(of: "@", with: "")
                        let identifier = try ShareableIdentifier(match)
                        result.append(ContentElement.nprofile1(identifier))
                    }
                    catch {
                        L.og.notice("problem decoding nevent in profile.pubkey: \(event?.id ?? "?") - \(matchString)")
                        result.append(ContentElement.text(NRTextParser.shared.parseText(fastTags: fastTags, event: event, text:matchString, primaryColor: primaryColor)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.lightningInvoicePattern).isEmpty {
                    result.append(ContentElement.lnbc(matchString))
                }
                else if !matchString.matchingStrings(regex: Self.cashuTokenPattern).isEmpty {
                    result.append(ContentElement.cashu(matchString))
                }
                else {
                    result.append(ContentElement.text(NRTextParser.shared.parseText(fastTags: fastTags, event: event, text:matchString, primaryColor: primaryColor)))
                }
                
                lastMatchEnd = matchRange.location + matchRange.length
            }
        }
        
        let nonMatchRange = NSRange(location: lastMatchEnd, length: input.utf16.count - lastMatchEnd)
        let nonMatch = (input as NSString).substring(with: nonMatchRange)
        
        if !nonMatch.isEmpty {
            result.append(ContentElement.text(NRTextParser.shared.parseText(fastTags: fastTags, event: event, text:nonMatch, primaryColor: primaryColor)))
        }
        
        // for kind:20 image urls are not in text but only as imeta:
        if galleryItems.isEmpty {
            galleryItems = fastTags
                .compactMap { galleryItemFromIMetaFastTag($0, pubkey: event?.pubkey, eventId: event?.id) }
        }
        
        return (result, linkPreviewUrls, galleryItems)
    }
    
    // Same as buildElements(), but with a image/video/other url matching removed
    // and uses .parseMD instead of .parseText
    func buildArticleElements(_ event: Event) -> ([ContentElement], [URL], [GalleryItem]) {
        if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            L.og.info("☠️☠️☠️☠️ buildArticleElements on MAIN thread....")
        }
        let input = event.noteTextPrepared
        
        let range = NSRange(location: 0, length: input.utf16.count)
        
        var result: [ContentElement] = []
        var lastMatchEnd = 0
        Self.articleRegex.enumerateMatches(in: input, options: [], range: range) { match, _, _ in
            if let match = match {
                let matchRange = match.range
                let nonMatchRange = NSRange(location: lastMatchEnd, length: matchRange.location - lastMatchEnd)
                let nonMatch = (input as NSString).substring(with: nonMatchRange)
                let matchString = (input as NSString).substring(with: matchRange)
                
                result.append(ContentElement.md(NRTextParser.shared.parseMD(event, text:nonMatch)))
                
                if !matchString.matchingStrings(regex: Self.npubPattern).isEmpty {
                    let match = matchString.replacingOccurrences(of: "\n", with: "")
                                            .replacingOccurrences(of: "@", with: "")
                    result.append(ContentElement.npub1(match))
                }
                else if !matchString.matchingStrings(regex: Self.notePattern).isEmpty {
                    let match = matchString.replacingOccurrences(of: "nostr:", with: "")
                                            .replacingOccurrences(of: "@", with: "")
                    result.append(ContentElement.note1(match))
                }
                else if !matchString.matchingStrings(regex: Self.neventPattern).isEmpty {
                    do {
                        let match = matchString.replacingOccurrences(of: "nostr:", with: "")
                                                .replacingOccurrences(of: "@", with: "")
                        let identifier = try ShareableIdentifier(match)
                        result.append(ContentElement.nevent1(identifier))
                        
                    }
                    catch {
                        L.og.notice("problem decoding nevent in event.id: \(event.id) - \(matchString)")
                        result.append(ContentElement.md(NRTextParser.shared.parseMD(event, text:matchString)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.naddrPattern).isEmpty {
                    do {
                        let match = matchString.replacingOccurrences(of: "nostr:", with: "")
                                                .replacingOccurrences(of: "@", with: "")
                        let identifier = try ShareableIdentifier(match)
                        result.append(ContentElement.naddr1(identifier))
                        
                    }
                    catch {
                        L.og.notice("problem decoding naddr in event.id: \(event.id) - \(matchString)")
                        result.append(ContentElement.md(NRTextParser.shared.parseMD(event, text:matchString)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.nprofilePattern).isEmpty {
                    do {
                        let match = matchString.replacingOccurrences(of: "\n", with: "")
                                                .replacingOccurrences(of: "@", with: "")
                        let identifier = try ShareableIdentifier(match)
                        result.append(ContentElement.nprofile1(identifier))
                    }
                    catch {
                        L.og.notice("problem decoding nevent in profile.pubkey: \(event.id) - \(matchString)")
                        result.append(ContentElement.md(NRTextParser.shared.parseMD(event, text:matchString)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.lightningInvoicePattern).isEmpty {
                    result.append(ContentElement.lnbc(matchString))
                }
                else if !matchString.matchingStrings(regex: Self.cashuTokenPattern).isEmpty {
                    result.append(ContentElement.cashu(matchString))
                }
                else if !matchString.matchingStrings(regex: Self.codePattern).isEmpty {
                    let m = matchString.matchingStrings(regex: Self.codePattern)
                    if let code = m[0][safe: 1] {
                        result.append(ContentElement.code(code))
                    }
                }
                else {
                    result.append(ContentElement.md(NRTextParser.shared.parseMD(event, text:matchString)))
                }
                
                lastMatchEnd = matchRange.location + matchRange.length
            }
        }
        
        let nonMatchRange = NSRange(location: lastMatchEnd, length: input.utf16.count - lastMatchEnd)
        let nonMatch = (input as NSString).substring(with: nonMatchRange)
        
        result.append(ContentElement.md(NRTextParser.shared.parseMD(event, text:nonMatch)))
        return (result, [], [])
    }
    
    
    static let imageUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:png#?|jpe?g#?|heic#?|gif#?|webp#?|avif#?)(\??\S+){0,1}\b"###
    static let previewImagePlaceholder = ###"--@!\^@(\d+)@\^!@--"###
    static let previewVideoPlaceholder = ###"-V-@!\^@(\d+)@\^!@-V-"###
    static let videoUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:mp4#?|mov#?|m3u8#?|m4v#?|mp3#?|m4a#?)(\??\S+){0,1}\b"###
    static let lightningInvoicePattern = ###"(?i)lnbc\S+"###
    static let cashuTokenPattern = ###"(?:cashu:)?(cashu[AB][A-Za-z0-9_-]*)"###
    
    // In preview, don't render without "nostr:" to discourage wrong creation
    static let previewNotePattern = ###"(nostr:|@)(note1[023456789acdefghjklmnpqrstuvwxyz]{58})"###
    static let previewNeventPattern = ###"(nostr:|@)(nevent1[023456789acdefghjklmnpqrstuvwxyz]+)\b"###
    static let previewNaddrPattern = ###"(nostr:|@)(naddr1[023456789acdefghjklmnpqrstuvwxyz]+)\b"###
    
    // Try to render everything, including wrong
    static let notePattern = ###"(nostr:|@?)(?<!/)(note1[023456789acdefghjklmnpqrstuvwxyz]{58})"###
    static let neventPattern = ###"(nostr:|@?)(?<!/)(nevent1[023456789acdefghjklmnpqrstuvwxyz]+)\b"###
    static let naddrPattern = ###"(nostr:|@?)(?<!/)(naddr1[023456789acdefghjklmnpqrstuvwxyz]+)\b"###
    static let codePattern = ###"```([\s\S]*?)```"###
    
    // These become cards so
    // no nostr: here, because we do that in TextParser (inline)
    // only if there is a newline before, else we also do that in TextParser (inline)
    static let nprofilePattern = ###"(?:\n@?)(?<!/)(nprofile1[023456789acdefghjklmnpqrstuvwxyz]+)\b"###
    static let npubPattern = ###"(?:\n@?)(?<!/)(npub1[023456789acdefghjklmnpqrstuvwxyz]{58})"### // no nostr: here, because we do that in TextParser
    
    static let otherUrlsPattern = ###"(?i)(https\:\/\/)[a-zA-Z0-9\-\.]+(?:\.[a-zA-Z]{2,999}+)+([\/\?\=\&\#\%\+\.]\@?[\S]+)*\/?[^\s\)\.,]"###
    
    // For kind 1 or similar text notes
    static let pattern = "\(previewImagePlaceholder)|\(previewVideoPlaceholder)|\(imageUrlPattern)|\(lightningInvoicePattern)|\(cashuTokenPattern)|\(npubPattern)|\(notePattern)|\(nprofilePattern)|\(neventPattern)|\(naddrPattern)|\(videoUrlPattern)|\(otherUrlsPattern)|\(codePattern)"
    static let regex = try! NSRegularExpression(pattern: pattern)
    
    static let previewPattern = "\(previewImagePlaceholder)|\(previewVideoPlaceholder)|\(imageUrlPattern)|\(lightningInvoicePattern)|\(cashuTokenPattern)|\(npubPattern)|\(previewNotePattern)|\(nprofilePattern)|\(previewNeventPattern)|\(previewNaddrPattern)|\(videoUrlPattern)|\(otherUrlsPattern)|\(codePattern)"
    static let previewRegex = try! NSRegularExpression(pattern: previewPattern)
    
    // For long form articles (kind 30023), no image urls, video urls, other urls, as these are handled by markdown
    static let articlePattern = "\(previewImagePlaceholder)|\(previewVideoPlaceholder)|\(lightningInvoicePattern)|\(cashuTokenPattern)|\(npubPattern)|\(notePattern)|\(nprofilePattern)|\(neventPattern)|\(naddrPattern)|\(codePattern)"
    static let articleRegex = try! NSRegularExpression(pattern: articlePattern)
}

public typealias Ptag = String

// NOTE: When adding types, update ContentRenderer AND DMContentRenderer
enum ContentElement: Hashable, Identifiable {
    var id: Self { self }
    case code(String) // dont parse anything here
    case text(AttributedStringWithPs) // text notes
    case md(MarkdownContentWithPs) // long form articles
    case npub1(String)
    case note1(String)
    case noteHex(String)
    case lnbc(String)
    case cashu(String)
    case link(String, URL)
    case image(GalleryItem)
    case video(MediaContent)
    case linkPreview(URL)
    case postPreviewImage(PostedImageMeta)
    case postPreviewVideo(PostedVideoMeta)
    case nevent1(ShareableIdentifier)
    case nprofile1(ShareableIdentifier)
    case nrPost(NRPost) // embedded post, already processed for rendering
    case naddr1(ShareableIdentifier)
}

import MarkdownUI

// For text notes
struct MediaContent: Hashable {
    let id = UUID()
    func hash(into hasher: inout Hasher) {
        return hasher.combine(id)
    }
    var url: URL
    var dimensions: CGSize?
    var blurHash: String?
    
    var aspect: CGFloat {
        if let dimensions {
            return dimensions.height / dimensions.width
        } else {
            return 1
        }
    }
}

// For text notes
struct AttributedStringWithPs: Hashable {
    let id = UUID()
    func hash(into hasher: inout Hasher) {
        return hasher.combine(id)
    }
    
    var input: String
    var nxOutput: AttributedString? // Render faster with Text() but doesn't support hashtag icons
    var output: NSAttributedString? // For selectable text, but slow because .makeUITextView only use when needed (hashtags or selectable text)
    var pTags: [Ptag]
    var missingPs: Set<String> = [] 
    weak var event: Event?
}

// For long form articles
struct MarkdownContentWithPs: Hashable {
    let id = UUID()
    func hash(into hasher: inout Hasher) {
        return hasher.combine(id)
    }
    
    var input: String
    var output: MarkdownContent
    var pTags: [Ptag]
    weak var event: Event?
}

// Helper function to extract all values from a FastTag
private func getTagValues(_ tag: FastTag) -> [String?] {
    return [tag.1, tag.2, tag.3, tag.4, tag.5, tag.6, tag.7, tag.8, tag.9]
}

struct iMetaInfo {
    var size: CGSize?
    var blurHash: String?
    
    var aspect: CGFloat? {
        if let size {
            return size.width / size.height
        } else {
            return nil
        }
    }
    
    var duration: Int?
    var waveform: [Int]?
}

func findImeta(_ fastTags: [FastTag], url:String) -> iMetaInfo? {
    // DIP-01
    // Find any tag that is 'imeta' and has matching 'url'
    let imetaTag: FastTag? = fastTags.first(where: { tag in
        guard tag.0 == "imeta" else { return false }
        
        // Check each value in the tag for a URL match
        return getTagValues(tag).contains { value in
            guard let value = value else { return false }
            let parts = value.split(separator: " ", maxSplits: 1)
            return parts.count == 2 && String(parts[0]) == "url" && String(parts[1]) == url
        }
    })
    
    
    if let imetaTag {
        return iMetaFromFastTag(imetaTag)
    }
    
    // NIP-54
    if let imeta = findImetaFromUrl(url) { return imeta }
    
    return nil
}

func iMetaFromFastTag(_ fastTag: FastTag) -> iMetaInfo? {
    // Check each value in found imeta tag for 'dim'
    var size: CGSize?
    for value in getTagValues(fastTag) {
        guard let value = value else { continue }
        let parts = value.split(separator: " ", maxSplits: 1)
        if parts.count == 2 && String(parts[0]) == "dim" {
            let dim = parts[1].split(separator: "x", maxSplits: 1)
            if dim.count == 2, let width = Int(dim[0]), let height = Int(dim[1]) {
                size = CGSize(width: width, height: height)
            }
        }
    }
    
    var blurHash: String?
    for value in getTagValues(fastTag) {
        guard let value = value else { continue }
        let parts = value.split(separator: " ", maxSplits: 1)
        if parts.count == 2 && String(parts[0]) == "blurhash" {
            blurHash = String(parts[1])
        }
    }
    
    if blurHash != nil || size != nil {
        return iMetaInfo(size: size, blurHash: blurHash)
    }
    
    return nil
}


// NIP-54
func findImetaFromUrl(_ url: String) -> iMetaInfo? {
    let splits = url.split(separator: "#", maxSplits: 1)
    guard let metaParams = splits.last else { return nil }
    let metaSplits = metaParams.split(separator: "&")
//    var dim:CGSize?
//    var m:String? // Disabled for now
//    var x:String? // Disabled for now
    for meta in metaSplits {
        if String(meta).prefix(4) == "dim=" {
            let dims = String(String(meta).dropFirst(4)).split(separator: "x").compactMap { Double($0) }
            guard dims.count == 2 else { continue }
            return iMetaInfo(size: CGSize(width: dims[0], height: dims[1]))
        }
        // Disabled for now:
//        else if String(meta).prefix(2) == "x=" {
//            x = String(String(meta).dropFirst(2))
//        }
//        else if String(meta).prefix(2) == "m=" {
//            m = String(meta).dropFirst(2).removingPercentEncoding
//        }
    }
    return nil
//    return ...
}

func imageUrlFromIMetaFastTag(_ tag: FastTag) -> URL? {
    guard tag.0 == "imeta" else { return nil }
    
    for value in getTagValues(tag) {
        guard let value = value else { continue }
        let property = value.components(separatedBy: " ")
        if property.count >= 2 && property[0] == "url" {
            return URL(string: property[1])
        }
    }
    
    return nil
}


func galleryItemFromIMetaFastTag(_ tag: FastTag, pubkey: String? = nil, eventId: String? = nil) -> GalleryItem? {
    guard let url = imageUrlFromIMetaFastTag(tag) else { return nil }
    let iMeta: iMetaInfo? = iMetaFromFastTag(tag)
    return GalleryItem(url: url, pubkey: pubkey, eventId: eventId, dimensions: iMeta?.size, blurhash: iMeta?.blurHash)
}
