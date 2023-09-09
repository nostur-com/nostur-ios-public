//
//  NosturState.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/01/2023.
//

import SwiftUI
import Foundation
import CoreData
import Combine

final class NosturState : ObservableObject {
    
    public static let shared = NosturState()
    
    public var wot:WebOfTrust?
    public var backlog = Backlog(timeout: 60.0, auto: true)
    public var nsecBunker:NSecBunkerManager?
    
    public var nrPostQueue = DispatchQueue(label: "com.nostur.nrPostQueue", attributes: .concurrent)
    
    let agoTimer = Timer.publish(every: 60, tolerance: 15.0, on: .main, in: .default).autoconnect()

    
    static let GUEST_ACCOUNT_PUBKEY = "c118d1b814a64266730e75f6c11c5ffa96d0681bfea594d564b43f3097813844"
    static let EXPLORER_PUBKEY = "afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320"
    @Published var onBoardingIsShown = false {
        didSet {
            sendNotification(.onBoardingIsShownChanged, onBoardingIsShown)
        }
    }
    
    var mutedWords:[String] = [] {
        didSet {
            sendNotification(.mutedWordsChanged, mutedWords)
        }
    }

    var _followingPublicKeys:Set<String> { // computed and needs (account MoC) self + following - blocked
        get {
            guard let account = account else { return Set<String>()}
            
            let withSelfIncluded = Set([account.publicKey] + account.follows_.map { $0.pubkey })
            let withoutBlocked = withSelfIncluded.subtracting(Set(account.blockedPubkeys_))
            
            return withoutBlocked
        }
    }
    
    var followingPublicKeys:Set<String> = [] { // does not mess with MoC
        didSet {
            self.bgFollowingPublicKeys = followingPublicKeys
        }
    }
    
    var bgFollowingPFPs:[String: URL] = [:]
    private func loadFollowingPFPs() {
        guard let account = account else { return }
        
        let followingPFPs:[String: URL] = Dictionary(grouping: account.follows_) { contact in
            contact.pubkey
        }
        .compactMapValues({ contacts in
            guard let picture = contacts.first?.picture else { return nil }
            guard picture.prefix(7) != "http://" else { return nil }
            return URL(string: picture)
        })
        
        bg().perform {
            self.bgFollowingPFPs = followingPFPs
        }
    }
    
    var bgFollowingPublicKeys:Set<String> = []
    
    var explorePubkeys:Set<String> {
        get {
            if account == nil { return rawExplorePubkeys }
            
            let withSelfIncluded = Set([account!.publicKey] + rawExplorePubkeys)
            let withoutBlocked = withSelfIncluded.subtracting(Set(account!.blockedPubkeys_))
            
            return withoutBlocked
        }
    }
    
    var subscriptions = Set<AnyCancellable>()

    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @Published var account:Account? = nil {
        didSet {
            if let account {
                bg().perform {
                    self.bgAccount = bg().object(with: account.objectID) as? Account
                    self.bgAccountKeys = Set(Account.fetchAccounts(context: bg()).map { $0.publicKey })
                }
            }
            else {
                bgAccount = nil
            }
        }
    }
    var bgAccount:Account?
    var bgAccountKeys:Set<String> = []
    @Published var readOnlyAccountSheetShown:Bool = false
    @Published var rawExplorePubkeys:Set<String> = []
    
    var pubkey:String? {
        get { account?.publicKey }
    }
    
    private var accounts_:[Account] = [] // Cache for result of Account.fetchRequest()
    var accounts:[Account] {
        get {
            if !accounts_.isEmpty {
                return self.accounts_
            }
            self.loadAccounts()
            return self.accounts_
        }
    }
    public func loadAccounts() {
        let r = Account.fetchRequest()
        self.accounts_ = (try? viewContext.fetch(r) ) ?? []
        self.bgAccountKeys = Set(accounts_.map { $0.publicKey })
    }
    
