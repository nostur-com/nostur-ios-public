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
// DOES NOT handle note links or image links, because those are embeds, handled by DetailContentRenderer
class ContentLinkRenderer { // TEXT things
    let context:NSManagedObjectContext
    
    init(_ context:NSManagedObjectContext? = nil) {
        self.context = context ?? DataProvider.shared().viewContext
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
        if let eventContact = event.contact, eventContact.pubkey == pubkey {
            return eventContact.username != "" ? eventContact.username : eventContact.authorName
        }
        if let contact = event.contacts?.first(where: { $0.pubkey == pubkey }) {
            return contact.username != "" ? contact.username : contact.authorName
        }
        // SLOW?
        if let contact = Contact.fetchByPubkey(pubkey, context: context) {
            return contact.username != "" ? contact.username : contact.authorName
        }
        return "--"
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
        let tags = event.tags()
        guard tags.count > 0 else { return text }
        
        var newText = text
        for index in tags.indices {
            if (tags[index].type == "p") {
                if !plainText {
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(contactUsername(fromPubkey: tags[index].pubkey, event:event).escapeMD())](nostur:p:\(tags[index].pubkey))")
                }
                else {
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "@\(contactUsername(fromPubkey: tags[index].pubkey, event:event))")
                }
            }
            if (tags[index].type == "e") {
                if !plainText {
                    let key = try! NIP19(prefix: "note1", hexString: tags[index].id)
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(String(key.displayString).prefix(11))](nostur:e:\(tags[index].id))")
                }
                else {
                    let key = try! NIP19(prefix: "note1", hexString: tags[index].id)
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "@\(String(key.displayString).prefix(11))")
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

        while let matchRange = replacedString.range(of: pattern, options: .regularExpression, range: range, locale: nil) {
            let match = replacedString[matchRange]
            var replacement = match
            switch match.prefix(11) {
                case "nostr:npub1":
                    let npub = String(match.dropFirst(6))
                    let pubkey = pubkey(npub)
                    if !plainText {
                        replacement = "[@\(contactUsername(fromPubkey: pubkey, event: event).escapeMD())](nostur:p:\(pubkey))"
                    }
                    else {
                        replacement = "" + contactUsername(fromPubkey: pubkey, event: event)
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
            .replacingOccurrences(of: ###"(?<![/\?]|\b)(\#)(\S+)"###,
                                  with: "[$0](nostur:t:$2)",
                                  options: .regularExpression)
    }
}



