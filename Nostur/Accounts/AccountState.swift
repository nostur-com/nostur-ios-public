//
//  AccountState.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/01/2023.
//

import SwiftUI
import Foundation
import CoreData


final class AccountState : ObservableObject {
    // public keys of the contacts that the currently active ("logged in") account follows
    
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @Published var followingPublicKeys:Set<String> = Set<String>()
    
    var viewContext:NSManagedObjectContext
    
    init(viewContext:NSManagedObjectContext) {
        self.viewContext = viewContext
        loadFollowing()
    }
    
    func activeAccount() -> Account? {
        let r = Account.fetchRequest()
        r.predicate = NSPredicate(format: "publicKey == %@", activeAccountPublicKey)
        return try! viewContext.fetch(r).first
    }
    
    func loadFollowing() {
        let activeAccount = activeAccount()
        if (activeAccount?.follows != nil) {
            let pubkeys = activeAccount!.follows?.map { $0.pubkey! } ?? []
            self.followingPublicKeys = Set( pubkeys )
        }
    }
    
    func follow(_ pubkey:String, cm:ConnectionManager) {
        guard let activeAccount = activeAccount() else {
            return
        }
        
        
        // find existing contact
        if let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) {
            activeAccount.addToFollows(contact)
        }
        else {
            // if nil, create new contact
            let contact = Contact(context: viewContext)
            contact.pubkey = pubkey
            activeAccount.addToFollows(contact)
        }

        try! viewContext.save()
        followingPublicKeys.insert(pubkey)
        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
    }
    
    func unfollow(_ pubkey: String) {
        followingPublicKeys.remove(pubkey)
        
        guard let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) else {
            return
        }
        guard let activeAccount = activeAccount() else {
            return
        }
        guard ((activeAccount.follows?.contains(contact)) != nil) else {
            return
        }
        activeAccount.removeFromFollows(contact)
        try! viewContext.save()
    }
    
    func isFollowing(_ pubkey:String) -> Bool {
        return followingPublicKeys.contains(pubkey)
    }
    
    
    
    func addBookmark(_ event:Event) {
        guard let activeAccount = activeAccount() else {
            return
        }
        activeAccount.addToBookmarks(event)
        do {
            try viewContext.save()
        }
        catch {
            print("Could not add bookmark: \(error)")
        }
    }
    
    func removeBookmark(_ event:Event) {
        guard let activeAccount = activeAccount() else {
            return
        }
        guard ((activeAccount.bookmarks?.contains(event)) != nil) else {
            return
        }
        activeAccount.removeFromBookmarks(event)
        do {
            try viewContext.save()
        }
        catch {
            print("Could not remove bookmark: \(error)")
        }
    }
    
    func isBookmarked(_ event:Event) -> Bool {
        guard let activeAccount = activeAccount(), activeAccount.bookmarks != nil else {
            return false
        }
        return activeAccount.bookmarks!.contains(event)
    }
}