    func setAccount(account:Account? = nil) {
        guard self.account != account else { return }
        var sendActiveAccountChangedNotification = true
        if let beforeAccount = self.account { // Save state for old account
            beforeAccount.lastNotificationReceivedAt = lastNotificationReceivedAt
            beforeAccount.lastProfileReceivedAt = lastProfileReceivedAt
        }
        else {
            sendActiveAccountChangedNotification = false
        }
        self.objectWillChange.send()
        self.account = account
        if let account {
            activeAccountPublicKey = account.publicKey
            // load state for new account
            followingPublicKeys = _followingPublicKeys
            self.loadFollowingPFPs()
            lastNotificationReceivedAt = account.lastNotificationReceivedAt
            lastProfileReceivedAt = account.lastProfileReceivedAt
            
            self.nsecBunker = account.isNC ? NSecBunkerManager(account) : nil
            
            // Remove currectly active "Following" subscriptions from connected sockets
            SocketPool.shared.removeActiveAccountSubscriptions()
            
            if sendActiveAccountChangedNotification {
                FollowingGuardian.shared.didReceiveContactListThisSession = false
                sendNotification(.activeAccountChanged, account)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NosturState.shared.loadWoT(account)
                if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
                    DirectMessageViewModel.default.load(pubkey: account.publicKey)
                }
                else {
                    DirectMessageViewModel.default.loadAfterWoT()
                }
            }
        }
    }
    
    public func loadWoT(_ account:Account? = nil) {
        guard let account = account ?? self.account else { L.og.error("🕸️🕸️ WebOfTrust: loadWoT. account = nil"); return }
        guard SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue else { return }
        
        let wotFollowingPubkeys = account.followingPublicKeys.subtracting(account.silentFollows) // We don't include silent follows in WoT
        
        let publicKey = account.publicKey
        DataProvider.shared().bg.perform { [weak self] in
            guard self?.wot?.pubkey != publicKey else { return }
            self?.wot = WebOfTrust(pubkey: publicKey, followingPubkeys: wotFollowingPubkeys)
            
            guard wotFollowingPubkeys.count > 10 else {
                DispatchQueue.main.async { sendNotification(.WoTReady, publicKey) }
                L.og.info("🕸️🕸️ WebOfTrust: Not enough follows to build WoT. Maybe still onboarding and contact list not received yet")
                return
            }
            
            switch SettingsStore.shared.webOfTrustLevel {
                case SettingsStore.WebOfTrustLevel.off.rawValue:
                    L.og.info("🕸️🕸️ WebOfTrust: Disabled")
                case SettingsStore.WebOfTrustLevel.normal.rawValue:
                    L.og.info("🕸️🕸️ WebOfTrust: Normal")
                    DataProvider.shared().bg.perform { [weak self] in
                        self?.wot?.loadNormal()
                    }
                case SettingsStore.WebOfTrustLevel.strict.rawValue:
                    L.og.info("🕸️🕸️ WebOfTrust: Strict")
                default:
                    L.og.info("🕸️🕸️ WebOfTrust: Disabled")
            }
        }
    }
    
    var lastNotificationReceivedAt:Date? // stored here so we dont have to worry about different object contexts / threads
    var lastProfileReceivedAt:Date? // stored here so we dont have to worry about different object contexts / threads
    var container:NSPersistentContainer
    var viewContext:NSManagedObjectContext
    
    init() {
        self.container = DataProvider.shared().container
        self.viewContext = self.container.viewContext
        self.loadAccounts()
        if (activeAccountPublicKey != "") {
            if let account = try? Account.fetchAccount(publicKey: activeAccountPublicKey, context: viewContext) {
                self.setAccount(account: account)
            }
        }
        initMutedWords()
        managePowerUsage()
    }
    
    func managePowerUsage() {
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }
    
    
    @objc func powerStateChanged(_ notification: Notification) {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            if SettingsStore.shared.animatedPFPenabled {
                SettingsStore.shared.objectWillChange.send() // This will reload views to stop playing animated PFP GIFs
            }
        }
    }
    
    func initMutedWords() {
        let fr = MutedWords.fetchRequest()
        fr.predicate = NSPredicate(format: "enabled == true")
        mutedWords = try! viewContext.fetch(fr)
            .map { $0.words }.compactMap { $0 }.filter { $0 != "" }
    }
    
