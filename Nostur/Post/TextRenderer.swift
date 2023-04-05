//
//  ContentRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/03/2023.
//

import Foundation
import CoreData

// Renders links for the text parts of post contents (in TEXT)
// Handles profile links
// Tag links
// Other links
// DOES NOT handle note links or image links, because those are embeds, handled by ContentRenderer
class TextRenderer { // TEXT things
    let context:NSManagedObjectContext
    let event:Event // The current event, so we dont need to duplicate .tags parsing
    let tags:[(String, String)] // Faster tags, and only decode once at init
    
    init(_ context:NSManagedObjectContext? = nil, event:Event) {
        self.context = context ?? DataProvider.shared().viewContext
        self.event = event
        self.tags = event.fastTags
    }
    
    func renderedText(_ event:Event, text: String) -> AttributedString {
//        var newText = text
        
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
        
        do {
//            newText = Self.replaceURLsWithMarkdownLinks(in: newText)
            newText = Self.replaceHashtagsWithMarkdownLinks(in: newText)
            let finalText = try AttributedString(markdown: newText, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return finalText
        }
        catch {
            let finalText = AttributedString(newText)
            print(error)
            return finalText
        }
    }
    
    func contactUsername(fromPubkey pubkey:String, event:Event) -> String {
        if let username = PubkeyUsernameCache.shared.retrieveObject(at: pubkey) {
            return username
        }
        if let eventContact = event.contact, eventContact.pubkey == pubkey {
            let username = eventContact.username != "" ? eventContact.username : eventContact.authorName
            PubkeyUsernameCache.shared.setObject(for: pubkey, value: username)
            return username
        }
        if let contact = event.contacts?.first(where: { $0.pubkey == pubkey }) {
            let username = contact.username != "" ? contact.username : contact.authorName
            PubkeyUsernameCache.shared.setObject(for: pubkey, value: username)
            return username
        }
        // SLOW?
        if let contact = Contact.fetchByPubkey(pubkey, context: context) {
            let username = contact.username != "" ? contact.username : contact.authorName
            PubkeyUsernameCache.shared.setObject(for: pubkey, value: username)
            return username
        }
        return "--"
    }
    
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
        else if (pTags.count > 0) {
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
        guard tags.count > 0 else { return text }
        
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
        let pattern = "nostr:npub1\\S+|nostr:nprofile1\\S+"

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
                        let pubkey = try pubkey(npub)
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





extension String {
    func escapeMD() -> String {
        return self
            .replacingOccurrences(of: "__", with: "\\_\\_")
            .replacingOccurrences(of: "**", with: "\\*\\*")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "/", with: "\\/")
            .replacingOccurrences(of: "\\", with: "\\\\")
    }
}
