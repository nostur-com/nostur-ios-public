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
        hasher.combine(anyName)
        hasher.combine(pictureUrl)
        hasher.combine(couldBeImposter)
    }
        
    var id: String { pubkey }
    let pubkey: String

    @Published var anyName: String
    var fixedName:String?
    var fixedPfp:String?
    var display_name:String?
    var name:String?
    @Published var pictureUrl: URL?
    var banner:String?
    var about:String?
    @Published var couldBeImposter: Int16 = -1 // -1: unchecked, 0:false 1:true
    @Published var similarToPubkey: String? 
    
    var nip05verified:Bool
    var nip05:String?
    var nip05nameOnly:String
    var metaDataCreatedAt:Date
    var metadata_created_at:Int64
    
    @Published var anyLud = false
    var lud06:String?
    var lud16:String?
    
    var zapperPubkeys: Set<String> = []
    var zapState: ZapState?
    
    var contact: Contact? // Only touch this in BG context!!!
    
    var randomColor: Color
    
    var npub: String {
        try! NIP19(prefix: "npub", hexString: pubkey).displayString
    }

    init(pubkey: String, contact: Contact? = nil) {
        shouldBeBg()

        self.contact = contact
        self.pubkey = contact?.pubkey ?? pubkey
        self.randomColor = Nostur.randomColor(seed: contact?.pubkey ?? pubkey)
        self.anyName = contact?.anyName ?? "..."
        self.fixedName = contact?.fixedName
        self.fixedPfp = contact?.fixedPfp
        self.display_name = contact?.display_name
        self.name = contact?.name
        self.pictureUrl = if let picture = contact?.picture {
            URL(string: picture)
        }
        else {
            nil
        }
        self.banner = contact?.banner
        self.about = contact?.about
        self.couldBeImposter = contact?.couldBeImposter ?? -1
        self.similarToPubkey = (contact?.couldBeImposter ?? -1 == 1) ? contact?.similarToPubkey : nil
        
        self.nip05verified = contact?.nip05veried ?? false
        self.nip05 = contact?.nip05
        self.nip05nameOnly = contact?.nip05nameOnly ?? ""
        self.metaDataCreatedAt = Date(timeIntervalSince1970: TimeInterval(contact?.metadata_created_at ?? 0))
        self.metadata_created_at = contact?.metadata_created_at ?? 0
        
        self.anyLud = contact?.anyLud ?? false
        self.lud06 = contact?.lud06
        self.lud16 = contact?.lud16
        self.zapperPubkeys = contact?.zapperPubkeys ?? []
        self.zapState = contact?.zapState
        
        listenForChanges()
        listenForNip05()
    }
    
    var subscriptions = Set<AnyCancellable>()
    
    private func listenForNip05() {
        let pubkey = self.pubkey
        ViewUpdates.shared.nip05updated
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .filter { $0.pubkey == pubkey }
            .sink { [weak self] nip05update in
                DispatchQueue.main.async { [weak self] in
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
            .receive(on: DispatchQueue.global())
            .filter { $0.0 == pubkey }
            .sink { [weak self] (_, contact) in
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    let anyName = contact.anyName
                    let fixedName = contact.fixedName
                    let fixedPfp = contact.fixedPfp
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
                    let similarToPubkey = contact.couldBeImposter == 1 ? contact.similarToPubkey : nil
                    
                    let nip05verified = contact.nip05veried
                    let nip05 = contact.nip05
                    let nip05nameOnly = contact.nip05nameOnly
                    let metaDataCreatedAt = Date(timeIntervalSince1970: TimeInterval(contact.metadata_created_at))
                    let metadata_created_at = contact.metadata_created_at
                    
                    let anyLud = contact.anyLud
                    let lud06 = contact.lud06
                    let lud16 = contact.lud16
                    let zapperPubkeys = contact.zapperPubkeys
//                    let zapState = contact.zapState
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        
//                        self.objectWillChange.send()
                        
                        withAnimation {
                            self.anyName = anyName
                            self.pictureUrl = pictureUrl
                        }
                        self.fixedName = fixedName
                        self.fixedPfp = fixedPfp
                        self.display_name = display_name
                        self.name = name
                        
                        self.banner = banner
                        self.about = about
                        self.couldBeImposter = couldBeImposter
                        self.similarToPubkey = similarToPubkey
                        
                        self.nip05verified = nip05verified
                        self.nip05 = nip05
                        self.nip05nameOnly = nip05nameOnly
                        self.metaDataCreatedAt = metaDataCreatedAt
                        // Data race in Nostur.NRContact.metadata_created_at.setter : Swift.Int64 at 0x12cb91380 (Thread 1)
                        self.metadata_created_at = metadata_created_at
                        
                        self.anyLud = anyLud
                        self.lud06 = lud06
                        self.lud16 = lud16
                        self.zapperPubkeys = zapperPubkeys
//                        self.zappableAttributes.zapState = zapState
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    @MainActor public func setFixedName(_ name: String) {
        guard name != self.fixedName else { return }
        self.objectWillChange.send()
        self.fixedName = name
        bg().perform { [weak self] in
            self?.contact?.fixedName = name
        }
    }
    
    @MainActor public func setFixedPfp(_ url: String) {
        guard url != self.fixedPfp else { return }
        self.objectWillChange.send()
        self.fixedPfp = url
        bg().perform { [weak self] in
            self?.contact?.fixedPfp = url
        }
    }
    
    @MainActor public func follow(privateFollow: Bool = false, la laOrNil: LoggedInAccount? = nil) {
        self.objectWillChange.send()
        self.couldBeImposter = 0
        self.similarToPubkey = nil
        
        guard let la = (laOrNil ?? AccountsState.shared.loggedInAccount) else { return }
        la.follow(pubkey, privateFollow: privateFollow)
    }
    
    @MainActor public func unfollow(_ laOrNil: LoggedInAccount? = nil) {
        self.objectWillChange.send()
        guard let la = (laOrNil ?? AccountsState.shared.loggedInAccount) else { return }
        la.unfollow(pubkey)
    }
    
    // Live events/activities/nests
    
    // if ["hand", "1"] tag is present in room presence event
    @Published public var raisedHand = false
    private var presenceATag: String?
    private var presenceSubscription: AnyCancellable?
    public var presenceTimestamp: Int? = nil
    
    public func listenForPresence(_ aTag: String) {
        self.presenceATag = aTag
        guard presenceSubscription == nil else { return }
        presenceSubscription = receiveNotification(.receivedMessage)
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .sink { [weak self] notification in
                guard let self = self else { return }
                let message = notification.object as! RelayMessage
                guard let event = message.event else { return }
                guard event.kind == .custom(10312) else { return }
                
                let ago = Int(Date().timeIntervalSince1970 - 120) // 2 min ago?
                guard event.createdAt.timestamp > ago else { return }
                
                
                guard event.publicKey == self.pubkey else { return }
                guard event.tags.first(where: { $0.type == "a" && $0.value == self.presenceATag }) != nil else { return }
                
                self.presenceTimestamp = event.createdAt.timestamp
                
                let raisedHand = event.tags.first(where: { $0.type == "hand" && $0.value == "1" }) != nil
                
                if raisedHand != self.raisedHand {
                    DispatchQueue.main.async { [weak self] in
                        self?.objectWillChange.send()
                        self?.raisedHand = raisedHand
                    }
                }
            }
    }
    
    @Published public var volume: CGFloat = 0.0
    @Published public var isMuted: Bool = true
}


extension NRContact {
    
    // Fetch from cache, or create from passed contact, or create by fetching from DB first
    static func fetch(_ pubkey: String, contact: Contact? = nil, context: NSManagedObjectContext? = nil) -> NRContact? {
        
        // From cache
        if let cachedNRContact = NRContactCache.shared.retrieveObject(at: pubkey) {
            return cachedNRContact
        }
        else if let contact { // From contact in param
            let nrContact = NRContact(pubkey: pubkey, contact: contact)
            NRContactCache.shared.setObject(for: pubkey, value: nrContact)
            return nrContact
        }
        else if let contact = Contact.fetchByPubkey(pubkey, context: context ?? bg()) { // from DB
            let nrContact = NRContact(pubkey: pubkey, contact: contact)
            NRContactCache.shared.setObject(for: pubkey, value: nrContact)
            return nrContact
        }
        return nil
    }
}
