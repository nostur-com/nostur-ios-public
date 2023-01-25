//
//  ContactProfile.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2023.
//

import Foundation
import SwiftyJSON

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
    
    var npub:String {
        get {
            contact.pubkey != nil ? try! NIP19(prefix: "npub", hexString: contact.pubkey!).displayString : "?"
        }
    }
    
    init(contact: Contact, metaData: NSetMetadata? = nil, clEvent: Event? = nil) {
        self.contact = contact
        self.metaData = metaData
        self.clEvent = clEvent
    }
    
    var id:String {
        get { contact.pubkey! }
    }
    
    var authorName:String {
        get { contact.authorName }
    }
    
    var username:String {
        get { contact.name ?? contact.authorKey }
    }
    
    var publicKey:String {
        get { contact.pubkey! }
    }
    
    var about:String {
        get { contact.about ?? "" }
    }
    
    static func == (lhs: ContactProfile, rhs: ContactProfile) -> Bool {
        return lhs.contact.id == rhs.contact.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(contact.id)
    }
    
    func contactsPubkeys() -> [String]? {
        guard let tagsSerialized = clEvent?.tagsSerialized else {
            return nil
        }
        
        guard let tags = try? JSON(data: tagsSerialized.data(using: .utf8, allowLossyConversion: false)!) else {
            return nil
        }
        
        return tags.filter { $0.1[0] == "p" } .map { $0.1[1].stringValue }
    }
    
}
