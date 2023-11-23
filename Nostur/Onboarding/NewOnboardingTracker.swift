//
//  NewOnboardingTracker.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/05/2023.
//

import Foundation
import Combine

class NewOnboardingTracker {
    
    static let shared = NewOnboardingTracker()
    
    private var guestAlreadyStarted = false
    
    // Who are we onboarding?
    private var pubkey:String?
    
    // Tasks backlog
    private var backlog = Backlog()
    private var subscriptions = Set<AnyCancellable>()
    
    // Completed tasks?
    private var fetchedOwnProfileTask = false { // Fetched own profile (KIND 0)
        didSet {
            DataProvider.shared().bgSave()
        }
    }
    private var fetchedFollowersTask = false { // Fetched followers (Ps in KIND 3)
        didSet {
            DataProvider.shared().bgSave()
        }
    }
    private var fetchedProfilesOfFollowersTask = false { // Fetched profiles of followers (KIND 0 of Ps in OWN KIND 3)
        didSet {
            DataProvider.shared().bgSave()
            if fetchedProfilesOfFollowersTask {
                self.stopAfterDelay() // If we reached here we have completed the onboarding.
            }
        }
    }
    
    private var bg = DataProvider.shared().bg
    private var account:CloudAccount?
    
    public var isOnboarding:Bool {
        account != nil
    }

    public func start(pubkey: String) throws {
        if pubkey == GUEST_ACCOUNT_PUBKEY {
            if guestAlreadyStarted { return }
            guestAlreadyStarted = true
        }
        self.bg.performAndWait { [weak self] in
            self?.cancel()
        }
        self.backlog = Backlog()
        self.pubkey = pubkey
        
        Importer.shared.importedMessagesFromSubscriptionIds
            .sink { [weak self] subscriptionIds in
            guard let self = self else { return }

            let reqTasks = self.backlog.tasks(with: subscriptionIds)
            reqTasks.forEach { task in
                task.process()
            }
        }
        .store(in: &subscriptions)
        
        L.onboarding.info("✈️✈️ OnboardingTracker.start(\(pubkey.short))")
        try self.bg.performAndWait {
            if let account = try? CloudAccount.fetchAccount(publicKey: pubkey, context: self.bg) {
                self.account = account
            }
            else {
                throw "No account in database"
            }
        }
        self.fetchedOwnProfileTask = false
        self.fetchedFollowersTask = false
        self.fetchedProfilesOfFollowersTask = false
        self.fetchProfileAndFollowers()
    }
    