//    func loadFollowing() {
//        if (account?.follows != nil) {
//            let pubkeys = account!.follows?.map { $0.pubkey } ?? []
////            print("💿 follows:")
////            print(pubkeys)
////            self.objectWillChange.send()
////            self.followingPublicKeys = Set( pubkeys )
//        }
//        else {
////            self.objectWillChange.send()
////            self.followingPublicKeys = Set([])
//        }
//    }
    
    func follow(_ pubkey:String) {
        guard let account = account else { return }
//        self.objectWillChange.send()
        // find existing contact
        if let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) {
            contact.couldBeImposter = 0
            account.addToFollows(contact)
        }
        else {
            // if nil, create new contact
            let contact = Contact(context: viewContext)
            contact.pubkey = pubkey
            contact.couldBeImposter = 0
            account.addToFollows(contact)
        }
        followingPublicKeys = _followingPublicKeys
        self.loadFollowingPFPs()
        sendNotification(.followersChanged, account.followingPublicKeys)
        sendNotification(.followingAdded, pubkey)
        self.publishNewContactList()
    }
    
    func follow(_ contact:Contact) {
        guard let account = account else { return }
//        self.objectWillChange.send()
        contact.couldBeImposter = 0
        account.addToFollows(contact)
        
        followingPublicKeys = _followingPublicKeys
        self.loadFollowingPFPs()
        sendNotification(.followersChanged, account.followingPublicKeys)
        sendNotification(.followingAdded, contact.pubkey)
        self.publishNewContactList()
    }
    
    func unfollow(_ pubkey: String) {
        guard let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) else {
            return
        }
        guard let account = account else { return }
