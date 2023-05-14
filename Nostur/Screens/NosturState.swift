//
//  AccountState.swift
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

    var followingPublicKeys:Set<String> {
        get {
            guard let account = account else { return Set<String>()}
            
            let withSelfIncluded = Set([account.publicKey] + account.follows_.map { $0.pubkey })
            let withoutBlocked = withSelfIncluded.subtracting(Set(account.blockedPubkeys_))
            
            return withoutBlocked
        }
    }
    
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
                DataProvider.shared().bg.perform {
                    self.bgAccount = DataProvider.shared().bg.object(with: account.objectID) as? Account
                }
            }
            else {
                bgAccount = nil
            }
        }
    }
    var bgAccount:Account?
    @Published var readOnlyAccountSheetShown:Bool = false
    @Published var rawExplorePubkeys:Set<String> = []
    
    var pubkey:String? {
        get { account?.publicKey }
    }
    
    var accounts:[Account] {
        get {
            let r = Account.fetchRequest()
            return (try? viewContext.fetch(r) ) ?? []
        }
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
            VPostTransformer.shared.followingKeys = self.followingPublicKeys
            VPostTransformer.bg.followingKeys = self.followingPublicKeys
            activeAccountPublicKey = account.publicKey
            // load state for new account
            lastNotificationReceivedAt = account.lastNotificationReceivedAt
            lastProfileReceivedAt = account.lastProfileReceivedAt
            
            // Remove currectly active "Following" subscriptions from connected sockets
            SocketPool.shared.removeActiveAccountSubscriptions()
            if sendActiveAccountChangedNotification {
                sendNotification(.activeAccountChanged, account)
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
        
        if (activeAccountPublicKey != "") {
            if let account = try? Account.fetchAccount(publicKey: activeAccountPublicKey, context: viewContext) {
                self.setAccount(account: account)
            }
        }
        initMutedWords()
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
        self.objectWillChange.send()
        // find existing contact
        if let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) {
            account.addToFollows(contact)
        }
        else {
            // if nil, create new contact
            let contact = Contact(context: viewContext)
            contact.pubkey = pubkey
            account.addToFollows(contact)
        }

        DataProvider.shared().save()
        sendNotification(.followersChanged, account.followingPublicKeys)
        VPostTransformer.shared.followingKeys = account.followingPublicKeys
        VPostTransformer.bg.followingKeys = account.followingPublicKeys
        publishNewContactList()
    }
    
    func follow(_ contact:Contact) {
        guard let account = account else { return }
        self.objectWillChange.send()
        account.addToFollows(contact)
        
        DataProvider.shared().save()
        sendNotification(.followersChanged, account.followingPublicKeys)
        VPostTransformer.shared.followingKeys = account.followingPublicKeys
        VPostTransformer.bg.followingKeys = account.followingPublicKeys
        publishNewContactList()
    }
    
    func unfollow(_ pubkey: String) {
        guard let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) else {
            return
        }
        guard let account = account else { return }
        self.objectWillChange.send()
        account.removeFromFollows(contact)
        DataProvider.shared().save()
        sendNotification(.followersChanged, account.followingPublicKeys)
        VPostTransformer.shared.followingKeys = account.followingPublicKeys
        VPostTransformer.bg.followingKeys = account.followingPublicKeys
        publishNewContactList()
    }
    
    func unfollow(_ contact:Contact) {
        guard let contact = Contact.contactBy(pubkey: contact.pubkey, context: viewContext) else {
            return
        }
        guard let account = account else { return }
        self.objectWillChange.send()
        account.removeFromFollows(contact)
        DataProvider.shared().save()
        sendNotification(.followersChanged, account.followingPublicKeys)
        VPostTransformer.shared.followingKeys = account.followingPublicKeys
        VPostTransformer.bg.followingKeys = account.followingPublicKeys
        publishNewContactList()
    }
    
    func publishNewContactList() {
        guard let clEvent = try? AccountManager.createContactListEvent(account: account!) else {
            print("🔴🔴 Could not create new clEvent")
            return
        }
        _ = Unpublisher.shared.publishLast(clEvent, ofType: .contactList)
    }
    
    func isFollowing(_ pubkey:String) -> Bool {
        return followingPublicKeys.contains(pubkey)
    }
    
    func isFollowing(_ contact:Contact) -> Bool {
        guard let account = account else { return false }
        return account.follows?.contains(contact) ?? false
    }    
    
    func addBookmark(_ event:Event) {
        guard let account = account else { return }
        event.objectWillChange.send()
        account.addToBookmarks(event)
        sendNotification(.postAction, PostActionNotification(type:.bookmark, eventId: event.id, bookmarked: true))
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            }
            catch {
                print("Could not add bookmark: \(error)")
            }
        }
    }
    
    func removeBookmark(_ event:Event) {
        guard let account = account else { return }
        account.removeFromBookmarks(event)
        sendNotification(.postAction, PostActionNotification(type:.bookmark, eventId: event.id, bookmarked: false))
        DataProvider.shared().save()
    }
    
    func toggleBookmark(_ event:Event) {
        if isBookmarked(event) {
            removeBookmark(event)
        }
        else {
            addBookmark(event)
        }
    }
    
    func isBookmarked(_ event:Event) -> Bool {
        guard account != nil else {
            return false
        }
        return account!.bookmarks?.contains(event) ?? false
    }
    
    func signEvent(_ event:NEvent) throws -> NEvent {
        guard account != nil, account?.privateKey != nil else {
            if (account == nil) { print("🔴🔴🔴🔴🔴 Acccount missing, could not sign 🔴🔴🔴🔴🔴") }
            if (account?.privateKey == nil) { print("🔴🔴🔴🔴🔴 private key missing, could not sign 🔴🔴🔴🔴🔴") }
            throw "account or keys missing, could not sign"
        }
        
        var eventToSign = event
        do {
            let keys = try NKeys(privateKeyHex: account!.privateKey!)
            let signedEvent = try eventToSign.sign(keys)
            return signedEvent
        }
        catch {
            print("🔴🔴🔴🔴🔴 Could not sign event 🔴🔴🔴🔴🔴")
            throw "Could not sign event"
        }
    }
    
    func followsYou(_ contact:Contact) -> Bool {
        guard let clEvent = contact.clEvent else { return false }
        guard let account = account else { return false }
        return clEvent.fastTags.filter { $0.0 == "p" && $0.1 == account.publicKey }.count > 0
    }
    
    func muteConversation(_ nrPost:NRPost) {
        guard let account = account else { return }
        if let replyToRootId = nrPost.replyToRootId {
            account.mutedRootIds_ = account.mutedRootIds_ + [replyToRootId, nrPost.id]
            print("Muting \(replyToRootId)")
        }
        else if let replyToId = nrPost.replyToId {
            account.mutedRootIds_ = account.mutedRootIds_ + [replyToId, nrPost.id]
            print("Muting \(replyToId)")
        }
        else {
            account.mutedRootIds_ = account.mutedRootIds_ + [nrPost.id]
            print("Muting \(nrPost.id)")
        }
        do {
            try viewContext.save()
            sendNotification(.muteListUpdated)
        }
        catch {
            print("Could not save after muting thread \(error)")
        }
    }
    
    func likePost(_ event:Event) -> NEvent? {
        guard account?.privateKey != nil else { readOnlyAccountSheetShown = true; return nil }
        guard account != nil else { return nil }
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        print("💖💖💖💖💖💖💖💖💖💖💖💖💖💖")
        
//      1. create kind 7 event based on kind 1 event:
        let likeEvent = EventMessageBuilder.makeReactionEvent(reactingTo: event)
//      2. sign that event with account keys
        guard let signedEvent = try? signEvent(likeEvent) else {
            print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        event.likesCount += 1
        return signedEvent
    }
    
    func unlikePost(_ event:Event) {
        event.likesCount -= 1
        do {
            try viewContext.save()
//            sendNotification(.viewNeedsUpdate)
        }
        catch {
            print("Could save after unlike \(error)")
        }
    }
    
    func logout(_ account:Account) {
        if (account.privateKey != nil) {
            AccountManager.shared.deletePrivateKey(forPublicKeyHex: account.publicKey)
        }
        if (accounts.count < 1) {
            onBoardingIsShown = true
            sendNotification(.clearNavigation)
            setAccount(account: nil)
            viewContext.delete(account)
        }
        else {
            viewContext.delete(account)
            setAccount(account: accounts.last)
        }
        try! viewContext.save()
    }
    
    func report(_ event:Event, reportType:ReportType, note:String = "", includeProfile:Bool = false) -> NEvent? {
        guard account?.privateKey != nil else { readOnlyAccountSheetShown = true; return nil }
        
        let report = EventMessageBuilder.makeReportEvent(pubkey: event.pubkey, eventId: event.id, type: reportType, note: note, includeProfile: includeProfile)

        guard let signedEvent = try? signEvent(report) else {
            print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    func reportContact(pubkey:String, reportType:ReportType, note:String = "") -> NEvent? {
        guard account?.privateKey != nil else { readOnlyAccountSheetShown = true; return nil }
        
        let report = EventMessageBuilder.makeReportContact(pubkey: pubkey, type: reportType, note: note)

        guard let signedEvent = try? signEvent(report) else {
            print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    func deletePost(_ eventId:String) -> NEvent? {
        guard account?.privateKey != nil else { readOnlyAccountSheetShown = true; return nil }
        
        let deletion = EventMessageBuilder.makeDeleteEvent(eventId: eventId)

        guard let signedEvent = try? signEvent(deletion) else {
            print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
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
