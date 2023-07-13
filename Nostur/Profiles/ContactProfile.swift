//
//  ContactProfile.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2023.
//

import Foundation

class ContactProfile: Identifiable, Hashable, ObservableObject {
    
    @Published var contact:Contact
    @Published var metaData:NSetMetadata? = nil {
        willSet {
            objectWillChange.send()
        }
    }
    @Published var clEvent:Event? = nil {
        willSet {
            objectWillChange.send()
        }
    }

    init(contact: Contact, metaData: NSetMetadata? = nil, clEvent: Event? = nil) {
        self.contact = contact
        self.metaData = metaData
        self.clEvent = clEvent
    }
    
    var npub:String { try! NIP19(prefix: "npub", hexString: contact.pubkey).displayString }
    var id:String { contact.pubkey }
    var authorName:String { contact.authorName }
    var username:String { contact.name ?? contact.authorKey }
    var publicKey:String { contact.pubkey }
    var about:String { contact.about ?? "" }
    
    static func == (lhs: ContactProfile, rhs: ContactProfile) -> Bool {
        return lhs.contact.id == rhs.contact.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(contact.id)
    }
    
    func contactsPubkeys() -> [String]? {
        guard let clEvent = clEvent else { return nil }
        guard clEvent.tagsSerialized != nil else { return nil }

        return clEvent.fastPs.map { $0.1 }
    }
    
}
