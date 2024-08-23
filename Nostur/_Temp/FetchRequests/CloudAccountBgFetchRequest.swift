//
//  CloudAccountBgFetchRequest.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/01/2024.
//

import Foundation
import CoreData

class CloudAccountBgFetchRequest: NSObject, NSFetchedResultsControllerDelegate  {
    
    let frc: NSFetchedResultsController<CloudAccount>
    
    override init() {
        let fr = CloudAccount.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \CloudAccount.lastLoginAt_, ascending: false)]
        self.frc = NSFetchedResultsController(fetchRequest: fr, managedObjectContext: bg(), sectionNameKeyPath: nil, cacheName: nil) // TODO: Try cache?
        super.init()
        frc.delegate = self

        bg().perform { [weak self] in
            do {
                try self?.frc.performFetch()
                guard let items = self?.frc.fetchedObjects else { return }
                L.og.debug("BGAccountFetchRequest CloudAccounts: \(items.count) -[LOG]-")
                self?.onChange(items)
            }
            catch {
                L.og.error("🔴🔴🔴 BGAccountFetchRequest failed to fetch items \(error.localizedDescription) -[LOG]-")
            }
        }    }
    
    func onChange(_ accounts: [CloudAccount]) {
        removeDuplicateAccounts(accounts: accounts)
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let accounts = controller.fetchedObjects as? [CloudAccount] else { return }
        onChange(accounts)
    }
    
    private func removeDuplicateAccounts(accounts: [CloudAccount]) {
        var uniqueAccounts = Set<String>()
        let sortedAccounts = accounts.sorted { $0.mostRecentItemDate > $1.mostRecentItemDate }

        accounts.forEach { account in
            account.noPrivateKey = false // clear old cache method

            // check if "full_account" flag is missing, set it if we have private key
            if !account.flagsSet.contains("full_account") && account.privateKey != nil {
                account.flagsSet.insert("full_account")
            }
        }

        let duplicates = sortedAccounts
            .filter { account in
                guard let publicKey = account.publicKey_ else { return false }
                return !uniqueAccounts.insert(publicKey).inserted
            }

        if duplicates.count > 0 {
            L.cloud.debug("BGAccountFetchRequest Deleting: \(duplicates.count) duplicate accounts")
        }
        duplicates.forEach({ duplicateAccount in
            // Before deleting, .union the follows to the existing account
            if let existingAccount = sortedAccounts.first(where: { existingAccount in
                return existingAccount.publicKey == duplicateAccount.publicKey
            }) {
                existingAccount.followingPubkeys.formUnion(duplicateAccount.followingPubkeys)
                existingAccount.privateFollowingPubkeys.formUnion(duplicateAccount.privateFollowingPubkeys)
                existingAccount.followingHashtags.formUnion(duplicateAccount.followingHashtags)
                existingAccount.flagsSet.formUnion(duplicateAccount.flagsSet)

                existingAccount.lastFollowerCreatedAt = max(existingAccount.lastFollowerCreatedAt, duplicateAccount.lastFollowerCreatedAt)
                existingAccount.lastSeenPostCreatedAt = max(existingAccount.lastSeenPostCreatedAt, duplicateAccount.lastSeenPostCreatedAt)
                existingAccount.lastSeenZapCreatedAt = max(existingAccount.lastSeenZapCreatedAt, duplicateAccount.lastSeenZapCreatedAt)
                existingAccount.lastSeenRepostCreatedAt = max(existingAccount.lastSeenRepostCreatedAt, duplicateAccount.lastSeenRepostCreatedAt)
                existingAccount.lastSeenReactionCreatedAt = max(existingAccount.lastSeenReactionCreatedAt, duplicateAccount.lastSeenReactionCreatedAt)
                existingAccount.lastSeenDMRequestCreatedAt = max(existingAccount.lastSeenDMRequestCreatedAt, duplicateAccount.lastSeenDMRequestCreatedAt)
                existingAccount.lastProfileReceivedAt = max(existingAccount.lastProfileReceivedAt ?? .distantPast, duplicateAccount.lastProfileReceivedAt ?? .distantPast)
                existingAccount.lastLoginAt = max(existingAccount.lastLoginAt, duplicateAccount.lastLoginAt)
            }
            bg().delete(duplicateAccount)
        })
        if !duplicates.isEmpty {
            bgSave()
        }
    }
}
