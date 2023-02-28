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
    
    public static let shared = NosturState(container: EventsProvider.shared.container)
//    public static let preview = NosturState(container: EventsProvider.preview.container)
    
    static let GUEST_ACCOUNT_PUBKEY = "c118d1b814a64266730e75f6c11c5ffa96d0681bfea594d564b43f3097813844"
    static let EXPLORER_PUBKEY = "afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320"
    @Published var onBoardingIsShown = false
    
    // public keys of the contacts that the currently active ("logged in") account follows
    // WTF followingPublicKeys met @Published is superlangzaam... HMMM.
    //@Published var followingPublicKeys:Set<String> = Set<String>()
//    @Published var followingPublicKeys:Set<String> = Set<String>()
//    var followingPublicKeys = CurrentValueSubject<[String], Never>([String]())
    var followingPublicKeys:Set<String> {
        get {
            if account == nil { return Set<String>() }
            
            let blocked = (account!.blockedContacts ?? Set<Contact>()).map { $0.pubkey }
            
            let withSelfIncluded = Set([account!.publicKey] + (account!.follows ?? Set<Contact>()).map { $0.pubkey })
            let withoutBlocked = withSelfIncluded.subtracting(blocked)
            
            return withoutBlocked
        }
    }
    
    var subscriptions = Set<AnyCancellable>()

    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @Published var account:Account? = nil
    @Published var readOnlyAccountSheetShown:Bool = false
    @Published var globalPubkeys:Set<String> = []
    
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
        if (account != nil) {
            activeAccountPublicKey = account!.publicKey
//            DataStore.shared.unreadCount.send(0)
            Task(priority: .userInitiated) {
                self.loadLikesAndReposts()
            }
        }
        print("🟠🟠🟠🟠🟠🟠 ACTIVE ACCOUNT IS: \(self.account?.name ?? "NONE")")
    }
    
    var container:NSPersistentContainer
    var viewContext:NSManagedObjectContext
    
    init(container:NSPersistentContainer) {
        self.container = container
        self.viewContext = container.viewContext
        if (activeAccountPublicKey != "") {
            if let account = try? Account.fetchAccount(publicKey: activeAccountPublicKey, context: viewContext) {
                self.setAccount(account: account)
            }
        }
        print("🟠🟠🟠🟠🟠🟠 ACTIVE ACCOUNT IS: \(self.account?.name ?? "NONE")")
    }
    
    func loadLikesAndReposts() {
        guard self.account != nil else {
            print("🔴🔴 no account 🔴🔴")
            return
        }
        
        let backgroundContext = container.newBackgroundContext()

        print("🎒🎒 LOAD LIKES/REPOSTS CACHE FOR ACCOUNT: ZEROING 🎒🎒")
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

        print("🎒🎒 LOAD LIKES/REPOSTS CACHE FOR ACCOUNT: SETTING 🎒🎒")
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
//        followingPublicKeys.insert(pubkey)
    }
    
    func follow(_ contact:Contact) {
        guard account != nil else {
            return
        }
        account!.addToFollows(contact)
        try! viewContext.save()
        
//        followingPublicKeys.insert(contact.pubkey)
        
        guard let clEvent = try? AccountManager.createContactListEvent(account: account!) else {
            print("🔴🔴 Could not create new clEvent")
            return
        }
        _ = Unpublisher.shared.publishLast(clEvent, ofType: .contactList)
    }
    
    func unfollow(_ pubkey: String) {
//        followingPublicKeys.remove(pubkey)
        
        guard let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) else {
            return
        }
        guard account != nil else {
            return
        }
        account!.removeFromFollows(contact)
        try! viewContext.save()
        
        guard let clEvent = try? AccountManager.createContactListEvent(account: account!) else {
            print("🔴🔴 Could not create new clEvent")
            return
        }
        _ = Unpublisher.shared.publishLast(clEvent, ofType: .contactList)
    }
    
    func unfollow(_ contact:Contact) {
//        followingPublicKeys.remove(contact.pubkey)
        
        guard let contact = Contact.contactBy(pubkey: contact.pubkey, context: viewContext) else {
            return
        }
        guard account != nil else {
            return
        }
        account!.removeFromFollows(contact)
        try! viewContext.save()
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
        guard account != nil else {
            return
        }
        account!.addToBookmarks(event)
        do {
            try viewContext.save()
        }
        catch {
            print("Could not add bookmark: \(error)")
        }
    }
    
    func removeBookmark(_ event:Event) {
        guard account != nil else {
            return
        }
        account!.removeFromBookmarks(event)
        do {
            try viewContext.save()
        }
        catch {
            print("Could not remove bookmark: \(error)")
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
        return (contact.clEvent!.tags()).filter { $0.type == "p" && $0.otherInformation[0] == activeAccountPublicKey }.count > 0
    }
    
}


final class UnreadCounterModel: ObservableObject {
    static public var shared = UnreadCounterModel()
    @Published var unreadCount = 0
    @Published var mostRecentCreatedAt:Int64 = 0
}

//final class TimelineModel: ObservableObject {
//    @Published var notesOnScreen:[Event] = []
//}

final class ExchangeRateModel: ObservableObject {
    static public var shared = ExchangeRateModel()
    @Published var bitcoinPrice:Double = 0.0
}



let IS_IPAD = UIDevice.current.userInterfaceIdiom == .pad
