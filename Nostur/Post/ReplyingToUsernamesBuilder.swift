//
//  ReplyingToUsernamesBuilder.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//

import Foundation
import CoreData

class ReplyingToUsernamesBuilder {
    let context:NSManagedObjectContext
    
    init(_ context:NSManagedObjectContext? = nil) {
        self.context = context ?? DataProvider.shared().viewContext
    }
    
    func replyingToUsernamesMarkDownString(_ event:Event) -> String? {
        guard event.replyToId != nil || event.replyTo != nil else { return nil }
        
        let pTags = Set(event.tags().filter { $0.type == "p" }.map { $0.pubkey })
            .sorted()
        
        let pTagsAsStrings = pTags.map { pubkey in
            let username = contactUsername(fromPubkey: pubkey, event: event)
                .escapeMD()
            return "[@\(username)](nostur:p:\(pubkey))"
        }
        if (pTagsAsStrings.count > 6) {
            return "Replying to: " + pTagsAsStrings.prefix(4).joined(separator: ", ") + " and \(pTagsAsStrings.count-4) others"
        }
        else if (pTagsAsStrings.count > 0) {
            return "Replying to: " + pTagsAsStrings.joined(separator: ", ")
        }
        return nil
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
}

extension String {
    func escapeMD() -> String {
        return self
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "/", with: "\\/")
            .replacingOccurrences(of: "\\", with: "\\\\")
    }
}
