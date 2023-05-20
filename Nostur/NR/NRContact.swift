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
//    let npub:String

    var anyName:String
    var displayName:String?
    var username:String?
    var anyUsername:String {
        if let username = username, !username.isEmpty {
            return username
        }
        return String(pubkey.suffix(11))
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
    
    var following:Bool = false
    var zapperPubkey: String?
    
    let contact:Contact // Only touch this in BG context!!!

    init(contact: Contact) {
        self.contact = contact
        self.pubkey = contact.pubkey
        self.anyName = contact.anyName
        self.displayName = contact.displayName
        self.username = contact.username
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
        isFollowingListener()
    }
    
    private func isFollowingListener() {
        receiveNotification(.followersChanged)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let followingPubkeys = notification.object as! Set<String>
                let isFollowing = followingPubkeys.contains(self.pubkey)
                if isFollowing != self.following {
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.following = isFollowing
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    var subscriptions = Set<AnyCancellable>()
    
    private func listenForChanges() {
        self.contact.contactUpdated
            .sink { [weak self] contact in
                guard let self = self else { return }
                
                let displayName = contact.display_name
                let username = contact.name
                let pictureUrl = contact.picture
                let about = contact.about
                
                let nip05verified = contact.nip05veried
                let nip05domain = contact.nip05domain
                let metaDataCreatedAt = Date(timeIntervalSince1970: TimeInterval(contact.metadata_created_at))
                let metadata_created_at = contact.metadata_created_at
                
                let anyLud = contact.anyLud
                let lud06 = contact.lud06
                let lud16 = contact.lud16
                let zapperPubkey = contact.zapperPubkey
                
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    
                    self.displayName = displayName
                    self.username = username
                    self.pictureUrl = pictureUrl
                    self.about = about
                    
                    self.nip05verified = nip05verified
                    self.nip05domain = nip05domain
                    self.metaDataCreatedAt = metaDataCreatedAt
                    self.metadata_created_at = metadata_created_at
                    
                    self.anyLud = anyLud
                    self.lud06 = lud06
                    self.lud16 = lud16
                    self.zapperPubkey = zapperPubkey
                }
            }
            .store(in: &subscriptions)
    }
    
    var mainContact:Contact {
        DataProvider.shared().viewContext.object(with: contact.objectID) as! Contact
    }
}
