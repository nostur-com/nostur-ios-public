//
//  NRPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import Foundation
import Combine

class NRContact: ObservableObject, Identifiable, Hashable {
    
    static func == (lhs: NRContact, rhs: NRContact) -> Bool {
        lhs.pubkey == rhs.pubkey
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pubkey)
    }
        
    var id:String { pubkey }
    let pubkey:String
    let npub:String

    var displayName:String?
    var anyDisplayName:String {
        if let displayName = displayName, !displayName.isEmpty {
            return displayName
        }
        return anyUsername
    }
    
    var username:String?
    var anyUsername:String {
        if let username = username, !username.isEmpty {
            return username
        }
        return String(npub.prefix(11))
    }
    var pictureUrl:String?
    var about:String?
    
    var nip05verified:Bool
    var nip05domain:String?
    var metaDataCreatedAt:Date
    var metadata_created_at:Int64
    
    var anyLud = false
    var lud06:String?
    var lud16:String?
    
    var following:Bool = false // TODO: FIX FOLLOWING
    var zapperPubkey: String?
    
    let contact:Contact // Only touch this in BG context!!!

    init(contact: Contact) {
        self.contact = contact
        self.pubkey = contact.pubkey
        self.npub = "...." // contact.npub
        
        self.displayName = contact.display_name
        self.username = contact.name
        self.pictureUrl = contact.picture
        self.about = contact.about
        
        self.nip05verified = contact.nip05veried
        self.nip05domain = contact.nip05domain
        self.metaDataCreatedAt = Date(timeIntervalSince1970: TimeInterval(contact.metadata_created_at))
        self.metadata_created_at = contact.metadata_created_at
        
        self.anyLud = contact.anyLud
        self.lud06 = contact.lud06
        self.lud16 = contact.lud16
        self.zapperPubkey = contact.zapperPubkey
        
        // self.following = // todo
        listenForChanges()
    }
    
    // Save properties that can be changed, unlike pubkey, npub etc
    private func updateProperties() {
        self.displayName = contact.display_name
        self.username = contact.name
        self.pictureUrl = contact.picture
        self.about = contact.about
        
        self.nip05verified = contact.nip05veried
        self.nip05domain = contact.nip05domain
        self.metaDataCreatedAt = Date(timeIntervalSince1970: TimeInterval(contact.metadata_created_at))
        self.metadata_created_at = contact.metadata_created_at
        
        self.anyLud = contact.anyLud
        self.lud06 = contact.lud06
        self.lud16 = contact.lud16
        self.zapperPubkey = contact.zapperPubkey
    }
    
    var subscriptions = Set<AnyCancellable>()
    
    private func listenForChanges() {
        contactSavedListener()
    }
    
    private func contactSavedListener() {
        receiveNotification(.contactSaved)
            .filter({ [weak self] notification in
                guard let self = self else { return false }
                let contactPubkey = notification.object as! String
                return self.pubkey == contactPubkey
            })
            .throttle(for: .seconds(0.1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] notification in
            guard let self = self else { return }
//            let contactPubkey = notification.object as! String
            
            DataProvider.shared().bg.perform { [weak self] in
                self?.updateProperties()
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
        }
        .store(in: &subscriptions)
    }
    
    var mainContact:Contact {
        DataProvider.shared().viewContext.object(with: contact.objectID) as! Contact
    }
}