    private func stopAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(10)) {
            if let account = Nostur.account(), !NRState.shared.activeAccountPublicKey.isEmpty && account.publicKey == NRState.shared.activeAccountPublicKey {
                WebOfTrust.shared.loadWoT()
            }
            self.bg.perform { [weak self] in
                self?.cancel()
            }
        }
    }
    
    public func abort() {
        self.backlog = Backlog()
        self.account = nil
    }
    
    private func cancel() {
        guard self.account != nil else { return }
        L.onboarding.info("✈️✈️✈️✈️✈️✈️ ONBOARDING COMPLETED/CANCELLED \(String(describing: self.account?.getFollowingPublicKeys(includeBlocked: true).count) ) followers for \(self.account?.name ?? "") \(self.account?.display_name ?? "")")
        self.account = nil
    }
    
    private func fetchProfileAndFollowers() {
        guard let pubkey = self.pubkey else { return }
//        guard let account = self.account else { return }
        
        // We maybe already have kind 0/3
        self.bg.performAndWait {
            self.processKind0()
        }
        
        // We maybe already have kind 0/3
        self.bg.performAndWait {
            self.processKind3()
        }
        
        let fetchProfileAndFollowersTask = ReqTask(
            prefix: "FPF-",
            reqCommand: { (taskId) in
                L.onboarding.info("\(taskId) ✈️✈️ fetchProfileAndFollowersTask.reqCommand()")
                guard self.fetchedOwnProfileTask == false && self.fetchedFollowersTask == false else {
                    L.onboarding.info("\(taskId) ✈️✈️ SKIPPED - ALREADY HAVE BOTH")
                    return
                }

                req(RM.getUserMetadataAndContactList(pubkey: pubkey, subscriptionId: taskId))
            },
            processResponseCommand: { [weak self] (taskId, _, _) in
                guard let self = self else { return }
                L.onboarding.info("\(taskId) ✈️✈️ fetchProfileAndFollowersTask.processResponseCommand()")
                self.bg.perform { [weak self] in
                    guard let self = self else { return }
                    if !self.fetchedOwnProfileTask {
                        self.processKind0()
                    }
                }
                
                self.bg.perform { [weak self] in
                    guard let self = self else { return }
                    if !self.fetchedFollowersTask {
                        self.processKind3()
                    }
                }
            })

        guard self.fetchedOwnProfileTask == false && self.fetchedFollowersTask == false else {
            self.account = nil
            return
        }
        backlog.add(fetchProfileAndFollowersTask)
        fetchProfileAndFollowersTask.fetch()
    }
    
    public var didFetchKind3 = PassthroughSubject<Event, Never>()
    
    private func processKind3() {
        L.onboarding.info("✈️✈️ processing kind 3")
        guard let pubkey = self.pubkey else { return }
        guard let account = self.account else { return }
        if let kind3 = Event.fetchReplacableEvent(3, pubkey: pubkey, context: self.bg) {
            didFetchKind3.send(kind3)
            let pTags = kind3.fastPs.map { $0.1 }
            let existingAndCreatedContacts = self.createContactsFromPs(pTags, isOwnAccount: account.privateKey != nil)
            account.followingPubkeys.formUnion(Set(existingAndCreatedContacts.map { $0.pubkey }))
            let followingPublicKeys = account.getFollowingPublicKeys(includeBlocked: true)
            
            let tTags = kind3.fastTs.map { $0.1 }
            for tag in tTags {
                account.followingHashtags.insert(tag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
            }
            
            DataProvider.shared().bgSave()
            NRState.shared.loggedInAccount?.reloadFollows()
            
            DispatchQueue.main.async {
                if NRState.shared.activeAccountPublicKey == pubkey {
                    sendNotification(.followersChanged, followingPublicKeys)
                }
            }
            self.fetchedFollowersTask = true
            
            self.createRelaysFromKind3Content(kind3.content ?? "")
            L.onboarding.info("✈️✈️ created relays from kind 3")
            
            L.onboarding.info("✈️✈️ processed kind 3")
            self.fetchProfilesOfFollowers(pTags)
        }
        else {
            L.onboarding.info("✈️✈️ kind 3 not found. ")
        }
    }
    
    private func processKind0() {
        guard let pubkey = self.pubkey else { return }
        if let kind0 = Event.fetchReplacableEvent(0, pubkey: pubkey, context: self.bg) {
            
            self.preloadAccountInfo(kind0)
            
            self.fetchedOwnProfileTask = true
        }
    }
    
    private func preloadAccountInfo(_ kind0:Event) {
        guard let content = kind0.content else { return }
        guard let account = self.account else { return }
        
        let decoder = JSONDecoder()
        
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: content.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }

        account.objectWillChange.send()
//        account.display_name = metaData.display_name ?? ""
        account.name = metaData.name ?? ""
        account.about = metaData.about ?? ""
        account.picture = metaData.picture ?? ""
        account.banner = metaData.banner ?? ""
        account.nip05 = metaData.nip05 ?? ""
        account.lud16 = metaData.lud16 ?? ""
        account.lud06 = metaData.lud06 ?? ""
        L.onboarding.info("✈️✈️ Preloaded account info")
    }
    
    private func fetchProfilesOfFollowers(_ pTags:[String]) {
        guard !self.fetchedProfilesOfFollowersTask else { return }
        let fetchProfilesOfFollowersTask = ReqTask(
            prefix: "FPoF-",
            reqCommand: { (taskId) in
                L.onboarding.info("\(taskId) ✈️✈️ fetchProfilesOfFollowersTask.reqCommand()")
                req(RM.getUserMetadata(pubkeys: pTags, subscriptionId: taskId))
            },
            processResponseCommand: { [weak self] (taskId, _, _) in
                guard let self = self else { return }
                L.onboarding.info("\(taskId) ✈️✈️ fetchProfilesOfFollowersTask.processResponseCommand()")
                self.fetchedProfilesOfFollowersTask = true
            })
        backlog.add(fetchProfilesOfFollowersTask)
        fetchProfilesOfFollowersTask.fetch()
    }
    
    private func createContactsFromPs(_ pTags:[String], isOwnAccount: Bool = false) -> [Contact] {
        var existingAndCreatedContacts = [Contact]()
        for pTag in pTags {
            let contact = Contact.fetchByPubkey(pTag, context: self.bg)
            guard contact == nil else {
                // Skip if we already have a contact
                existingAndCreatedContacts.append(contact!)
                continue
            }
            // Else create a new one
            let newContact = Contact(context: self.bg)
            newContact.pubkey = pTag
            newContact.metadata_created_at = 0
            newContact.updated_at = 0
            newContact.couldBeImposter = isOwnAccount ? 0 : -1 // If we are already following from own account, mark as NOT imposter
            existingAndCreatedContacts.append(newContact)
        }
        return existingAndCreatedContacts
    }
    
    private func createRelaysFromKind3Content(_ content:String) {
        guard let pubkey = self.pubkey else { return }
        // Load existing relays if found in .content
        if !content.isEmpty, let contentData = content.data(using: .utf8), AccountManager.shared.hasPrivateKey(pubkey: pubkey) {
            do {
                let decoder = JSONDecoder()
                let relays = try decoder.decode(Kind3Relays.self, from: contentData)
                if !relays.relays.isEmpty {
                    L.onboarding.info("✈️✈️✈️ found \(relays.relays.count) existing relays")
                }
                relays.relays.forEach { relay in
                    let fr = CloudRelay.fetchRequest()
                    if relay.url.suffix(1) == "/" {
                        let relayWithoutSlash = String(relay.url.dropLast(1))
                        fr.predicate = NSPredicate(format: "url == %@ OR url == %@", relay.url.lowercased(), relayWithoutSlash.lowercased())
                    }
                    else {
                        let relayWithSlash = relay.url + "/"
                        fr.predicate = NSPredicate(format: "url == %@ OR url == %@", relay.url.lowercased(), relayWithSlash.lowercased())
                    }
                    L.onboarding.info("✈️✈️✈️ adding \(relay.url) ")
                    if let existingRelay = try? self.bg.fetch(fr).first {
                        existingRelay.read = relay.readWrite.read ?? false
                        existingRelay.write = relay.readWrite.write ?? false
                    }
                    else {
                        let newRelay = CloudRelay(context: self.bg)
                        newRelay.url_ = relay.url.lowercased()
                        newRelay.read = relay.readWrite.read ?? false
                        newRelay.write = relay.readWrite.write ?? false
                        newRelay.createdAt = Date()
                    }
                }
            } catch {
                L.og.error("Error decoding JSON: \(error)")
            }
        }
    }
}
