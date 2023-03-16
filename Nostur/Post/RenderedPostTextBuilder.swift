//
//  RenderedNoteTextBuilder.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//

import Foundation
import CoreData

class RenderedPostTextBuilder {
    let context:NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    func renderedText(_ event:Event) -> AttributedString {
        var newText = event.noteText
        let tags = event.tags()
        if (tags.count > 0) {
            for index in tags.indices {
                if (tags[index].type == "p") {
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(contactUsername(fromPubkey: tags[index].pubkey, event:event))](nostur:p:\(tags[index].pubkey))")
                }
                if (tags[index].type == "e") {
                    let key = try! NIP19(prefix: "note1", hexString: tags[index].id)
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(String(key.displayString).prefix(11))](nostur:e:\(tags[index].id))")
                }
            }
        }
        do {
            let newText = Self.replaceURLsWithMarkdownLinks(in: newText)
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
        do {
            return String((try NIP19(prefix: "npub", hexString: pubkey).displayString).prefix(11))
        }
        catch {
            return  "⏤⏤"
        }
    }
    
    func copyPasteText(_ event:Event) -> String {
        var newText = event.noteText
        let tags = event.tags()
        if (tags.count > 0) {
            for index in tags.indices {
                if (tags[index].type == "p") {
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "@\(contactUsername(fromPubkey: tags[index].pubkey, event:event))")
                }
                if (tags[index].type == "e") {
                    // TODO: NIP19 bech32 is very slow, with hundreds of rows it slows down UI noticeably, so disable for now
                    let key = try! NIP19(prefix: "note1", hexString: tags[index].id)
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "@\(String(key.displayString).prefix(12))")
                }
            }
        }
        return newText
    }
    
    // Takes a string and replaces any link with a markdown link. Also handles subdomains
    static func replaceURLsWithMarkdownLinks(in string: String) -> String {
        return string
            .replacingOccurrences(of: #"(?<!https?:\/\/)(?<!\S)[a-zA-Z0-9\-\.]+(?:\.[a-zA-Z]+)+([\/\?\=\&\#\.]\@?[\w-]+)*\/?"#,
                                  with: "[$0](https://$0)",
                                  options: .regularExpression) // REPLACE ALL DOMAINS WITHOUT PROTOCOL, WITH MARKDOWN LINK AND ADD PROTOCOL
            .replacingOccurrences(of: #"(?<!\S)([\w+]+\:\/\/)?[a-zA-Z0-9\-\.]+(?:\.[a-zA-Z]+)+([\/\?\=\&\#\.]\@?[\w-]+)*\/?"#,
                                  with: "[$0]($0)",
                                  options: .regularExpression) // REPLACE THE REMAINING URLS THAT HAVE PROTOCOL, BUT IGNORE ALREADY MARKDOWNED LINKS
    }
}
