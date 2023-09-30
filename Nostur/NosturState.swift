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

//final class NosturState : ObservableObject {
//    
//    public static let shared = NosturState()
//    
////    public var wot:WebOfTrust?
////    public var backlog = Backlog(timeout: 60.0, auto: true)
////    public var nsecBunker:NSecBunkerManager?
//    
////    public var nrPostQueue = DispatchQueue(label: "com.nostur.nrPostQueue", attributes: .concurrent)
////    
////    let agoTimer = Timer.publish(every: 60, tolerance: 15.0, on: .main, in: .default).autoconnect()
//
//    
//    
////    @Published var onBoardingIsShown = false {
////        didSet {
////            sendNotification(.onBoardingIsShownChanged, onBoardingIsShown)
////        }
////    }
////    
////    var mutedWords:[String] = [] {
////        didSet {
////            sendNotification(.mutedWordsChanged, mutedWords)
////        }
////    }
//
////    var _followingPublicKeys:Set<String> { // computed and needs (account MoC) self + following - blocked
////        get {
////            guard let account = account else { return Set<String>()}
////            
////            let withSelfIncluded = Set([account.publicKey] + account.follows_.map { $0.pubkey })
////            let withoutBlocked = withSelfIncluded.subtracting(Set(account.blockedPubkeys_))
////            
////            return withoutBlocked
////        }
////    }
//    
////    var followingPublicKeys:Set<String> = [] { // does not mess with MoC
////        didSet {
////            self.bgFollowingPublicKeys = followingPublicKeys
////        }
////    }
//    
////    var bgFollowingPFPs:[String: URL] = [:]
////    public func loadFollowingPFPs() {
////        guard let account = account else { return }
////        
////        let followingPFPs:[String: URL] = Dictionary(grouping: account.follows_) { contact in
////            contact.pubkey
////        }
////        .compactMapValues({ contacts in
////            guard let picture = contacts.first?.picture else { return nil }
////            guard picture.prefix(7) != "http://" else { return nil }
////            return URL(string: picture)
////        })
////        
////        bg().perform {
////            self.bgFollowingPFPs = followingPFPs
////        }
////    }
//    
////    var bgFollowingPublicKeys:Set<String> = []
//    
//    
//    
////    var subscriptions = Set<AnyCancellable>()
////
////    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = "" {
////        didSet {
////            let activeAccountPublicKey = self.activeAccountPublicKey
////            bg().perform {
////                self.bgActiveAccountPublicKey = activeAccountPublicKey
////            }
////        }
////    }
//    
////    var bgActiveAccountPublicKey: String = ""
////    @Published var account:Account? = nil {
////        didSet {
////            if let account {
////                bg().perform {
////                    self.bgAccount = bg().object(with: account.objectID) as? Account
////                    let accounts = Account.fetchAccounts(context: bg())
////                    self.bgAccountKeys = Set(accounts.map { $0.publicKey })
////                    self.bgFullAccountKeys = Set(accounts.filter { $0.privateKey != nil }.map { $0.publicKey })
////                }
////            }
////            else {
////                bgAccount = nil
////            }
////        }
////    }
////    var bgAccount:Account?
////    var bgAccountKeys:Set<String> = []
////    var bgFullAccountKeys:Set<String> = []
////    @Published var readOnlyAccountSheetShown:Bool = false
////    @Published var rawExplorePubkeys:Set<String> = []
//    
////    private var accounts_:[Account] = [] // Cache for result of Account.fetchRequest()
////    var accounts:[Account] {
////        get {
////            if !accounts_.isEmpty {
////                return self.accounts_
////            }
////            self.loadAccounts()
////            return self.accounts_
////        }
////    }
////    public func loadAccounts() {
////        let r = Account.fetchRequest()
////        self.accounts_ = (try? viewContext.fetch(r) ) ?? []
////        self.bgAccountKeys = Set(accounts_.map { $0.publicKey })
////        self.bgFullAccountKeys = Set(accounts_.filter { $0.privateKey != nil }.map { $0.publicKey })
////    }
//    
//    func setAccount(account:Account? = nil) {
////        guard self.account != account else { return }
////        var sendActiveAccountChangedNotification = true
////        if let beforeAccount = self.account { // Save state for old account
////            beforeAccount.lastNotificationReceivedAt = lastNotificationReceivedAt
////            beforeAccount.lastProfileReceivedAt = lastProfileReceivedAt
////        }
////        else {
////            sendActiveAccountChangedNotification = false
////        }
////        self.objectWillChange.send()
////        self.account = account
//        if let account {
////            activeAccountPublicKey = account.publicKey
//            // load state for new account
////            followingPublicKeys = _followingPublicKeys
////            self.loadFollowingPFPs()
////            lastNotificationReceivedAt = account.lastNotificationReceivedAt
////            lastProfileReceivedAt = account.lastProfileReceivedAt
//            
////            self.nsecBunker = account.isNC ? NSecBunkerManager(account) : nil
//            
////            // Remove currectly active "Following" subscriptions from connected sockets
////            SocketPool.shared.removeActiveAccountSubscriptions()
////            
////            if sendActiveAccountChangedNotification {
////                FollowingGuardian.shared.didReceiveContactListThisSession = false
////                sendNotification(.activeAccountChanged, account)
////            }
//            
////            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
////                NosturState.shared.loadWoT(account)
////                if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
////                    DirectMessageViewModel.default.load(pubkey: account.publicKey)
////                }
////                else {
////                    DirectMessageViewModel.default.loadAfterWoT()
////                }
////            }
//        }
//    }
//    
//    
//    
////    var lastNotificationReceivedAt:Date? // stored here so we dont have to worry about different object contexts / threads
////    var lastProfileReceivedAt:Date? // stored here so we dont have to worry about different object contexts / threads
////    var container:NSPersistentContainer
////    var viewContext:NSManagedObjectContext
//    
////    init() {
////        self.container = DataProvider.shared().container
////        self.viewContext = self.container.viewContext
////        self.loadAccounts()
////        if (activeAccountPublicKey != "") {
////            if let account = try? Account.fetchAccount(publicKey: activeAccountPublicKey, context: viewContext) {
////                self.setAccount(account: account)
////            }
////        }
////        initMutedWords()
////        managePowerUsage()
////    }
//    
//    
//    
////    func initMutedWords() {
////        let fr = MutedWords.fetchRequest()
////        fr.predicate = NSPredicate(format: "enabled == true")
////        mutedWords = try! viewContext.fetch(fr)
////            .map { $0.words }.compactMap { $0 }.filter { $0 != "" }
////    }
//    
////    func loadFollowing() {
////        if (account?.follows != nil) {
////            let pubkeys = account!.follows?.map { $0.pubkey } ?? []
//////            print("💿 follows:")
//////            print(pubkeys)
//////            self.objectWillChange.send()
//////            self.followingPublicKeys = Set( pubkeys )
////        }
////        else {
//////            self.objectWillChange.send()
//////            self.followingPublicKeys = Set([])
////        }
////    }
//    
////    func follow(_ pubkey:String) {
////        guard let account = account else { return }
//////        self.objectWillChange.send()
////        // find existing contact
////        if let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) {
////            contact.couldBeImposter = 0
////            account.addToFollows(contact)
////        }
////        else {
////            // if nil, create new contact
////            let contact = Contact(context: viewContext)
////            contact.pubkey = pubkey
////            contact.couldBeImposter = 0
////            account.addToFollows(contact)
////        }
////        followingPublicKeys = _followingPublicKeys
////        self.loadFollowingPFPs()
////        sendNotification(.followersChanged, account.followingPublicKeys)
////        sendNotification(.followingAdded, pubkey)
////        self.publishNewContactList()
////    }
//    
//    
//    
//    
//    
//    
//    
//        
//    
//    
//    
////    func followsYou(_ contact:Contact) -> Bool { // TODO: REDO, should probably be on NRContact
////        guard let clEvent = contact.clEvent else { return false }
////        guard let account = Thread.isMainThread ? account : bgAccount else { return false }
////        return !clEvent.fastTags.filter { $0.0 == "p" && $0.1 == account.publicKey }.isEmpty
////    }
//    
//        
//    
//    
//}


final class ExchangeRateModel: ObservableObject {
    static public var shared = ExchangeRateModel()
    @Published var bitcoinPrice:Double = 0.0
}


let IS_IPAD = UIDevice.current.userInterfaceIdiom == .pad
let IS_CATALYST = ProcessInfo.processInfo.isMacCatalystApp
let IS_APPLE_TYRANNY = ((Bundle.main.infoDictionary?["NOSTUR_IS_DESKTOP"] as? String) ?? "NO") == "NO"
//let IS_MAC = ProcessInfo.processInfo.isiOSAppOnMac


let GUEST_ACCOUNT_PUBKEY = "c118d1b814a64266730e75f6c11c5ffa96d0681bfea594d564b43f3097813844"
let EXPLORER_PUBKEY = "afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320"


var timeTrackers: [String: CFAbsoluteTime] = [:]
