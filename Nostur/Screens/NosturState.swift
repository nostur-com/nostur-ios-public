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
    @Published var onBoardingIsShown = false
    

    var followingPublicKeys:Set<String> {
        get {
            if account == nil { return Set<String>() }
            
            let withSelfIncluded = Set([account!.publicKey] + (account!.follows ?? Set<Contact>()).map { $0.pubkey })
            let withoutBlocked = withSelfIncluded.subtracting(Set(account!.blockedPubkeys_))
            
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
    @Published var account:Account? = nil
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
        self.objectWillChange.send()
        self.account = account
        if let account {
            activeAccountPublicKey = account.publicKey
            
            // Remove currectly active "Following" subscriptions from connected sockets
            SocketPool.shared.removeActiveAccountSubscriptions()
            Task(priority: .userInitiated) {
                self.loadLikesAndReposts()
            }
            sendNotification(.activeAccountChanged, account)
        }
        print("🟠🟠🟠🟠🟠🟠 ACTIVE ACCOUNT IS: \((self.account?.name != "") ? self.account?.name ?? (self.account?.display_name ?? "NONE") : (self.account?.display_name ?? "NONE"))")
    }
    
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
    }
    
    func loadLikesAndReposts() {
        guard self.account != nil else {
            print("🔴🔴 no account 🔴🔴")
            return
        }
        
        let backgroundContext = DataProvider.shared().newTaskContext()

        print("🎒🎒 LOAD LIKES/REPOSTS CACHE FOR ACCOUNT: ZEROING/SETTING 🎒🎒")
        backgroundContext.perform {
            let batchUpdate = NSBatchUpdateRequest(entityName: "Event")
            batchUpdate.propertiesToUpdate = ["liked": 0, "reposted": 0]
            batchUpdate.resultType = .updatedObjectsCountResultType

            do {
                let result = try backgroundContext.execute(batchUpdate) as! NSBatchUpdateResult
                print("Zerod .liked/.reposted property for \(result.result!) events")
            } catch {
                print("Failed to zero .liked/.reposted")
            }
        }

//        print("🎒🎒 LOAD LIKES/REPOSTS CACHE FOR ACCOUNT: SETTING 🎒🎒")
        backgroundContext.performAndWait {
            let account = backgroundContext.object(with: self.account!.objectID) as! Account
            guard account.likes != nil else {
                print("🔴🔴 no account or account.likes 🔴🔴")
                return
            }

            for event in account.likes! {
                event.liked = true
            }

            print("Updated likes cache for \(account.likes!.count) events... NEED TO SAVE HERE OR NO?")
        }
        backgroundContext.performAndWait {
            let account = backgroundContext.object(with: self.account!.objectID) as! Account
            guard account.reposts != nil else {
                print("🔴🔴 no account or account.reposts 🔴🔴")
                return
            }

            for event in account.reposts! {
                event.reposted = true
            }

            print("Updated reposts cache for \(account.reposts!.count) events... NEED TO SAVE HERE OR NO?")
        }
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
        guard account != nil else {
            return
        }
        self.objectWillChange.send()
        // find existing contact
        if let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) {
            account!.addToFollows(contact)
        }
        else {
            // if nil, create new contact
            let contact = Contact(context: viewContext)
            contact.pubkey = pubkey
            account!.addToFollows(contact)
        }

        try! viewContext.save()
        publishNewContactList()
    }
    
    func publishNewContactList() {
        guard let clEvent = try? AccountManager.createContactListEvent(account: account!) else {
            print("🔴🔴 Could not create new clEvent")
            return
        }
        _ = Unpublisher.shared.publishLast(clEvent, ofType: .contactList)
    }
    
    func follow(_ contact:Contact) {
        guard account != nil else {
            return
        }
        self.objectWillChange.send()
        account!.addToFollows(contact)
        try! viewContext.save()

        publishNewContactList()
    }
    
    func unfollow(_ pubkey: String) {
        guard let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) else {
            return
        }
        guard account != nil else {
            return
        }
        self.objectWillChange.send()
        account!.removeFromFollows(contact)
        try! viewContext.save()
        
        publishNewContactList()
    }
    
    func unfollow(_ contact:Contact) {
        guard let contact = Contact.contactBy(pubkey: contact.pubkey, context: viewContext) else {
            return
        }
        guard account != nil else {
            return
        }
        self.objectWillChange.send()
        account!.removeFromFollows(contact)
        try! viewContext.save()
        
        publishNewContactList()
    }
    
    func isFollowing(_ pubkey:String) -> Bool {
        return followingPublicKeys.contains(pubkey)
    }
    
    func isFollowing(_ contact:Contact) -> Bool {
        guard account != nil else {
            return false
        }
        return account!.follows?.contains(contact) ?? false
    }    
    
    func addBookmark(_ event:Event) {
        guard account != nil else { return }
        event.objectWillChange.send()
        account!.addToBookmarks(event)
        do {
            try viewContext.save()
//            sendNotification(.viewNeedsUpdate)
        }
        catch {
            print("Could not add bookmark: \(error)")
        }
    }
    
    func removeBookmark(_ event:Event) {
        guard account != nil else { return }
        account!.removeFromBookmarks(event)
        do {
            try viewContext.save()
//            sendNotification(.viewNeedsUpdate)
        }
        catch {
            print("Could not remove bookmark: \(error)")
        }
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
        guard contact.clEvent != nil else { return false }
        guard let account = account else { return false }
        return (contact.clEvent!.fastTags).filter { $0.0 == "p" && $0.1 == account.publicKey }.count > 0
    }
    
    func muteConversation(_ vPost:VPost) {
        guard let account = account else { return }
        if let replyToRootId = vPost.event.replyToRootId {
            account.mutedRootIds_ = account.mutedRootIds_ + [replyToRootId, vPost.id]
            print("Muting \(replyToRootId)")
        }
        else if let firstE = vPost.event.firstE() {
            account.mutedRootIds_ = account.mutedRootIds_ + [firstE, vPost.id]
            print("Muting \(firstE)")
        }
        else {
            account.mutedRootIds_ = account.mutedRootIds_ + [vPost.id]
            print("Muting \(vPost.id)")
        }
        do {
            try viewContext.save()
            sendNotification(.muteListUpdated)
            //sendNotification(.viewNeedsUpdate) // TODO: NEED THIS??
        }
        catch {
            print("Could not save after muting thread \(error)")
        }
    }
    
    func likePost(_ event:Event) -> NEvent? {
        guard account?.privateKey != nil else { readOnlyAccountSheetShown = true; return nil }
        guard let account = account else { return nil }
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        print("💖💖💖💖💖💖💖💖💖💖💖💖💖💖")
        event.liked = true
        event.likesCount += 1
        account.addToLikes(event)
        
//      1. create kind 7 event based on kind 1 event:
        let likeEvent = EventMessageBuilder.makeReactionEvent(reactingTo: event)
//      2. sign that event with account keys
        guard let signedEvent = try? signEvent(likeEvent) else {
            print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    func unlikePost(_ event:Event) {
        event.liked = false
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
        if (accounts.count <= 1) {
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
    
    func report(_ event:Event, reportType:ReportType, note:String = "") -> NEvent? {
        guard account?.privateKey != nil else { readOnlyAccountSheetShown = true; return nil }
        
        let report = EventMessageBuilder.makeReportEvent(pubkey: event.pubkey, eventId: event.id, type: reportType, note: note)

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
