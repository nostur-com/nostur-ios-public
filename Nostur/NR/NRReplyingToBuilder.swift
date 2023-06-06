import CoreData

class NRReplyingToBuilder {
    
    static let shared = NRReplyingToBuilder()

    func replyingToUsernamesMarkDownString(_ event:Event) -> String? {
        guard event.replyToId != nil || event.replyTo != nil else { return nil }
        let tags = event.fastTags
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

}

func contactUsername(fromPubkey pubkey:String, event:Event) -> String {
    if let anyName = PubkeyUsernameCache.shared.retrieveObject(at: pubkey) {
        return anyName
    }
    if let contact = event.contact, contact.pubkey == pubkey {
        PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
        return contact.anyName
    }
    if let contact = event.contacts?.first(where: { $0.pubkey == pubkey }) {
        PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
        return contact.anyName
    }
    if let contact = event.replyTo?.contact, pubkey == contact.pubkey {
        PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
        return contact.anyName
    }
    
    if let contact = EventRelationsQueue.shared.getAwaitingBgContacts().first(where: { $0.pubkey == pubkey }) {
        PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
        return contact.anyName
    }
    
    if let context = event.managedObjectContext {
        if let contact = Contact.fetchByPubkey(pubkey, context: context) {
            PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
            return contact.anyName
        }
    }
    return "..."
}
