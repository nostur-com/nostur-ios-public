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

    public let pubkey: String

    // FOR VIEW
    @Published var anyName: String
    @Published var fixedName: String?
    @Published var pictureUrl: URL?
    @Published var fixedPfpURL: URL?
    @Published var npub: String?
    @Published var banner: String?
    @Published var about: String?
    @Published var couldBeImposter: Int16 = -1 // -1: unchecked, 0:false 1:true
    @Published var similarToPubkey: String? 
    
    @Published var nip05verified: Bool = false
    
    // Internal state
    private var didRunImposterCheck: Bool = false
    
    public var nip05: String?
    public var nip05nameOnly: String?
    public var metadata_created_at: Int64 = 0
    
    @Published var anyLud = false
    public var lud06: String?
    public var lud16: String?
    
    public var zapperPubkeys: Set<String> = [] {
        didSet {
            if Thread.isMainThread {
                bg().perform {
                    withContact(pubkey: self.pubkey) { [self] contact in
                        contact.zapperPubkeys = zapperPubkeys
                    }
                }
            }
            else {
                withContact(pubkey: self.pubkey) { [self] contact in
                    contact.zapperPubkeys = zapperPubkeys
                }
            }
        }
    }
    @Published var zapState: ZapState?
    
    public var randomColor: Color = Color.gray

    private init(pubkey: String, contact: Contact? = nil) {
        self.pubkey = pubkey
        self.anyName = String(pubkey.suffix(11))
        configure(pubkey: pubkey, contact: contact)
    }
    


    private func listenForNip05() {
        nip05Subscription = ViewUpdates.shared.nip05updated
            .filter { $0.pubkey == self.pubkey }
            .receive(on: RunLoop.main)
            .sink { [weak self] nip05update in
                guard let self else { return }
                guard nip05update.isVerified != self.nip05verified else { return }
                self.nip05verified = nip05update.isVerified
                self.nip05 = nip05update.nip05
                self.nip05nameOnly = nip05update.nameOnly
            }
    }
    
    private func listenForChanges() {
        profileUpdateSubscription = ViewUpdates.shared.profileUpdates
            .filter { $0.pubkey == self.pubkey }
            .receive(on: RunLoop.main)
            .sink { [weak self] profileInfo in
                guard let self else { return }
                configureFromProfileUpdate(profileInfo)
            }
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
    
    private func configureFromProfileUpdate(_ profileInfo: ProfileInfo, animate: Bool = false) {
        if animate {
            withAnimation {
                self.anyName = profileInfo.anyName ?? String(pubkey.suffix(11))
                self.pictureUrl = profileInfo.pfpUrl
            }
        }
        else {
            self.anyName = profileInfo.anyName ?? String(pubkey.suffix(11))
            self.pictureUrl = profileInfo.pfpUrl
        }
        self.fixedName = profileInfo.fixedName
        self.fixedPfpURL = profileInfo.fixedPfpUrl
        
        self.banner = profileInfo.banner
        self.about = profileInfo.about
        self.couldBeImposter = profileInfo.couldBeImposter
        self.similarToPubkey = profileInfo.couldBeImposter == 1 ? profileInfo.similarToPubkey : nil
        
        self.nip05verified = profileInfo.nip05verified
        self.nip05 = profileInfo.nip05
        self.nip05nameOnly = Nostur.nip05nameOnly(nip05veried: profileInfo.nip05verified, nip05: profileInfo.nip05)

        self.metadata_created_at = profileInfo.metadata_created_at
        
        self.anyLud = profileInfo.anyLud
        self.lud06 = profileInfo.lud06
        self.lud16 = profileInfo.lud16
        self.zapperPubkeys = profileInfo.zapperPubkeys
    }
    
    private func configureFromBgContact(_ bgContact: Contact, animate: Bool = false) {
        self.configureFromProfileUpdate(profileInfo(bgContact), animate: animate)
    }
    
    private func configure(pubkey: String, contact: Contact? = nil) {
        self.randomColor = Nostur.randomColor(seed: self.pubkey)
        
        if Thread.isMainThread {
            bg().perform { [weak self] in
                if let bgContact = (contact ?? Contact.fetchByPubkey(pubkey, context: bg())) {
                    self?.configureFromBgContact(bgContact)
                }
            }
        }
        else {
            if let bgContact = (contact ?? Contact.fetchByPubkey(pubkey, context: bg())) {
                configureFromBgContact(bgContact)
            }
        }
        
        listenForChanges()
        listenForNip05()
    }
    
    private var profileUpdateSubscription: AnyCancellable?
    private var nip05Subscription: AnyCancellable?
    
    func runImposterCheck() {
        guard !didRunImposterCheck && couldBeImposter == -1  else { return }
        self.didRunImposterCheck = true
        ImposterChecker.shared.runImposterCheck(nrContact: self) { imposterYes in
            Task { @MainActor in
                self.couldBeImposter = 1
                self.similarToPubkey = imposterYes.similarToPubkey
            }
        }
    }
    
    public var id: String { pubkey }
    
    static func == (lhs: NRContact, rhs: NRContact) -> Bool {
        lhs.pubkey == rhs.pubkey
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pubkey)
        hasher.combine(anyName)
        hasher.combine(pictureUrl)
        hasher.combine(couldBeImposter)
    }
}

