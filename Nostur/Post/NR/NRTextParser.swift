//
//  NRTextBuilder.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import Foundation
import MarkdownUI
import UIKit
// Renders links for the text parts of post contents (in TEXT)
// Handles profile links
// Tag links
// Other links
// DOES NOT handle note links or image links, because those are embeds, handled by ContentRenderer
class NRTextParser { // TEXT things
    static let shared = NRTextParser()
    private let context = bg()

    func parseText(_ event:Event, text: String, availableWidth: CGFloat? = nil) -> AttributedStringWithPs {
        let availableWidth = availableWidth ??  DIMENSIONS.shared.availableNoteRowImageWidth()

        // Remove image links
        // because they get rendered as embeds in PostDetail.
        // and NoteRow shows them in ImageViewer
        var newText = removeImageLinks(event: event, text: text)

        // Handle #hashtags
        newText = Self.replaceHashtagsWithMarkdownLinks(in: newText)
        // Handle naddr1...
        newText = Self.replaceNaddrWithMarkdownLinks(in: newText)
        
        // NIP-08, handle #[0] #[1] etc
        let textWithPs = parseTagIndexedMentions(event: event, text: newText)

        // NIP-28 handle nostr:npub1, nostr:nprofile ...
        var newerTextWithPs = parseUserMentions(event: event, text: textWithPs.text)
        if newerTextWithPs.text.suffix(1) == "\n" {
            newerTextWithPs.text = String(newerTextWithPs.text.dropLast(1))
        }

        do {
            let finalText = try AttributedString(markdown: newerTextWithPs.text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            
            let mutableAttributedString = NSMutableAttributedString(finalText)
            let attributes:[NSAttributedString.Key: NSObject] = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor(Themes.default.theme.primary)
            ]
            
            mutableAttributedString.addAttributes(
                attributes,
                range: NSRange(location: 0, length: mutableAttributedString.length)
            )
            
            let height = mutableAttributedString.boundingRect(
                with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
            
            let a = AttributedStringWithPs(input:text, output: NSAttributedString(attributedString: mutableAttributedString), previewOutput: finalText, pTags: textWithPs.pTags + newerTextWithPs.pTags, event:event, height: height)
            
            return a
        }
        catch {
            let finalText = AttributedString(newerTextWithPs.text)
            
            let mutableAttributedString = NSMutableAttributedString(finalText)
            let attributes:[NSAttributedString.Key: NSObject] = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor(Themes.default.theme.primary)
            ]
            
            mutableAttributedString.addAttributes(
                attributes,
                range: NSRange(location: 0, length: mutableAttributedString.length)
            )
            
            let height = mutableAttributedString.boundingRect(
                with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
            
            L.og.error("NRTextParser: \(error)")
            let a = AttributedStringWithPs(input:text, output: NSAttributedString(attributedString: mutableAttributedString), previewOutput: finalText, pTags: textWithPs.pTags + newerTextWithPs.pTags, event:event, height: height)
            return a
        }
    }
    
    func parseMD(_ event:Event, text: String) -> MarkdownContentWithPs {
//        L.og.debug(text)

        // Remove image links
        // because they get rendered as embeds in PostDetail.
        // and NoteRow shows them in ImageViewer
//        let newText = removeImageLinks(event: event, text: text)

        // NIP-08, handle #[0] #[1] etc
        let textWithPs = parseTagIndexedMentions(event: event, text: text)

        // NIP-28 handle nostr:npub1, nostr:nprofile ...
        var newerTextWithPs = parseUserMentions(event: event, text: textWithPs.text)
        if newerTextWithPs.text.suffix(1) == "\n" {
            newerTextWithPs.text = String(newerTextWithPs.text.dropLast(1))
        }

        newerTextWithPs.text = Self.replaceHashtagsWithMarkdownLinks(in: newerTextWithPs.text)
        newerTextWithPs.text = Self.replaceNaddrWithMarkdownLinks(in: newerTextWithPs.text)
//        print(newerTextWithPs.text)
        let finalText = MarkdownContent(newerTextWithPs.text)
        
//        print(finalText)
        
        let a = MarkdownContentWithPs(input:text, output: finalText, pTags: textWithPs.pTags + newerTextWithPs.pTags, event:event)
        return a
    }

    func copyPasteText(_ event:Event, text: String) -> TextWithPs {
        // NIP-08, handle #[0] #[1] etc
        let textWithPs = parseTagIndexedMentions(event: event, text: text, plainText: true)

        // NIP-28 handle nostr:npub1, nostr:nprofile ...
        let newerTextWithPs = parseUserMentions(event: event, text: textWithPs.text, plainText: true)

        return TextWithPs(text: newerTextWithPs.text, pTags: textWithPs.pTags + newerTextWithPs.pTags)
    }

    // NIP-08 (deprecated in favor of NIP-27)
    private func parseTagIndexedMentions(event:Event, text:String, plainText:Bool = false) -> TextWithPs {
        guard !event.fastTags.isEmpty else { return TextWithPs(text: text, pTags: []) }

        if #available(iOS 16.0, *) {
            var pTags = [Ptag]()
            var newText = text
            let matches = text.matches(of: /#\[(\d+)\]/)
            for match in matches.prefix(100) { // 100 limit for sanity
                guard let tagIndex = Int(match.output.1) else { continue }
                guard tagIndex < event.fastTags.count else { continue }
                let tag = event.fastTags[tagIndex]

                if (tag.0 == "p") {
                    pTags.append(tag.1)
                    if !plainText {
                        newText = newText.replacingOccurrences(of: match.output.0, with: "[@\(contactUsername(fromPubkey: tag.1, event:event).escapeMD())](nostur:p:\(tag.1))")
                    }
                    else {
                        newText = newText.replacingOccurrences(of: match.output.0, with: "@\(contactUsername(fromPubkey: tag.1, event:event))")
                    }
                }
                else if (tag.0 == "e") {
                    if !plainText {
                        let key = try! NIP19(prefix: "note1", hexString: tag.1)
                        newText = newText.replacingOccurrences(of: match.output.0, with: "[@\(String(key.displayString).prefix(11))](nostur:e:\(tag.1))")
                    }
                    else {
                        let key = try! NIP19(prefix: "note1", hexString: tag.1)
                        newText = newText.replacingOccurrences(of: match.output.0, with: "@\(String(key.displayString).prefix(11))")
                    }
                }
            }
            return TextWithPs(text: newText, pTags: pTags)
        }
        else {
            var pTags = [Ptag]()
            var newText = text

            do {
                let regexPattern = "#\\[(\\d+)\\]"
                let regex = try NSRegularExpression(pattern: regexPattern)
                let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = regex.matches(in: text, options: [], range: nsRange)

                for match in matches.prefix(100) { // 100 limit for sanity
                    let range = match.range(at: 1)
                    guard let swiftRange = Range(range, in: text),
                          let tagIndex = Int(text[swiftRange]),
                          tagIndex < event.fastTags.count else {
                        continue
                    }
                    
                    let tag = event.fastTags[tagIndex]

                    if tag.0 == "p" {
                        pTags.append(tag.1)
                        let replacementString = !plainText ?
                            "[@\(contactUsername(fromPubkey: tag.1, event: event).escapeMD())](nostur:p:\(tag.1))" :
                            "@\(contactUsername(fromPubkey: tag.1, event: event))"
                        let entireMatchRange = match.range(at: 0)
                        if let entireSwiftRange = Range(entireMatchRange, in: newText) {
                            newText = newText.replacingOccurrences(of: String(newText[entireSwiftRange]), with: replacementString)
                        }
                    } else if tag.0 == "e" {
                        let key = try! NIP19(prefix: "note1", hexString: tag.1)
                        let replacementString = !plainText ?
                            "[@\(String(key.displayString).prefix(11))](nostur:e:\(tag.1))" :
                            "@\(String(key.displayString).prefix(11))"
                        let entireMatchRange = match.range(at: 0)
                        if let entireSwiftRange = Range(entireMatchRange, in: newText) {
                            newText = newText.replacingOccurrences(of: String(newText[entireSwiftRange]), with: replacementString)
                        }
                    }
                }
                
                return TextWithPs(text: newText, pTags: pTags)
            } catch {
                return TextWithPs(text: newText, pTags: pTags)
            }
        }
    }

    // NIP-27 handle nostr:npub or nostr:nprofile
    private func parseUserMentions(event:Event, text:String, plainText:Bool = false) -> TextWithPs {
        let pattern = "(?:nostr:)?@?npub1[023456789acdefghjklmnpqrstuvwxyz]{58}|(?:nostr:)?(nprofile1[023456789acdefghjklmnpqrstuvwxyz]+)\\b"

        var replacedString = text
        var range = text.startIndex..<text.endIndex
        var pTags = [Ptag]()

        var sanityIndex = 0
        while let matchRange = replacedString.range(of: pattern, options: .regularExpression, range: range, locale: nil) {
            if sanityIndex > 100 { break }
            sanityIndex += 1
            let match = replacedString[matchRange].replacingOccurrences(of: "@", with: "")
            var replacement = match
            
            let pub1OrProfile1 = match.prefix(11) == "nostr:npub1" || match.prefix(5) == "npub1"
                ? "npub1"
                : "nprofile1"
            
            //let identifier = try ShareableIdentifier(match)
            
            switch pub1OrProfile1 {
                case "npub1":
                    let npub = match.replacingOccurrences(of: "nostr:", with: "")
                    do {
                        let pubkey = try toPubkey(npub)
                        pTags.append(pubkey)
                        if !plainText {
                            replacement = "[@\(contactUsername(fromPubkey: pubkey, event: event).escapeMD())](nostur:p:\(pubkey))"
                        }
                        else {
                            replacement = "" + contactUsername(fromPubkey: pubkey, event: event)
                        }
                    }
                    catch {
                        L.og.debug("problem decoding npub")
                    }
                case "nprofile1":
                let nprofile = match.replacingOccurrences(of: "nostr:", with: "")
                    do {
                        let identifier = try ShareableIdentifier(nprofile)
                        if let pubkey = identifier.pubkey {
                            pTags.append(pubkey)
                            if !plainText {
                                replacement = "[@\(contactUsername(fromPubkey: pubkey, event: event).escapeMD())](nostur:p:\(pubkey))"
                            }
                            else {
                                replacement = "" + contactUsername(fromPubkey: pubkey, event: event)
                            }
                        }
                    }
                    catch {
                        L.og.debug("problem decoding nprofile")
                    }
                default:
                    L.og.debug("eeuh")
            }

            replacedString.replaceSubrange(matchRange, with: replacement)
            
            // Check if the next index is valid
            if matchRange.lowerBound >= replacedString.endIndex {
                break
            }

            let newStartIndex = replacedString.index(after: matchRange.lowerBound)
            range = newStartIndex..<replacedString.endIndex
        }
        return TextWithPs(text: replacedString, pTags: pTags)
    }


    private func removeImageLinks(event: Event, text:String) -> String {
        text.replacingOccurrences(of: #"(?i)https?:\/\/\S+?\.(?:png#?|jpe?g#?|gif#?|webp#?|bmp#?)(\??\S+){0,1}\b"#,
                                  with: "",
                                  options: .regularExpression)
    }

    // Takes a string and replaces any link with a markdown link. Also handles subdomains
    static func replaceURLsWithMarkdownLinks(in string: String) -> String {
        return string
            .replacingOccurrences(of: #"(?!.*\.\.)(?<!https?:\/\/)(?<!\S)[a-zA-Z0-9\-\.]+(?:\.[a-zA-Z]{2,999}+)+([\/\?\=\&\#\.]\@?[\w-]+)*\/?"#,
                                  with: "[$0](https://$0)",
                                  options: .regularExpression) // REPLACE ALL DOMAINS WITHOUT PROTOCOL, WITH MARKDOWN LINK AND ADD PROTOCOL
            .replacingOccurrences(of: #"(?!.*\.\.)(?<!\S)([\w+]+\:\/\/)?[a-zA-Z0-9\-\.]+(?:\.[a-zA-Z]{2,999}+)+([\/\?\=\&\#\%\+\.]\@?[\S]+)*\/?"#,
                                  with: "[$0]($0)",
                                  options: .regularExpression) // REPLACE THE REMAINING URLS THAT HAVE PROTOCOL, BUT IGNORE ALREADY MARKDOWNED LINKS
    }
    
    static func replaceNaddrWithMarkdownLinks(in string: String) -> String {
        return string
            .replacingOccurrences(of: ###"(?:nostr:)?(naddr1[023456789acdefghjklmnpqrstuvwxyz]+)\b"###,
                                  with: "[naddr1...](nostur:nostr:$1)",
                                  options: .regularExpression)
    }

    static func replaceHashtagsWithMarkdownLinks(in string: String) -> String {
        return string
            .replacingOccurrences(of: ###"(?<![/\?]|\b)(\#)([^\s#\]\[]\S{2,})\b"###,
                                  with: "[$0](nostur:t:$2)",
                                  options: .regularExpression)
    }
}

struct TextWithPs: Hashable {
    var text:String
    var pTags:[Ptag]
}

extension String {
    func escapeMD() -> String {
        return self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "**", with: "\\*\\*")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "/", with: "\\/")
            .replacingOccurrences(of: "__", with: "\\_\\_")
    }
}
