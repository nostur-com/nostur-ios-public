//
//  NRContact.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import Foundation
import Combine
import CoreData

class NRContact: ObservableObject, Identifiable, Hashable {
    
    public class ZappableAttributes: ObservableObject {
        
        @Published var isZapped = false
        
        var zapState:Contact.ZapState? = nil {
            didSet {
                guard zapState != nil else {
                    DispatchQueue.main.async {
                        self.isZapped = false
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.isZapped = [.initiated, .nwcConfirmed, .zapReceiptConfirmed].contains(self.zapState)
                }
            }
        }
        
        init(zapState: Contact.ZapState? = nil) {
            self.zapState = zapState
        }
    }
    
    var zappableAttributes:ZappableAttributes
    
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
    var hasPrivateNote = false
    
    let contact:Contact // Only touch this in BG context!!!

    init(contact: Contact, following:Bool? = nil) {
        self.contact = contact
        self.pubkey = contact.pubkey
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
        self.privateFollow = contact.privateFollow
        self.zappableAttributes = ZappableAttributes(zapState: contact.zapState)
        
        self.hasPrivateNote = _hasPrivateNote()
        
        listenForChanges()
        isFollowingListener()
        listenForNip05()
        listenForZapState()
    }
    
    private func _hasPrivateNote() -> Bool {
        if let account = account(), let notes = account.privateNotes {
            return notes.first(where: { $0.contact == self.contact }) != nil
        }
        return false
    }
    
    private func isFollowingListener() {
        receiveNotification(.followersChanged) // includes followed but blocked keys
            .subscribe(on: DispatchQueue.global())
            .sink { [weak self] notification in
                guard let self = self else { return }
                let followingPubkeys = notification.object as! Set<String>
                let isFollowing = followingPubkeys.contains(self.pubkey)
                if isFollowing != self.following {
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.following = isFollowing
                        if (isFollowing) {
                            self.couldBeImposter = 0
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
    
    private func listenForZapState() {
        self.contact.zapStateChanged
            .subscribe(on: DispatchQueue.global())
            .sink { [weak self] (zapState, _) in
                guard let self = self else { return }
                guard zapState != zappableAttributes.zapState else { return }
                zappableAttributes.zapState = zapState
            }
            .store(in: &subscriptions)
    }
    
    private func listenForNip05() {
        self.contact.nip05updated
            .subscribe(on: DispatchQueue.global())
            .sink { [weak self] (isVerified, nip05, name) in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    guard isVerified != self.nip05verified else { return }
                    self.objectWillChange.send()
                    self.nip05verified = isVerified
                    self.nip05 = nip05
                    self.nip05nameOnly = name
                }
            }
            .store(in: &subscriptions)
    }
    
    private func listenForChanges() {
        self.contact.contactUpdated
            .subscribe(on: DispatchQueue.global())
            .sink { [weak self] contact in
                guard let self = self else { return }
                
                bg().perform {
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
                    let zapState = contact.zapState
                    
                    DispatchQueue.main.async {
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
                        self.zappableAttributes.zapState = zapState
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    var mainContact:Contact {
        DataProvider.shared().viewContext.object(with: contact.objectID) as! Contact
    }
    
    @MainActor public func setFixedName(_ name:String) {
        guard name != self.fixedName else { return }
        self.objectWillChange.send()
        self.fixedName = name
        bg().perform {
            self.contact.fixedName = name
        }
    }
    
    @MainActor public func follow(privateFollow: Bool = false) {
        self.objectWillChange.send()
        self.following = true
        self.couldBeImposter = 0
        self.privateFollow = privateFollow
        
        bg().perform {
            guard let account = account() else { return }
            self.contact.privateFollow = privateFollow // TODO: need to fix for multi account
            self.contact.couldBeImposter = 0
            account.addToFollows(self.contact)
            DataProvider.shared().bgSave()
            account.publishNewContactList()
            
            DispatchQueue.main.async {
                NRState.shared.loggedInAccount?.reloadFollows()
                sendNotification(.followingAdded, self.pubkey)
            }
        }
    }
    
    @MainActor public func unfollow() {
        self.objectWillChange.send()
        self.following = false
        self.privateFollow = false
        
        bg().perform {
            guard let account = account() else { return }
            self.contact.privateFollow = false // TODO: need to fix for multi account
            account.removeFromFollows(self.contact)
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