extension NRContact {
    
    @MainActor public func setFixedName(_ name: String) {
        guard name != self.fixedName else { return }
        self.fixedName = name
        bg().perform {
            withContact(pubkey: self.pubkey) { contact in
                contact.fixedName = name
            }
        }
    }
    
    @MainActor public func follow(privateFollow: Bool = false, la laOrNil: LoggedInAccount? = nil) {
        self.couldBeImposter = 0
        self.similarToPubkey = nil
        
        guard let la = (laOrNil ?? AccountsState.shared.loggedInAccount) else { return }
        la.follow(pubkey, privateFollow: privateFollow)
    }
    
    @MainActor public func unfollow(_ laOrNil: LoggedInAccount? = nil) {
        guard let la = (laOrNil ?? AccountsState.shared.loggedInAccount) else { return }
        la.unfollow(pubkey)
    }
    
    
    @MainActor
    public func loadNpub() async {
        guard npub == nil else { return }
        npub = await Task.detached {
            try? NIP19(prefix: "npub", hexString: self.pubkey).displayString
        }.value
   }
}


extension NRContact {
    
    // Fetch EXISTING NRContact from cache, or create from passed contact, or create by fetching from DB first, or create new
    static func instance(of pubkey: String, contact: Contact? = nil) -> NRContact {
        
        // From cache
        if let cachedNRContact = Self.fetch(pubkey, contact: contact) {
            return cachedNRContact
        }
        
        // Create new instance and store in cache
        let nrContact = NRContact(pubkey: pubkey, contact: contact)
        NRContactCache.shared.setObject(for: pubkey, value: nrContact)
        return nrContact
    }
    
    
    // Fetch EXISTING NRContact from cache, or create from passed contact, or create by fetching from DB first (never create new)
    static func fetch(_ pubkey: String, contact: Contact? = nil) -> NRContact? {
        
        // From cache
        if let cachedNRContact = NRContactCache.shared.retrieveObject(at: pubkey) {
            return cachedNRContact
        }
        else if let contact { // From contact in param
            let nrContact = NRContact(pubkey: pubkey, contact: contact)
            NRContactCache.shared.setObject(for: pubkey, value: nrContact)
            return nrContact
        }
        else if Thread.isMainThread {
            let nrContact = NRContact(pubkey: pubkey, contact: contact)
            NRContactCache.shared.setObject(for: pubkey, value: nrContact)
            return nrContact
        }
        else if let contact = Contact.fetchByPubkey(pubkey, context: bg()) { // from DB
            let nrContact = NRContact(pubkey: pubkey, contact: contact)
            NRContactCache.shared.setObject(for: pubkey, value: nrContact)
            return nrContact
        }
        return nil
    }
}
