import Foundation
import UIKit

class NRContentElementBuilder {
    
    static let shared = NRContentElementBuilder()
    let context = DataProvider.shared().bg
    
    func buildElements(_ event:Event) -> ([ContentElement], [URL]) {
        if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            L.og.info("☠️☠️☠️☠️ renderElements on MAIN thread....")
        }
        
        let input = event.noteTextPrepared
        
        let range = NSRange(location: 0, length: input.utf16.count)
        
        var result: [ContentElement] = []
        var linkPreviewUrls: [URL] = []
        var lastMatchEnd = 0
        
        Self.regex.enumerateMatches(in: input, options: [], range: range) { match, _, _ in
            if let match = match {
                let matchRange = match.range
                let nonMatchRange = NSRange(location: lastMatchEnd, length: matchRange.location - lastMatchEnd)
                let nonMatch = (input as NSString).substring(with: nonMatchRange)
                let matchString = (input as NSString).substring(with: matchRange)
                
                result.append(ContentElement.text(NRTextParser.shared.parseText(event, text:nonMatch)))
                
                if !matchString.matchingStrings(regex: Self.imageUrlPattern).isEmpty {
                    if let url = URL(string: matchString) {
                        result.append(ContentElement.image(url))
                    }
                    else {
                        result.append(ContentElement.text(NRTextParser.shared.parseText(event, text:matchString)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.videoUrlPattern).isEmpty {
                    if let url = URL(string: matchString) {
                        result.append(ContentElement.video(url))
                    }
                    else {
                        result.append(ContentElement.text(NRTextParser.shared.parseText(event, text:matchString)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.otherUrlsPattern).isEmpty {
                    if let url = URL(string: matchString) {
                        result.append(ContentElement.linkPreview(url))
                        linkPreviewUrls.append(url)
                    }
                    else {
                        result.append(ContentElement.text(NRTextParser.shared.parseText(event, text:matchString)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.npubPattern).isEmpty {
                    let match = matchString.replacingOccurrences(of: "\n", with: "")
                                            .replacingOccurrences(of: "@", with: "")
                    result.append(ContentElement.npub1(match))
                }
                else if !matchString.matchingStrings(regex: Self.notePattern).isEmpty {
                    let match = matchString.replacingOccurrences(of: "nostr:", with: "")
                                            .replacingOccurrences(of: "@", with: "")
                    result.append(ContentElement.note1(match))
                }
                else if !matchString.matchingStrings(regex: Self.previewImagePlaceholder).isEmpty {
                    let m = matchString.matchingStrings(regex: Self.previewImagePlaceholder)
                    if let index = Int(m[0][1]) {
                        if let p = event.previewImages[safe: index] {
                            result.append(ContentElement.postPreviewImage(p))
                        }
                    }
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
                        result.append(ContentElement.text(NRTextParser.shared.parseText(event, text:matchString)))
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
                        result.append(ContentElement.text(NRTextParser.shared.parseText(event, text:matchString)))
                    }
                }
                else if !matchString.matchingStrings(regex: Self.lightningInvoicePattern).isEmpty {
                    result.append(ContentElement.lnbc(matchString))
                }
                else {
                    result.append(ContentElement.text(NRTextParser.shared.parseText(event, text:matchString)))
                }
                
                lastMatchEnd = matchRange.location + matchRange.length
            }
        }
        
        let nonMatchRange = NSRange(location: lastMatchEnd, length: input.utf16.count - lastMatchEnd)
        let nonMatch = (input as NSString).substring(with: nonMatchRange)
        
        result.append(ContentElement.text(NRTextParser.shared.parseText(event, text:nonMatch)))
        return (result, linkPreviewUrls)
    }
    
    
    static let imageUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:png|jpe?g|gif|webp)(\?\S+){0,1}\b"###
    static let previewImagePlaceholder = ###"--@!\^@(\d+)@\^!@--"###
    static let videoUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:mp4|mov)(\?\S+){0,1}\b"###
    static let lightningInvoicePattern = ###"(?i)lnbc\S+"###
    static let notePattern = ###"(nostr:|@?)(note1[023456789acdefghjklmnpqrstuvwxyz]{58})"###
    static let neventPattern = ###"(nostr:@?)(nevent1[023456789acdefghjklmnpqrstuvwxyz]+)\b"###
    
    // These become cards so
    // no nostr: here, because we do that in TextParser (inline)
    // only if there is a newline before, else we also do that in TextParser (inline)
    static let nprofilePattern = ###"(?:\n@?)(nprofile1[023456789acdefghjklmnpqrstuvwxyz]+)\b"###
    static let npubPattern = ###"(?:\n@?)(npub1[023456789acdefghjklmnpqrstuvwxyz]{58})"### // no nostr: here, because we do that in TextParser
    
    static let otherUrlsPattern = ###"(?i)(https\:\/\/)[a-zA-Z0-9\-\.]+(?:\.[a-zA-Z]{2,999}+)+([\/\?\=\&\#\%\+\.]\@?[\S]+)*\/?[^\s\)]"### 
    static let pattern = "\(previewImagePlaceholder)|\(imageUrlPattern)|\(lightningInvoicePattern)|\(npubPattern)|\(notePattern)|\(nprofilePattern)|\(neventPattern)|\(videoUrlPattern)|\(otherUrlsPattern)"
    static let regex = try! NSRegularExpression(pattern: pattern)
}

public typealias Ptag = String

enum ContentElement: Hashable, Identifiable {
    var id:Self { self }
    case text(AttributedStringWithPs)
    case npub1(String)
    case note1(String)
    case noteHex(String)
    case lnbc(String)
    case link(String, URL)
    case image(URL)
    case video(URL)
    case linkPreview(URL)
    case postPreviewImage(UIImage)
    case nevent1(ShareableIdentifier)
    case nprofile1(ShareableIdentifier)
}

struct AttributedStringWithPs: Hashable {
    let id = UUID()
    func hash(into hasher: inout Hasher) {
        return hasher.combine(id)
    }
    
    var input:String
    var output:AttributedString
    var pTags:[Ptag]
    var event:Event
}
