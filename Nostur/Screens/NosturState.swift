//
//  AccountState.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/01/2023.
//

import SwiftUI
import Foundation
import CoreData

final class NosturState : ObservableObject {
        
    @Published var isOnboarding = false

    
    // public keys of the contacts that the currently active ("logged in") account follows
    // WTF followingPublicKeys met @Published is superlangzaam... HMMM.
    //@Published var followingPublicKeys:Set<String> = Set<String>()
    @Published var followingPublicKeys:Set<String> = Set<String>()
    
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @Published var account:Account? = nil
    
    @State var pendingFirstContactsFetch:Bool = false
    @Published var readOnlyAccountSheetShown:Bool = false
    
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
        self.account = account
        if (account == nil) {
            self.followingPublicKeys = []
        }
        else {
            _ = loadActiveAccount(account: account)
            activeAccountPublicKey = account!.publicKey!
        }
    }
    
    var container:NSPersistentContainer
    var viewContext:NSManagedObjectContext
    
    init(container:NSPersistentContainer) {
        self.container = container
        self.viewContext = container.viewContext
        _ = loadActiveAccount()
        print("🦋🦋 ACTIVE ACCOUNT IS: \(self.account?.name ?? "NONE")")
    }
    
    func loadActiveAccount(account:Account? = nil) -> Account? {
        if (account != nil) {
            self.account = account!            
        }
        else {
            let r = Account.fetchRequest()
            if (activeAccountPublicKey != "") {
                r.predicate = NSPredicate(format: "publicKey == %@", activeAccountPublicKey)
            }
            self.account = try! viewContext.fetch(r).first
            
            if (self.account == nil) { // No account? Just fall back to (ANY) firstaccount
                r.predicate = nil
                self.account = try! viewContext.fetch(r).first
            }
            if (self.account == nil) {
                isOnboarding = true
                return nil
            }
            activeAccountPublicKey = self.account!.publicKey!
        }
        loadFollowing()
        Task(priority: .userInitiated) {
            self.loadLikes()
        }
        return self.account
    }
    
    func loadLikes() {
        guard self.account != nil else {
            print("🔴🔴 no account 🔴🔴")
            return
        }
        
        let backgroundContext = container.newBackgroundContext()

        backgroundContext.perform {
            let batchUpdate = NSBatchUpdateRequest(entityName: "Event")
            batchUpdate.propertiesToUpdate = ["liked": 0]
            batchUpdate.resultType = .updatedObjectsCountResultType

            do {
                let result = try backgroundContext.execute(batchUpdate) as! NSBatchUpdateResult
                print("Zerod .liked property for \(result.result!) events")
            } catch {
                print("Failed to zero .liked")
            }
        }

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
    }
    
    func loadFollowing() {
        if (account?.follows != nil) {
            let pubkeys = account!.follows?.map { $0.pubkey! } ?? []
//            print("💿 follows:")
//            print(pubkeys)
            self.followingPublicKeys = Set( pubkeys )
        }
        else {
            self.followingPublicKeys = Set([])
        }
    }
    
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
        followingPublicKeys.insert(pubkey)
    }
    
    func follow(_ contact:Contact) {
        guard account != nil else {
            return
        }
        account!.addToFollows(contact)
        try! viewContext.save()
        
        followingPublicKeys.insert(contact.pubkey!)
        
        guard let clEvent = try? AccountManager.createContactListEvent(account: account!) else {
            print("🔴🔴 Could not create new clEvent")
            return
        }
        _ = Unpublisher.shared.publishLast(clEvent, ofType: .contactList)
    }
    
    func unfollow(_ pubkey: String) {
        followingPublicKeys.remove(pubkey)
        
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
        followingPublicKeys.remove(contact.pubkey!)
        
        guard let contact = Contact.contactBy(pubkey: contact.pubkey!, context: viewContext) else {
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
        return (contact.clEvent!.oldTags() ?? []).filter { $0.type == "p" && $0.otherInformation[0] == activeAccountPublicKey }.count > 0
    }
    
}
