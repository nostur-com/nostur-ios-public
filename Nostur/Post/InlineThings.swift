//
//  InlineThings.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/04/2023.
//

import SwiftUI
import Foundation
import CoreData
import UIKit

// TODO: Hashtags icons in text. Almost got them working, but stuck on a problem. Disabled/not used until completely fixed.
// TODO: 2 months later clean up: Forgot what the problem was, maybe something with wrong heights because of UIViewRepresentable, or replacing hashtags in hashtags, cant remember. need to look into it again later


// renderer
// string -> md links -> string -> hashtags -> NSAttributedString

// view
// -> NSAttributedString -> UIViewRepresentable view

class NewTextRenderer { // TEXT things
    let context:NSManagedObjectContext
    let event:Event // The current event, so we dont need to duplicate .tags parsing
    let tags:[(String, String, String?, String?)] // Faster tags, and only decode once at init
    
    init(_ context:NSManagedObjectContext? = nil, event:Event) {
        self.context = context ?? DataProvider.shared().viewContext
        self.event = event
        self.tags = event.fastTags
    }
    
    // Takes text, removes links, converts hashtags, mentions etc. to markdown
    func convertToMarkdown(_ event:Event, text: String) -> String {
        
        // Remove image links
        // because they get rendered as embers in PostDetail.
        // and NoteRow shows them in ImageViewer
        var newText = removeImageLinks(event: event, text: text)
        
        // NIP-08, handle #[0] #[1] etc
        newText = parseTagIndexedMentions(event: event, text: newText)
        
        // NIP-28 handle nostr:npub1, nostr:nprofile ...
        newText = parseUserMentions(event: event, text: newText)
        if newText.suffix(1) == "\n" {
            newText = String(newText.dropLast(1))
        }
        
        newText = Self.replaceHashtagsWithMarkdownLinks(in: newText)
        return newText
    }
    
//    func contactUsername(fromPubkey pubkey:String, event:Event) -> String {
//        if let username = PubkeyUsernameCache.shared.retrieveObject(at: pubkey) {
//            return username
//        }
//        if let eventContact = event.contact, eventContact.pubkey == pubkey {
//            let username = eventContact.username != "" ? eventContact.username : eventContact.authorName
//            PubkeyUsernameCache.shared.setObject(for: pubkey, value: username)
//            return username
//        }
//        if let contact = event.contacts?.first(where: { $0.pubkey == pubkey }) {
//            let username = contact.username != "" ? contact.username : contact.authorName
//            PubkeyUsernameCache.shared.setObject(for: pubkey, value: username)
//            return username
//        }
//        if event.replyTo?.contact?.pubkey == pubkey {
//            let contact = event.replyTo!.contact!
//            let username = contact.username != "" ? contact.username : contact.authorName
//            PubkeyUsernameCache.shared.setObject(for: pubkey, value: username)
//            return username
//        }
//        // SLOW?
//        if let contact = Contact.fetchByPubkey(pubkey, context: context) {
//            let username = contact.username != "" ? contact.username : contact.authorName
//            PubkeyUsernameCache.shared.setObject(for: pubkey, value: username)
//            return username
//        }
//        return "--"
//    }
    
    func replyingToUsernamesMarkDownString(_ event:Event) -> String? {
        guard event.replyToId != nil || event.replyTo != nil else { return nil }
        guard tags.count < 50 else { return "Replying to \(tags.count) people" }
        
        
        let pTags = Set(tags.filter { $0.0 == "p" }.map { $0.1 })
        if (pTags.count > 6) {
            let pTagsAsStrings = pTags.prefix(4).map { pubkey in
                let username = contactUsername(fromPubkey: pubkey, event: event)
                    .escapeMD()
                return "[@\(username)](nostur:p:\(pubkey))"
            }
            return "Replying to: " + pTagsAsStrings.joined(separator: ", ") + " and \(pTags.count-4) others"
        }
        else if (!pTags.isEmpty) {
            let pTagsAsStrings = pTags.map { pubkey in
                let username = contactUsername(fromPubkey: pubkey, event: event)
                    .escapeMD()
                return "[@\(username)](nostur:p:\(pubkey))"
            }
            return "Replying to: " + pTagsAsStrings.joined(separator: ", ")
        }
        return nil
    }
    
    func copyPasteText(_ event:Event,  text: String) -> String {
        var newText = text
        
        // NIP-08, handle #[0] #[1] etc
        newText = parseTagIndexedMentions(event: event, text: text, plainText: true)
        
        // NIP-28 handle nostr:npub1, nostr:nprofile ...
        newText = parseUserMentions(event: event, text: newText, plainText: true)
        
        return newText
    }
    
