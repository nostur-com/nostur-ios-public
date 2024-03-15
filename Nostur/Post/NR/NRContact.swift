//
//  NRContact.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
// 

import SwiftUI
import Combine
import CoreData

class NRContact: ObservableObject, Identifiable, Hashable, IdentifiableDestination {
    
    static func == (lhs: NRContact, rhs: NRContact) -> Bool {
        lhs.pubkey == rhs.pubkey
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pubkey)
    }
        
    var id:String { pubkey }
    let pubkey:String

    var anyName:String
    var fixedName:String?
    var display_name:String?
    var name:String?
    var pictureUrl:URL?
    var banner:String?
    var about:String?
    @Published var couldBeImposter:Int16 = -1 // -1: unchecked, 0:false 1:true
    
    var nip05verified:Bool
    var nip05:String?
    var nip05nameOnly:String
    var metaDataCreatedAt:Date
    var metadata_created_at:Int64
    
    var anyLud = false
    var lud06:String?
    var lud16:String?
    
    var following:Bool = false
    var privateFollow:Bool = false
    var zapperPubkey: String?
    var zapState: ZapState?
    
    var contact: Contact? // Only touch this in BG context!!!
    
    var randomColor: Color

    init(contact: Contact, following:Bool? = nil) {
        self.contact = contact
        self.pubkey = contact.pubkey
        self.randomColor = Nostur.randomColor(seed: contact.pubkey)
        self.anyName = contact.anyName
        self.fixedName = contact.fixedName
        self.display_name = contact.display_name
        self.name = contact.name
        self.pictureUrl = if let picture = contact.picture {
            URL(string: picture)
        }
        else {
            nil
        }
        self.banner = contact.banner
        self.about = contact.about
        self.couldBeImposter = (following ?? false) ? 0 : contact.couldBeImposter
        
        self.nip05verified = contact.nip05veried
        self.nip05 = contact.nip05
        self.nip05nameOnly = contact.nip05nameOnly
        self.metaDataCreatedAt = Date(timeIntervalSince1970: TimeInterval(contact.metadata_created_at))
        self.metadata_created_at = contact.metadata_created_at
        
        self.anyLud = contact.anyLud
        self.lud06 = contact.lud06
        self.lud16 = contact.lud16
        self.zapperPubkey = contact.zapperPubkey
        
        self.following = isFollowing(contact.pubkey)
        self.privateFollow = contact.isPrivateFollow
        self.zapState = contact.zapState
        
        listenForChanges()
        isFollowingListener()
        listenForNip05()
    }
    
    private func isFollowingListener() {
        receiveNotification(.followersChanged) // includes followed but blocked keys
            .subscribe(on: DispatchQueue.global())
            .sink { [weak self] notification in
                guard let self = self else { return }
                let followingPubkeys = notification.object as! Set<String>
                let isFollowing = followingPubkeys.contains(self.pubkey)
                if isFollowing != self.following {
                    DispatchQueue.main.async { [weak self] in
                        self?.objectWillChange.send()
                        self?.following = isFollowing
                        if (isFollowing) {
                            self?.couldBeImposter = 0
                        }
                    }
                }
            }
            .store(in: &subscriptions)
        
//        receiveNotification(.activeAccountChanged)
//            .subscribe(on: DispatchQueue.global())
//            .sink { [weak self] _ in
//                bg().perform {
//                    guard let self = self else { return }
//                    let isFollowing = NRState.shared.loggedInAccount?.followingPublicKeys.contains(self.pubkey) ?? false
//                    if isFollowing != self.following {
//                        DispatchQueue.main.async {
//                            self.objectWillChange.send()
//                            self.following = isFollowing
//                            if (isFollowing) {
//                                self.couldBeImposter = 0
//                            }
//                        }
//                    }
//                }
//            }
//            .store(in: &subscriptions)
    }
    
    var subscriptions = Set<AnyCancellable>()
    
    private func listenForNip05() {
        let pubkey = self.pubkey
        ViewUpdates.shared.nip05updated
            .subscribe(on: DispatchQueue.global())
            .filter { $0.pubkey == pubkey }
            .sink { [weak self] nip05update in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard nip05update.isVerified != self.nip05verified else { return }
                    self.objectWillChange.send()
                    self.nip05verified = nip05update.isVerified
                    self.nip05 = nip05update.nip05
                    self.nip05nameOnly = nip05update.nameOnly
                }
            }
            .store(in: &subscriptions)
    }
    
    private func listenForChanges() {
        let pubkey = self.pubkey
        ViewUpdates.shared.contactUpdated
            .subscribe(on: DispatchQueue.global())
            .filter { $0.pubkey == pubkey }
            .sink { [weak self] contact in
                bg().perform {
                    guard let self = self else { return }
                    let anyName = contact.anyName
                    let fixedName = contact.fixedName
                    let display_name = contact.display_name
                    let name = contact.name
                    let pictureUrl:URL? = if let picture = contact.picture {
                        URL(string: picture)
                    }
                    else {
                        nil
                    }
                    let banner = contact.banner
                    let about = contact.about
                    let couldBeImposter = contact.couldBeImposter
                    
                    let nip05verified = contact.nip05veried
                    let nip05 = contact.nip05
                    let nip05nameOnly = contact.nip05nameOnly
                    let metaDataCreatedAt = Date(timeIntervalSince1970: TimeInterval(contact.metadata_created_at))
                    let metadata_created_at = contact.metadata_created_at
                    
                    let anyLud = contact.anyLud
                    let lud06 = contact.lud06
                    let lud16 = contact.lud16
                    let zapperPubkey = contact.zapperPubkey
//                    let zapState = contact.zapState
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        
                        self.objectWillChange.send()
                        
                        self.anyName = anyName
                        self.fixedName = fixedName
                        self.display_name = display_name
                        self.name = name
                        self.pictureUrl = pictureUrl
                        self.banner = banner
                        self.about = about
                        self.couldBeImposter = couldBeImposter
                        
                        self.nip05verified = nip05verified
                        self.nip05 = nip05
                        self.nip05nameOnly = nip05nameOnly
                        self.metaDataCreatedAt = metaDataCreatedAt
                        self.metadata_created_at = metadata_created_at
                        
                        self.anyLud = anyLud
                        self.lud06 = lud06
                        self.lud16 = lud16
                        self.zapperPubkey = zapperPubkey
//                        self.zappableAttributes.zapState = zapState
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    var mainContact: Contact? {
        guard let contact = self.contact else { return nil }
        return DataProvider.shared().viewContext.object(with: contact.objectID) as? Contact
    }
    
    @MainActor public func setFixedName(_ name:String) {
        guard name != self.fixedName else { return }
        self.objectWillChange.send()
        self.fixedName = name
        bg().perform { [weak self] in
            self?.contact?.fixedName = name
        }
    }
    
    @MainActor public func follow(privateFollow: Bool = false) {
        self.objectWillChange.send()
        self.following = true
        self.couldBeImposter = 0
        self.privateFollow = privateFollow
        
        bg().perform { [weak self] in
            guard let self else { return }
            guard let account = account() else { return }
            self.contact?.isPrivateFollow = privateFollow
            self.contact?.couldBeImposter = 0
            account.followingPubkeys.insert(self.pubkey)
            DataProvider.shared().bgSave()
            account.publishNewContactList()
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                NRState.shared.loggedInAccount?.reloadFollows()
                sendNotification(.followingAdded, self.pubkey)
            }
        }
    }
    
    @MainActor public func unfollow() {
        self.objectWillChange.send()
        self.following = false
        self.privateFollow = false
        
        bg().perform { [weak self] in
            guard let self else { return }
            guard let account = account() else { return }
            self.contact?.isPrivateFollow = false
            account.followingPubkeys.remove(self.pubkey)
            DataProvider.shared().bgSave()
            account.publishNewContactList()
            
            DispatchQueue.main.async {
                NRState.shared.loggedInAccount?.reloadFollows()
            }
        }
    }
    
    static func fetch(_ pubkey: String, context:NSManagedObjectContext) -> NRContact? {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        guard let contact = Contact.fetchByPubkey(pubkey, context: context) else {
            return nil
        }
        return NRContact(contact: contact, following: isFollowing(pubkey))
    }
}