//        self.objectWillChange.send()
        account.removeFromFollows(contact)
        followingPublicKeys = _followingPublicKeys
        self.loadFollowingPFPs()
        sendNotification(.followersChanged, account.followingPublicKeys)
        self.publishNewContactList()
    }
    
    func unfollow(_ contact:Contact) {
//        guard let contact = Contact.contactBy(pubkey: contact.pubkey, context: viewContext) else {
//            return
//        }
        guard let account = account else { return }
//        self.objectWillChange.send()
        account.removeFromFollows(contact)
        followingPublicKeys = _followingPublicKeys
        self.loadFollowingPFPs()
        sendNotification(.followersChanged, account.followingPublicKeys)
        self.publishNewContactList()
    }
    
    func publishNewContactList() {
        guard let clEvent = try? AccountManager.createContactListEvent(account: account!) else {
            L.og.error("🔴🔴 Could not create new clEvent")
            return
        }
        guard let account = account else { return }
        if account.isNC {
            nsecBunker?.requestSignature(forEvent: clEvent, whenSigned: { signedEvent in
                _ = Unpublisher.shared.publishLast(signedEvent, ofType: .contactList)
            })
        }
        else {
            _ = Unpublisher.shared.publishLast(clEvent, ofType: .contactList)
        }
    }
    
    func isFollowing(_ pubkey:String) -> Bool {
        return followingPublicKeys.contains(pubkey)
    }
    
    func isFollowing(_ contact:Contact) -> Bool {
        guard let account = account else { return false }
        return account.follows?.contains(contact) ?? false
    }    
    
    func addBookmark(_ nrPost:NRPost) {
        guard account != nil else { return }
        sendNotification(.postAction, PostActionNotification(type:.bookmark, eventId: nrPost.id, bookmarked: true))
        
        DataProvider.shared().bg.perform {
            guard let account = self.bgAccount else { return }
            account.addToBookmarks(nrPost.event)
            DataProvider.shared().bgSave()
        }
    }
    
    func removeBookmark(_ nrPost:NRPost) {
        guard account != nil else { return }
        sendNotification(.postAction, PostActionNotification(type:.bookmark, eventId: nrPost.id, bookmarked: false))
        DataProvider.shared().bg.perform {
            guard let account = self.bgAccount else { return }
            account.removeFromBookmarks(nrPost.event)
            DataProvider.shared().bgSave()
        }
    }
    
    func followsYou(_ contact:Contact) -> Bool {
        guard let clEvent = contact.clEvent else { return false }
        guard let account = account else { return false }
        return !clEvent.fastTags.filter { $0.0 == "p" && $0.1 == account.publicKey }.isEmpty
    }
    
    func muteConversation(_ nrPost:NRPost) {
        guard let account = account else { return }
        if let replyToRootId = nrPost.replyToRootId {
            account.mutedRootIds_ = account.mutedRootIds_ + [replyToRootId, nrPost.id]
            L.og.info("Muting \(replyToRootId)")
        }
        else if let replyToId = nrPost.replyToId {
            account.mutedRootIds_ = account.mutedRootIds_ + [replyToId, nrPost.id]
            L.og.info("Muting \(replyToId)")
        }
        else {
            account.mutedRootIds_ = account.mutedRootIds_ + [nrPost.id]
            L.og.info("Muting \(nrPost.id)")
        }
        do {
            try viewContext.save()
            sendNotification(.muteListUpdated)
        }
        catch {
            L.og.error("Could not save after muting thread \(error)")
        }
    }    
    
    func logout(_ account:Account) {
        if (account.privateKey != nil) {
            if account.isNC {
                NIP46SecretManager.shared.deleteSecret(account: account)
            }
            else {
                AccountManager.shared.deletePrivateKey(forPublicKeyHex: account.publicKey)
            }
        }
        if (accounts.isEmpty) {
            onBoardingIsShown = true
            sendNotification(.clearNavigation)
            setAccount(account: nil)
            viewContext.delete(account)
            self.loadAccounts()
        }
        else {
            viewContext.delete(account)
            self.loadAccounts()
            if account == self.account {
                setAccount(account: accounts.last)
            }
        }
        try! viewContext.save()
    }
    
    func report(_ event:Event, reportType:ReportType, note:String = "", includeProfile:Bool = false) -> NEvent? {
        guard account?.privateKey != nil else { readOnlyAccountSheetShown = true; return nil }
        guard let account = account else { return nil }
        
        let report = EventMessageBuilder.makeReportEvent(pubkey: event.pubkey, eventId: event.id, type: reportType, note: note, includeProfile: includeProfile)

        guard let signedEvent = try? account.signEvent(report) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    func reportContact(pubkey:String, reportType:ReportType, note:String = "") -> NEvent? {
        guard account?.privateKey != nil else { readOnlyAccountSheetShown = true; return nil }
        guard let account = account else { return nil }
        
        let report = EventMessageBuilder.makeReportContact(pubkey: pubkey, type: reportType, note: note)

        guard let signedEvent = try? account.signEvent(report) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    func deletePost(_ eventId:String) -> NEvent? {
        guard account?.privateKey != nil else { readOnlyAccountSheetShown = true; return nil }
        guard let account = account else { return nil }
        
        let deletion = EventMessageBuilder.makeDeleteEvent(eventId: eventId)

        guard let signedEvent = try? account.signEvent(deletion) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
}


final class ExchangeRateModel: ObservableObject {
    static public var shared = ExchangeRateModel()
    @Published var bitcoinPrice:Double = 0.0
}



let IS_IPAD = UIDevice.current.userInterfaceIdiom == .pad
let IS_CATALYST = ProcessInfo.processInfo.isMacCatalystApp
let IS_APPLE_TYRANNY = ((Bundle.main.infoDictionary?["NOSTUR_IS_DESKTOP"] as? String) ?? "NO") == "NO"
//let IS_MAC = ProcessInfo.processInfo.isiOSAppOnMac