    // NIP-08 (deprecated in favor of NIP-27)
    func parseTagIndexedMentions(event:Event, text:String, plainText:Bool = false) -> String {
        guard !tags.isEmpty else { return text }
        
        var newText = text
        let matches = text.matches(of: /#\[(\d+)\]/)
        for match in matches.prefix(100) { // 100 limit for sanity
            guard let tagIndex = Int(match.output.1) else { continue }
            guard tagIndex < tags.count else { continue }
            let tag = tags[tagIndex]
            
            if (tag.0 == "p") {
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
        return newText
    }
    
    // NIP-27 handle nostr:npub or nostr:nprofile
    func parseUserMentions(event:Event, text:String, plainText:Bool = false) -> String {
        let pattern = "nostr:npub1[023456789acdefghjklmnpqrstuvwxyz]{58}|nostr:nprofile1[023456789acdefghjklmnpqrstuvwxyz]{30,999}"
        
        var replacedString = text
        var range = text.startIndex..<text.endIndex
        
        var sanityIndex = 0
        while let matchRange = replacedString.range(of: pattern, options: .regularExpression, range: range, locale: nil) {
            if sanityIndex > 100 { break }
            sanityIndex += 1
            let match = replacedString[matchRange]
            var replacement = match
            switch match.prefix(11) {
                case "nostr:npub1":
                    let npub = String(match.dropFirst(6))
                    do {
                        let pubkey = try toPubkey(npub)
                        if !plainText {
                            replacement = "[@\(contactUsername(fromPubkey: pubkey, event: event).escapeMD())](nostur:p:\(pubkey))"
                        }
                        else {
                            replacement = "" + contactUsername(fromPubkey: pubkey, event: event)
                        }
                    }
                    catch {
                        print("problem decoding npub")
                    }
                case "nostr:nprof":
                    let nprofile = String(match.dropFirst(6))
                    do {
                        let identifier = try ShareableIdentifier(nprofile)
                        if let pubkey = identifier.pubkey {
                            if !plainText {
                                replacement = "[@\(contactUsername(fromPubkey: pubkey, event: event).escapeMD())](nostur:p:\(pubkey))"
                            }
                            else {
                                replacement = "" + contactUsername(fromPubkey: pubkey, event: event)
                            }
                        }
                    }
                    catch {
                        print("problem decoding nprofile")
                    }
                default:
                    print("eeuh")
            }
            
            replacedString.replaceSubrange(matchRange, with: replacement)
            range = replacedString.index(after: matchRange.lowerBound)..<replacedString.endIndex
        }
        
        return replacedString
    }
    
    func removeImageLinks(event: Event, text:String) -> String {
        text.replacingOccurrences(of: #"(?i)https?:\/\/\S+?\.(?:png|jpe?g|gif|webp|bmp)(\?\S+){0,1}\b"#,
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
    
    static func replaceHashtagsWithMarkdownLinks(in string: String) -> String {
        return string
            .replacingOccurrences(of: ###"(?<![/\?]|\b)(\#)(\S{2,})\b"###,
                                  with: "[$0](nostur:t:$2)",
                                  options: .regularExpression)
    }
}

struct MarkdownText: UIViewRepresentable {
    
    let hashtags = ["#bitcoin": "HashtagBitcoin",
                    "#btc": "HashtagBitcoin",
                    "#sats": "HashtagBitcoin",
                    "#satoshis": "HashtagBitcoin",
                    "#nostur": "HashtagNostur",
                    "#nostr": "HashtagNostr",
                    "#lightning": "HashtagLightning",
                    "#zapping": "HashtagLightning",
                    "#zapped": "HashtagLightning",
                    "#zaps": "HashtagLightning",
                    "#zap": "HashtagLightning"]
    
    let string:String
    
    init(_ string:String) {
        self.string = string
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        
//        textView.textContainer.lineBreakMode = .byCharWrapping
        
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let attributedString = NSMutableAttributedString(string: string)
        attributedString.addAttributes([.font: bodyFont], range: NSRange(location: 0, length: attributedString.length))
        
        attributedString.convertMarkdown(hashtags)
        
        textView.attributedText = attributedString
//
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        
//        textView.setContentHuggingPriority(.defaultHigh, for: .horizontal) // << here !!
//        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
    }
}

extension NSMutableAttributedString {
    
    func convertMarkdown(_ hashtags:[String: String]) {
        convertMarkdownLinks()
        convertMarkdownBold()
        convertMarkdownItalic()
        convertMarkdownItalic2()
        convertMarkdownStrikethrough()
        convertMarkdownMonospaced()
        convertHashtags(hashtags)
    }
    
    private func convertMarkdownLinks() {
        let markdownLinkPattern = "\\[(.*?)\\]\\((.*?)\\)"
        let regex = try? NSRegularExpression(pattern: markdownLinkPattern, options: [])
        
        let matches = regex?.matches(in: string, options: [], range: NSRange(location: 0, length: length)) ?? []
        
        // Reverse the matches array, so we can safely replace ranges without affecting the next matches.
        let reversedMatches = Array(matches.reversed())
        
        for match in reversedMatches {
            if match.numberOfRanges == 3 {
                let titleRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                let font = UIFont.preferredFont(forTextStyle: .body)
                
                if let url = URL(string: (string as NSString).substring(with: urlRange)) {
                    let linkAttributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .link: url,
                        .foregroundColor: UIColor(named: "AccentColor")!
                    ]
                    
                    let linkedText = NSAttributedString(string: (string as NSString).substring(with: titleRange), attributes: linkAttributes)
                    replaceCharacters(in: match.range, with: linkedText)
                }
            }
        }
    }
    
    private func convertMarkdownBold() {
        let boldPattern = "\\*\\*([^*]+)\\*\\*"
        let regex = try? NSRegularExpression(pattern: boldPattern, options: [])
        
        let matches = regex?.matches(in: string, options: [], range: NSRange(location: 0, length: length)) ?? []
        let reversedMatches = Array(matches.reversed())
        
        for match in reversedMatches {
            if match.numberOfRanges == 2 {
                let contentRange = match.range(at: 1)
                let boldFont = UIFont.preferredFont(forTextStyle: .body).bold
                
                let boldAttributes: [NSAttributedString.Key: Any] = [
                    .font: boldFont
                ]
                
                let boldText = NSAttributedString(string: (string as NSString).substring(with: contentRange), attributes: boldAttributes)
                replaceCharacters(in: match.range, with: boldText)
            }
        }
    }
    
    private func convertMarkdownItalic() {
        let italicPattern = "\\*([^*]+)\\*"
        let regex = try? NSRegularExpression(pattern: italicPattern, options: [])
        
        let matches = regex?.matches(in: string, options: [], range: NSRange(location: 0, length: length)) ?? []
        let reversedMatches = Array(matches.reversed())
        
        for match in reversedMatches {
            if match.numberOfRanges == 2 {
                let contentRange = match.range(at: 1)
                let italicFont = UIFont.preferredFont(forTextStyle: .body).italic
                
                let italicAttributes: [NSAttributedString.Key: Any] = [
                    .font: italicFont
                ]
                
                let italicText = NSAttributedString(string: (string as NSString).substring(with: contentRange), attributes: italicAttributes)
                replaceCharacters(in: match.range, with: italicText)
            }
        }
    }
    
    private func convertMarkdownItalic2() {
        let italicPattern = "__([^__]+)__"
        let regex = try? NSRegularExpression(pattern: italicPattern, options: [])
        
        let matches = regex?.matches(in: string, options: [], range: NSRange(location: 0, length: length)) ?? []
        let reversedMatches = Array(matches.reversed())
        
        for match in reversedMatches {
            if match.numberOfRanges == 2 {
                let contentRange = match.range(at: 1)
                let italicFont = UIFont.preferredFont(forTextStyle: .body).italic
                
                let italicAttributes: [NSAttributedString.Key: Any] = [
                    .font: italicFont
                ]
                
                let italicText = NSAttributedString(string: (string as NSString).substring(with: contentRange), attributes: italicAttributes)
                replaceCharacters(in: match.range, with: italicText)
            }
        }
    }
    
    private func convertMarkdownStrikethrough() {
        let strikethroughPattern = "~~([^~]+)~~"
        let regex = try? NSRegularExpression(pattern: strikethroughPattern, options: [])
        
        let matches = regex?.matches(in: string, options: [], range: NSRange(location: 0, length: length)) ?? []
        let reversedMatches = Array(matches.reversed())
        
        for match in reversedMatches {
            if match.numberOfRanges == 2 {
                let contentRange = match.range(at: 1)
                
                let font = UIFont.preferredFont(forTextStyle: .body)
                let strikethroughAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]
                
                let strikethroughText = NSAttributedString(string: (string as NSString).substring(with: contentRange), attributes: strikethroughAttributes)
                replaceCharacters(in: match.range, with: strikethroughText)
            }
        }
    }
    
    private func convertMarkdownMonospaced() {
        let monospacedPattern = "`([^`]+)`"
        let regex = try? NSRegularExpression(pattern: monospacedPattern, options: [])
        
        let matches = regex?.matches(in: string, options: [], range: NSRange(location: 0, length: length)) ?? []
        let reversedMatches = Array(matches.reversed())
        
        for match in reversedMatches {
            if match.numberOfRanges == 2 {
                let contentRange = match.range(at: 1)
                let monospacedFont = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
                
                let monospacedAttributes: [NSAttributedString.Key: Any] = [
                    .font: monospacedFont
                ]
                
                let monospacedText = NSAttributedString(string: (string as NSString).substring(with: contentRange), attributes: monospacedAttributes)
                replaceCharacters(in: match.range, with: monospacedText)
            }
        }
    }
    
    private func convertHashtags(_ hashtags:[String: String]) {
        
        let font = UIFont.preferredFont(forTextStyle: .body)
        var h = [String: NSAttributedString]()
        let size = (font.capHeight - font.pointSize).rounded() / 2
        
        for tag in hashtags {
            let attachment = NSTextAttachment()
            attachment.image = UIImage(named: tag.value)//?.withRenderingMode(.alwaysTemplate)
            attachment.bounds = CGRect(x: 0, y: size, width: font.pointSize, height: font.pointSize)
            let attributedImageString = NSAttributedString(attachment: attachment)
            h[tag.key] = attributedImageString
        }
        
        var replaced = [String]()
        
        for tag in h.sorted(by: { $0.key.count > $1.key.count }) {
            
            let regex = try? NSRegularExpression(pattern: "\(tag.key)", options: [.caseInsensitive])
            
            let matches = regex?.matches(in: string, options: [], range: NSRange(location: 0, length: length)) ?? []
            let reversedMatches = Array(matches.reversed())
            
            for match in reversedMatches {
                if match.numberOfRanges == 1 {
                    let contentRange = match.range(at: 0)
                    
                    let tagString = (string as NSString).substring(with: contentRange) // #Zapped
                    if replaced.first(where: { $0.prefix(tagString.count) == tagString }) == nil { // Dont replace #Zap if we already replaced #Zapped (#Zap⚡️ ped⚡️)
                        replaced.append(tagString)
                    }
                    else {
                        continue
                    }
                    
                    
                    let replacementAttributedString = NSMutableAttributedString(string: tag.key + " ")
                    replacementAttributedString.setAttributes([.font: font], range: NSRange(location: 0, length: replacementAttributedString.length))
                    replacementAttributedString.append(tag.value)
                    //                    string.replaceCharacters(in: contentRange, with: replacementAttributedString)
                    
                    
                    replaceCharacters(in: contentRange, with: replacementAttributedString)
                }
            }
        }
        
    }
}


//func renderHashtags(_ hashtags: [String: String], font: UIFont, in attributedText: NSAttributedString) -> NSAttributedString {
//
//    var h = [String: NSAttributedString]()
//    let size = (font.capHeight - font.pointSize).rounded() / 2
//
//    for tag in hashtags {
//        let attachment = NSTextAttachment()
//        attachment.image = UIImage(named: tag.value)//?.withRenderingMode(.alwaysTemplate)
//        attachment.bounds = CGRect(x: 0, y: size, width: font.pointSize, height: font.pointSize)
//        let attributedImageString = NSAttributedString(attachment: attachment)
//        h[tag.key] = attributedImageString
//    }
//
//    let mutableAttributedString = NSMutableAttributedString(attributedString: attributedText)
//
//    for tag in h {
//        var searchStartIndex = mutableAttributedString.string.startIndex
//        while let tagRange = mutableAttributedString.string.range(of: tag.key, options: [.caseInsensitive], range: searchStartIndex..<mutableAttributedString.string.endIndex) {
//            let nsRange = NSRange(tagRange, in: mutableAttributedString.string)
//
//
//            let replacementAttributedString = NSMutableAttributedString(string: tag.key + " ")
//            replacementAttributedString.setAttributes([.font: font], range: NSRange(location: 0, length: replacementAttributedString.length))
//            replacementAttributedString.append(tag.value)
//            mutableAttributedString.replaceCharacters(in: nsRange, with: replacementAttributedString)
//
//
//            let utf16Offset = nsRange.location + tag.value.length
//            searchStartIndex = String.Index(utf16Offset: utf16Offset, in: mutableAttributedString.string)
//        }
//    }
//
//    return mutableAttributedString
//}

struct HashtagRenderer_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadMedia()
        }) {
            VStack {
                if let event = PreviewFetcher.fetchEvent("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3") {
                    let renderer = NewTextRenderer(event: event)
                    let toMarkdown = renderer.convertToMarkdown(event, text: event.noteText)
                    
                    ScrollView {
                        VStack {
                            Text("Test")
                            MarkdownText("This __is__ #bitcoin **and** #nostur [doesnt work](https://nostur.com) #nostr and #zaps hey #Zapped or #lightning")
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
        //                        .frame(maxWidth: .infinity)
                            MarkdownText(toMarkdown)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}


//extension String {
//    func escapeMD() -> String {
//        return self
//            .replacingOccurrences(of: "__", with: "\\_\\_")
//            .replacingOccurrences(of: "**", with: "\\*\\*")
//            .replacingOccurrences(of: "[", with: "\\[")
//            .replacingOccurrences(of: "]", with: "\\]")
//            .replacingOccurrences(of: "/", with: "\\/")
//            .replacingOccurrences(of: "\\", with: "\\\\")
//    }
//}
