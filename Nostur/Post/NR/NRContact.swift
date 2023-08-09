//
//  NRContact.swift
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

    var anyName:String
    var display_name:String?
    var name:String?
    var pictureUrl:String?
    var about:String?
    @Published var couldBeImposter:Int16 = -1 // -1: unchecked, 0:false 1:true
    
    var nip05verified:Bool
    var nip05domain:String?
    var metaDataCreatedAt:Date
    var metadata_created_at:Int64
    
    var anyLud = false
    var lud06:String?
    var lud16:String?
    
    var following:Bool = false
    var privateFollow:Bool = false
    var zapperPubkey: String?
    
    let contact:Contact // Only touch this in BG context!!!

    init(contact: Contact, following:Bool? = nil) {
        self.contact = contact
        self.pubkey = contact.pubkey
        self.anyName = contact.anyName
        self.display_name = contact.display_name
        self.name = contact.name
        self.pictureUrl = contact.picture
        self.about = contact.about
        self.couldBeImposter = contact.couldBeImposter
        
        self.nip05verified = contact.nip05veried
        self.nip05domain = contact.nip05domain
        self.metaDataCreatedAt = Date(timeIntervalSince1970: TimeInterval(contact.metadata_created_at))
        self.metadata_created_at = contact.metadata_created_at
        
        self.anyLud = contact.anyLud
        self.lud06 = contact.lud06
        self.lud16 = contact.lud16
        self.zapperPubkey = contact.zapperPubkey
        
        self.following = following ?? false
        self.privateFollow = contact.privateFollow
        listenForChanges()
        isFollowingListener()
        listenForNip05()
    }
    
    private func isFollowingListener() {
        receiveNotification(.followersChanged)
            .subscribe(on: DispatchQueue.global())
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
    
    private func listenForNip05() {
        self.contact.nip05updated
            .sink { [weak self] isVerified in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    guard isVerified != self.nip05verified else { return }
                    self.objectWillChange.send()
                    self.nip05verified = isVerified
                }
            }
            .store(in: &subscriptions)
    }
    
    private func listenForChanges() {
        self.contact.contactUpdated
            .sink { [weak self] contact in
                guard let self = self else { return }
                
                let anyName = contact.anyName
                let display_name = contact.display_name
                let name = contact.name
                let pictureUrl = contact.picture
                let about = contact.about
                let couldBeImposter = contact.couldBeImposter
                
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
                    
                    self.anyName = anyName
                    self.display_name = display_name
                    self.name = name
                    self.pictureUrl = pictureUrl
                    self.about = about
                    self.couldBeImposter = couldBeImposter
                    
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
