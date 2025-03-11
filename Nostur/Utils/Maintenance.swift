//
//  Maintenance.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import Foundation
import CoreData
import KeychainAccess

struct Maintenance {
    
    @MainActor
    static func deleteAllEventsAndContacts(context: NSManagedObjectContext) async {
#if DEBUG
        guard IS_SIMULATOR else { return }
        await context.perform {
            
            let fr = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            fr.predicate = NSPredicate(value: true)
            
            let frBatchDelete = NSBatchDeleteRequest(fetchRequest: fr)
            frBatchDelete.resultType = .resultTypeCount
            
            if let result = try? context.execute(frBatchDelete) as? NSBatchDeleteResult {
                if let count = result.result as? Int, count > 0 {
                    L.maintenance.info("🧹🧹🧹🧹 Deleted \(count) events")
                }
            }
            
            let fr2 = NSFetchRequest<NSFetchRequestResult>(entityName: "Contact")
            fr2.predicate = NSPredicate(value: true)
            
            let fr2BatchDelete = NSBatchDeleteRequest(fetchRequest: fr2)
            fr2BatchDelete.resultType = .resultTypeCount
            
            if let result2 = try? context.execute(fr2BatchDelete) as? NSBatchDeleteResult {
                if let count = result2.result as? Int, count > 0 {
                    L.maintenance.info("🧹🧹🧹🧹 Deleted \(count) contacts")
                }
            }
        }
#endif
    }

    static let BOOTSTRAP_RELAYS = ["wss://relay.damus.io", "wss://relay.nostr.band", "wss://nos.lol", "wss://nostr.wine", "wss://purplepag.es"]
    
    // Removed: wss://relay.damus.io // shows only cameri bug
    // Removed: time out... "wss://nostr.fmt.wiz.biz"
    // Removed: too many subscriptions "wss://relay.snort.social"
    // Removed: always connection fail "wss://relayable.org"
    
    @MainActor
    static func ensureBootstrapRelaysExist(context:NSManagedObjectContext) async {
        await context.perform {
            let r = CloudRelay.fetchRequest()
            if let relaysCount = try? context.fetch(r).count {
                var relays:[RelayData] = []
                
                if (relaysCount == 0) {
                    for url in BOOTSTRAP_RELAYS {
                        let bootstrapRelay = CloudRelay(context: context)
                        bootstrapRelay.read = ["wss://relay.nostr.band","wss://relay.damus.io"].contains(url) ? false : true // write only bootstrap
                        bootstrapRelay.write = true
                        bootstrapRelay.createdAt = Date.now
                        bootstrapRelay.url_ = url
                        if ["wss://relay.nostr.band","wss://relay.damus.io"].contains(url) {
                            bootstrapRelay.search = true
                        }
                        if (url == "wss://nostr.wine") {
                            bootstrapRelay.auth = true
                        }
                        relays.append(bootstrapRelay.toStruct())
                    }
                }
            }
            
        }
    }
    
    // Version based migrations
    // Runs on viewContext. Must finish before app can continue launch
    static func upgradeDatabase(context: NSManagedObjectContext) async {
        L.maintenance.info("Starting version based maintenance")
        await context.perform {
            Self.runDeleteEventsWithoutId(context: context)
            Self.runUseDtagForReplacableEvents(context: context)
//            Self.runSetAtagForReplacableEvents(context: context) // Removed, can't query relays for multiple aTags so nevermind. Maybe useful in the future but not now
            Self.runInsertFixedNames(context: context)
            Self.runFixArticleReplies(context: context)
            Self.runMigrateDMState(context: context)
            Self.runFixImposterFalsePositivesAgainAgain(context: context)
            Self.runFixZappedContactPubkey(context: context)
            Self.runPutRepostedPubkeyInOtherPubkey(context: context)
            Self.runPutReactionToPubkeyInOtherPubkey(context: context)
            Self.runMigrateBookmarks(context: context)
            Self.runMigratePrivateNotes(context: context)
            Self.runMigrateCustomFeeds(context: context)
            Self.runMigrateBlocks(context: context)
            Self.runMigrateAccounts(context: context)
            Self.runMigrateDMsToCloud(context: context)
            Self.runMigrateRelays(context: context)
            Self.runUpdateKeychainInfo(context: context)
            Self.runSaveFullAccountFlag(context: context)
            Self.runFixMissingDMStates(context: context)
            Self.runInsertFixedPfps(context: context)
            Self.runMigrateListStateToCustomFeeds(context: context)
            Self.runPutReferencedAtag(context: context)
            do {
                if context.hasChanges {
                    try context.save()
                }
            }
            catch {
                L.maintenance.error("🧹🧹 🔴🔴 Version based maintenance could not save: \(error)")
            }
        }
    }
    
    
    // Clean up things older than X days
    // Deletes ALL KIND=0 Events (except own), because should have Contact entity.
    // Keeps bookmarks
    // Keeps own events
    // Keeps contacts/posts with private notes
    // Could run in background, maybe on app minimize
    static func dailyMaintenance(context: NSManagedObjectContext, force: Bool = false) async -> Bool {
        
        // Time based migrations
    
        let lastMaintenanceTimestamp = Date(timeIntervalSince1970: TimeInterval(SettingsStore.shared.lastMaintenanceTimestamp))
        let hoursAgo = Date(timeIntervalSinceNow: -86_400)
        guard force || (lastMaintenanceTimestamp < hoursAgo) else { // don't do maintenance more than once every 24 hours
            L.maintenance.info("Skipping maintenance");
            return false
        }
        SettingsStore.shared.lastMaintenanceTimestamp = Int(Date.now.timeIntervalSince1970)
        L.maintenance.info("Starting time based maintenance")
        
        return await context.perform {
            Self.databaseCleanUp(context)
            try? context.save()
            return true
        }
    }
    
    // SetMetadata can have a banner field now.
    func rescanForBannerFields() {
        DataProvider.shared().container.viewContext.perform {
            
            do {
                let decoder = JSONDecoder()
                
                let er = NSFetchRequest<Event>(entityName: "Event")
                er.predicate = NSPredicate(format: "kind == 0")
                er.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                let metaEvents = try! er.execute()
                
                let cr = NSFetchRequest<Contact>(entityName: "Contact")
                cr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
                let contacts = try! cr.execute()
                
                for contact in contacts {
                    // TODO: `replace with new function (updateContactFromMetaEvent)
                    if let lastEvent = metaEvents.first(where: { $0.pubkey == contact.pubkey }) {
                        guard let metaData = try? decoder.decode(NSetMetadata.self, from: (lastEvent.content?.data(using: .utf8, allowLossyConversion: false)!)!) else {
                            continue
                        }
                        if metaData.banner != nil {
                            contact.banner = metaData.banner!
                            L.maintenance.info("🟡🟡 Updated banner \(metaData.banner!) for \(contact.pubkey)")
                        }
                    }
                }
                try DataProvider.shared().container.viewContext.save()
                L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
            }
            
            catch let error {
                L.maintenance.info("😢😢😢 XX \(error)")
            }
        }
    }
    
    func deleteAllContacts() {
        //        if (1 == 1) { return }
        //        DataProvider.shared().container.viewContext.perform {
        //            do {
        //                let r = NSFetchRequest<Contact>()
        //                r.entity = Contact.entity()
        //                r.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
        //
        //                guard let allContacts = try? r.execute() else {
        //                    L.maintenance.info("😢 XX")
        //                    return
        //                }
        //
        //                for contact in allContacts {
        //                    DataProvider.shared().container.viewContext.delete(contact)
        //                }
        //
        //                try DataProvider.shared().container.viewContext.save()
        //            } catch let error  {
        //                L.maintenance.info("😢😢😢 XX \(error)")
        //            }
        //        }
    }
    
    static func databaseCleanUp(_ context: NSManagedObjectContext) {
        let pfr = NSFetchRequest<NSFetchRequestResult>(entityName: "PersistentNotification")
        let fiveDaysAgo = Date.now.addingTimeInterval(-432_000)
        let monthsAgo = Date.now.addingTimeInterval(-5_356_800) // 2 months
        pfr.predicate = NSPredicate(format: "createdAt < %@ AND NOT readAt = nil", fiveDaysAgo as NSDate)
        
        let pfrBatchDelete = NSBatchDeleteRequest(fetchRequest: pfr)
        pfrBatchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(pfrBatchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) old notifications")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete old notifications")
        }
        
        let frA = CloudAccount.fetchRequest()
        let allAccounts = Array(try! context.fetch(frA))
        let ownAccountPubkeys = allAccounts.reduce([String]()) { partialResult, account in
            var newResult = Array(partialResult)
            if (account.isFullAccount) || (account.privateKey != nil) { // only if it is really our account. .privateKey could return nil if device is restarted, not unlocked yet, so keychain access not available. so we also track full account by "full_account" flag in db.
                newResult.append(account.publicKey)
            }
            return newResult
        }
        
        let regex = ".*(" + ownAccountPubkeys.map {
            NSRegularExpression.escapedPattern(for: serializedP($0))
        }.joined(separator: "|") + ").*"
        
        let ownAccountBookmarkIds:Set<String> = Set(Bookmark.fetchAll(context: context).compactMap { $0.eventId })
        
        let ownAccountPrivateNoteEventIds:Set<String> = Set(CloudPrivateNote.fetchAll(context: context).compactMap({ pn in
            guard let type = pn.type,
                  type == CloudPrivateNote.PrivateNoteType.post.rawValue,
                  let eventId = pn.eventId
            else { return nil }
            return eventId
        }))
        
        let xDaysAgo = Date.now.addingTimeInterval(-345_600) // 4 days
        
        
        
        // CLEAN UP EVENTS WITHOUT SIG (BUG FROM PostPreview)
        let frNoSig = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        frNoSig.predicate = NSPredicate(format: "sig == nil AND flags != \"nsecbunker_unsigned\"")
        
        let frNoSigbatchDelete = NSBatchDeleteRequest(fetchRequest: frNoSig)
        frNoSigbatchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(frNoSigbatchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) events without signature")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete events without signature")
        }
        
        
        
        
        // KIND 1,4,5,6,20,9802,30023,34235
        // OLDER THAN X DAYS
        // IS NOT BOOKMARKED
        // IS NOT OWN EVENT
        // DOES NOT HAVE OUR PUBKEY IN P (Notifications)
        // DONT DELETE MUTED BLOCKED, SO OUR BLOCK LIST STILL FUNCTIONS....
        // TODO: DONT EXPORT MUTED / BLOCKED. KEEP HERE SO WE DONT HAVE TO KEEP ..REPARSING
        
        // Ids to keep: own bookmarks, privatenotes
        let mergedIds = Set(ownAccountBookmarkIds).union(Set(ownAccountPrivateNoteEventIds))
        
        let fr16 = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        fr16.predicate = NSPredicate(format: "created_at < %i AND kind IN {1,4,5,6,20,9802,30023,34235} AND NOT id IN %@ AND NOT (pubkey IN %@ OR tagsSerialized MATCHES %@)", Int64(xDaysAgo.timeIntervalSince1970), mergedIds, ownAccountPubkeys, regex)
        
        let fr16batchDelete = NSBatchDeleteRequest(fetchRequest: fr16)
        fr16batchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(fr16batchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) kind {1,4,5,6,20,9802,30023,34235} events")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete {1,4,5,6,20,9802,30023,34235} data")
        }
        
        
        // KIND 7,8
        // OLDER THAN X DAYS
        // PUBKEY NOT IN OWN ACCOUNTS
        // OR PUBKEY OF OWN ACCOUNTS NOT IN SERIALIZED TAGS
        //            context.perform {
        let fr78 = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        
        fr78.predicate = NSPredicate(format: "created_at < %i AND kind IN {8,7} AND NOT (pubkey IN %@ OR tagsSerialized MATCHES %@)", Int64(xDaysAgo.timeIntervalSince1970), ownAccountPubkeys, regex)
        
        let fr78batchDelete = NSBatchDeleteRequest(fetchRequest: fr78)
        fr78batchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(fr78batchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) kind {8,7} events")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete 8,7 data")
        }
        
        // KIND 9735
        // OLDER THAN X DAYS
        // otherPubkey NOT IN OWN ACCOUNTS
        //            context.perform {
        let fr9735 = Event.fetchRequest()
        fr9735.predicate = NSPredicate(format: "created_at < %i AND kind == 9735 AND (otherPubkey == nil OR NOT otherPubkey IN %@)", Int64(xDaysAgo.timeIntervalSince1970), ownAccountPubkeys)
        
        var deleted9735 = 0
        var deleted9734 = 0
        if let zaps = try? context.fetch(fr9735) {
            for zap in zaps {
                // Also delete zap request (not sure if cascades from 9735 so just delete here anyway)
                if let zapReq = zap.zapFromRequest {
                    context.delete(zapReq)
                    deleted9734 += 1
                }
                context.delete(zap)
                deleted9735 += 1
            }
        }
        L.maintenance.info("🧹🧹 Deleted \(deleted9735) zaps and \(deleted9734) zap requests")
        
        // KIND 0
        // REMOVE ALL BECAUSE EVERY KIND 0 HAS A CONTACT
        // DONT REMOVE OWN KIND 0
        //            context.perform {
        let fr0 = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        fr0.predicate = NSPredicate(format: "(kind == 0) AND NOT pubkey IN %@", ownAccountPubkeys)
        
        let fr0batchDelete = NSBatchDeleteRequest(fetchRequest: fr0)
        fr0batchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(fr0batchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) kind=0 events")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete kind=0 data")
        }

        
        // DELETE OLDER KIND 3 + 10002 EVENTS
        // BUT NOT OUR OWN OR THOSE WE ARE FOLLOWING (FOR WoT follows-follows)
        // AND NOT OUR PUBKEY IN Ps (is following us, for following notifications)
        
        var followingPubkeys = Set(ownAccountPubkeys)
        for account in allAccounts {
            if account.privateKey != nil {
                followingPubkeys = followingPubkeys.union(account.followingPubkeys)
            }
        }
        
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.predicate = NSPredicate(format: "kind IN {3,10002} AND NOT (pubkey IN %@ OR tagsSerialized MATCHES %@)", followingPubkeys, regex)
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let kind3or10002 = try! context.fetch(r)
        
        var noDuplicates:Dictionary<String, Event> = [:]
        var forDeletion:[Event] = []
        
        for event in kind3or10002 {
            if noDuplicates[event.pubkey + String(event.kind)] != nil {
                forDeletion.append(event)
            }
            else {
                noDuplicates[event.pubkey + String(event.kind)] = event
            }
        }
        for toDelete in forDeletion {
            context.delete(toDelete)
        }
        
        var olderKind3DeletedCount = 0
        for remaining in noDuplicates.values {
            if remaining.created_at < Int64(xDaysAgo.timeIntervalSince1970) {
                context.delete(remaining)
                olderKind3DeletedCount = olderKind3DeletedCount + 1
            }
        }
        
        if !forDeletion.isEmpty {
            L.maintenance.info("🧹🧹 Deleted \(forDeletion.count) duplicate kind 3,10002 events")
        }
        if olderKind3DeletedCount > 0 {
            L.maintenance.info("🧹🧹 Deleted \(olderKind3DeletedCount) older kind 3,10002 events")
        }
        
        // ALL OTHER UNKNOWN KINDS
        // OLDER THAN X DAYS
        // PUBKEY NOT IN OWN ACCOUNTS
        // OR PUBKEY OF OWN ACCOUNTS NOT IN SERIALIZED TAGS
        //            context.perform {
        let frOther = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        
        frOther.predicate = NSPredicate(format: "created_at < %i AND NOT kind IN {0,1,3,4,5,6,7,8,20,9734,9735,9802,10002,30023,34235} AND NOT (pubkey IN %@ OR tagsSerialized MATCHES %@)", Int64(xDaysAgo.timeIntervalSince1970), ownAccountPubkeys, regex)
        
        let frOtherbatchDelete = NSBatchDeleteRequest(fetchRequest: frOther)
        frOtherbatchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(frOtherbatchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) unknown kind events")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete unknown kind data")
        }
        
        
        // Posts, Reactions, Zaps where our account is mentioned in tag
        // OLDER THAN 2 MONTHS
        // PUBKEY NOT IN OWN ACCOUNTS
        //            context.perform {
        let frTagsSerialized = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        
        frTagsSerialized.predicate = NSPredicate(format: "(created_at < %i AND kind IN {1,7,9734,9735} AND NOT pubkey IN %@) AND tagsSerialized MATCHES %@", Int64(monthsAgo.timeIntervalSince1970), ownAccountPubkeys, regex)
        
        let frTagsSerializedbatchDelete = NSBatchDeleteRequest(fetchRequest: frTagsSerialized)
        frTagsSerializedbatchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(frTagsSerializedbatchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) replies/reactions/zaps to our accounts")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete replies/reactions/zaps to our accounts")
        }
                
        // Keep imposter cache
        // Keep zapper pubkey cache
        // Without metadata (kind 0 missing)
        let frContacts = NSFetchRequest<NSFetchRequestResult>(entityName: "Contact")
        frContacts.predicate = NSPredicate(format: "couldBeImposter == -1 AND zapperPubkey != nil AND metadata_created_at == 0")
        
        let frContactsbatchDelete = NSBatchDeleteRequest(fetchRequest: frContacts)
        frContactsbatchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(frContactsbatchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) contacts without metadata")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete contacts without metadata")
        }
        
        
        // All contacts not in WoT
        // only if contacts > 15000
        // only if WoT size > 7000
        // only older than 2 months (updated_at)
        // not our own accounts
        
        guard WebOfTrust.shared.allowedKeysCount > 7000 else { return }
        
        // Keep imposter cache
        let frContactsWoT = Contact.fetchRequest()
        frContactsWoT.predicate = NSPredicate(format: "updated_at < %i AND couldBeImposter == -1 AND NOT pubkey IN %@", Int64(monthsAgo.timeIntervalSince1970), ownAccountPubkeys)
        
        // to keep that have private note
        let privateNotePubkeys = Set(CloudPrivateNote.fetchAll(context: context).filter { $0.pubkey != nil }.map { $0.pubkey })
        
        var deletedContacts = 0
        if let contacts = try? context.fetch(frContactsWoT) {
            for contact in contacts {
                if !WebOfTrust.shared.isAllowed(contact.pubkey) && !privateNotePubkeys.contains(contact.pubkey) && contact.couldBeImposter == -1 {
                    context.delete(contact)
                    deletedContacts += 1
                }
            }
        }
        L.maintenance.info("🧹🧹 Deleted \(deletedContacts) old contacts not in Web of Trust")
    }
    
    
    // Check if a migration has already been executed
    static func didRun(migrationCode:migrationCode, context:NSManagedObjectContext) -> Bool {
        let fr = Migration.fetchRequest()
        fr.predicate = NSPredicate(format: "migrationCode == %@", migrationCode.rawValue)
        fr.fetchLimit = 1
        fr.resultType = .countResultType
        return ((try? context.count(for: fr)) ?? 0) > 0
    }
    
    
    // Run once to fill dTag and delete old replacable events
    static func runUseDtagForReplacableEvents(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.useDtagForReplacableEvents, context: context) else { return }
        
        // 1. For each replacable event, save the dtag
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind >= 30000 AND kind < 40000")
        
        guard let replacableEvents = try? context.fetch(fr) else {
            L.maintenance.error("runUseDtagForReplacableEvents: Could not fetch replacable events")
            return
        }
        
        L.maintenance.info("runUseDtagForReplacableEvents: Found \(replacableEvents.count) replacable events")
        
        for event in replacableEvents {
            event.dTag = event.fastTags.first(where: { $0.0 == "d" })?.1 ?? ""
            if event.dTag != "" {
                L.maintenance.info("runUseDtagForReplacableEvents: dTag set to: \(event.dTag) for \(event.id)")
            }
        }
        
        // 2. For each replacable event, find same author + dtag, keep most recent, delete older
        for event in replacableEvents {
            let matches = replacableEvents.filter { $0.pubkey == event.pubkey && $0.dTag == event.dTag }
            if matches.count <= 1 { continue } // if we have just 1 match, no need to delete older
            
            // only keep the most recent
            guard let keep = matches.sorted(by: { $0.created_at > $1.created_at }).first else { continue }
            for match in matches {
                if match != keep {
                    match.mostRecentId = keep.id
                }
            }
        }
        
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.useDtagForReplacableEvents.rawValue
    }
    
    // Run once to delete events without id (old bug)
    static func runDeleteEventsWithoutId(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.deleteEventsWithoutId, context: context) else { return }
        
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id == \"\"")
        
        guard let eventsWithoutId = try? context.fetch(fr) else {
            L.maintenance.error("runDeleteEventsWithoutId: Could not fetch eventsWithoutId")
            return
        }
        
        L.maintenance.info("eventsWithoutId: Found \(eventsWithoutId.count) eventsWithoutId")
        
        for event in eventsWithoutId {
            context.delete(event)
        }
        
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.deleteEventsWithoutId.rawValue
    }
    
    // Run once to put .anyName in fixedName
    static func runInsertFixedNames(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.insertFixedNames, context: context) else { return }
        
        let fr = Contact.fetchRequest()
        fr.predicate = NSPredicate(format: "fixedName == nil")
        
        guard let contacts = try? context.fetch(fr) else {
            L.maintenance.error("runInsertFixedNames: Could not fetch")
            return
        }
        
        L.maintenance.info("runInsertFixedNames: Found \(contacts.count) contacts")
        
        for contact in contacts {
            if contact.anyName != contact.authorKey {
                contact.fixedName = contact.anyName
            }
        }
        
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.insertFixedNames.rawValue
    }
    
    // Run once to put .picture in fixedPfp
    static func runInsertFixedPfps(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.insertFixedPfps, context: context) else { return }
        
        let fr = Contact.fetchRequest()
        fr.predicate = NSPredicate(format: "fixedPfp == nil")
        
        guard let contacts = try? context.fetch(fr) else {
            L.maintenance.error("runInsertFixedPfps: Could not fetch")
            return
        }
        
        L.maintenance.info("runInsertFixedPfps: Found \(contacts.count) contacts")
        
        for contact in contacts {
            contact.fixedPfp = contact.picture
        }
        
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.insertFixedPfps.rawValue
    }
    
    // Run once to fix replies to existing replacable events
    static func runFixArticleReplies(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.fixArticleReplies, context: context) else { return }
        
        // Find all posts referencing an article
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 1 AND tagsSerialized CONTAINS %@", "[\"a\",\"30023:")
        
        if let articleReplies = try? context.fetch(fr) {
            L.maintenance.info("runFixArticleReplies: Found \(articleReplies.count) article replies")
            for reply in articleReplies {
                let event = reply.toNEvent()
                
                // The following code is similar as in .saveEvent()
                if let replyToAtag = event.replyToAtag() { // Comment on article
                    if let dbArticle = Event.fetchReplacableEvent(aTag: replyToAtag.value, context: context) {
                        reply.replyToId = dbArticle.id
                        reply.replyTo = dbArticle
                        L.maintenance.info("runFixArticleReplies: Fixing reply (\(reply.id)) -> \(replyToAtag.value) (article already in DB)")
                    }
                    else {
                        // we don't have the article yet, store aTag in replyToId
                        reply.replyToId = replyToAtag.value
                        L.maintenance.info("runFixArticleReplies: Fixing reply (\(reply.id)) -> \(replyToAtag.value) (article not in DB)")
                    }
                }
                else if let replyToRootAtag = event.replyToRootAtag() {
                    // Comment has article as root, but replying to other comment, not to article.
                    if let dbArticle = Event.fetchReplacableEvent(aTag: replyToRootAtag.value, context: context) {
                        reply.replyToRootId = dbArticle.id
                        reply.replyToRoot = dbArticle
                        L.maintenance.info("runFixArticleReplies: Fixing replyToRoot (\(reply.id)) -> \(replyToRootAtag.value) (article already in DB)")
                    }
                    else {
                        // we don't have the article yet, store aTag in replyToRootId
                        reply.replyToRootId = replyToRootAtag.value
                        L.maintenance.info("runFixArticleReplies: Fixing replyToRoot (\(reply.id)) -> \(replyToRootAtag.value) (article not in DB)")
                    }
                }
                
                if reply.replyToId == nil && reply.replyToRootId != nil { // If there is a replyToRoot but not a reply, set replyToRoot as replyTo
                    reply.replyToId = reply.replyToRootId
                    reply.replyTo = reply.replyToRoot
                }
            }
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.fixArticleReplies.rawValue
    }
    
    // Run once to fix false positives from imposter checking
    // In older versions right after switching accounts it would put the label
    // and then cache the result
    static func runFixImposterFalsePositives(context: NSManagedObjectContext) {
        // removed. no need to run anymore, only run the last one below
    }
    
    // Need to run it again... false positives still
    // And again - found another bug during new account onboarding
    static func runFixImposterFalsePositivesAgainAgain(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.fixImposterFalsePositivesAgainAgain, context: context) else { return }
        
        let frA = CloudAccount.fetchRequest()
        let allAccounts = Array(try! context.fetch(frA))
        
        var imposterCacheFixedCount = 0
        var imposterCacheFollowCount = 0
        for account in allAccounts {
//            guard account.privateKey != nil else { continue }
            for contact in account.follows { // We are following so can't be imposter
                if contact.couldBeImposter == 1 {
                    contact.couldBeImposter = 0
                    imposterCacheFixedCount += 1
                }
                else if contact.couldBeImposter == -1 { // We are following so can't be imposter
                    contact.couldBeImposter = 0
                    imposterCacheFollowCount += 1
                }
            }
        }
        
        L.maintenance.info("fixImposterFalsePositivesAgain: Fixed \(imposterCacheFixedCount) false positives, preset-to-0 \(imposterCacheFollowCount) contacts")
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.fixImposterFalsePositivesAgainAgain.rawValue
    }
    
    // Run once to migrate DM info in "root" DM event to DMState record
    static func runMigrateDMState(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.migrateDMState, context: context) else { return }
        
        let frA = CloudAccount.fetchRequest()
        let allAccounts = Array(try! context.fetch(frA))
        // This one includes read-only accounts
        _ = allAccounts.reduce([String]()) { partialResult, account in
            var newResult = Array(partialResult)
                newResult.append(account.publicKey)
            return newResult
        }
        
        // Need to do per account, because we can have multiple accounts in Nostur, can message eachother,
        // Each account needs its own conversation state.
        
        typealias ConversationKeypair = String // "accountPubkey-contactPubkey"
        typealias AccountPubkey = String
        typealias ContactPubkey = String
        typealias IsAccepted = Bool
        typealias MarkedReadAt = Date?
        
        var dmStates:[ConversationKeypair: (AccountPubkey, ContactPubkey, IsAccepted, MarkedReadAt)] = [:]
        
        let existingDMStates = (try? context.fetch(DMState.fetchRequest())) ?? []
        var existingDMkeys:Set<String> = []
        for state in existingDMStates {
            guard let accountPubkey = state.accountPubkey, let contactPubkey = state.contactPubkey else { continue }
            let key = accountPubkey + "-"  + contactPubkey
            dmStates[key] = (accountPubkey, contactPubkey, state.accepted, state.markedReadAt)
            existingDMkeys.insert(key)
        }
        
        for account in allAccounts {
            let sent = Event.fetchRequest()
            sent.predicate = NSPredicate(format: "kind == 4 AND pubkey == %@", account.publicKey)
            sent.fetchLimit = 9999
            sent.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]

            if let sent = try? context.fetch(sent) {
                for messageSent in sent {
                    // sent is always "accepted"
                    guard let contactPubkey = messageSent.firstP() else { continue }
                    messageSent.otherPubkey = contactPubkey
                    
                    let accountPubkey = messageSent.pubkey
                    
                    guard accountPubkey != contactPubkey else { continue }
                    
                    let markedReadAt = messageSent.lastSeenDMCreatedAt != 0 ? Date(timeIntervalSince1970: TimeInterval(messageSent.lastSeenDMCreatedAt)) : nil
                    
                    // Set or update the DM conversation state, use the most recent markedReadAt (lastSeenDMCreatedAt)
                    if let existingDMState = dmStates[accountPubkey + "-" + contactPubkey], let newerMarkedReadAt = markedReadAt, newerMarkedReadAt > (existingDMState.3 ?? Date(timeIntervalSince1970: 0) ) {
                        dmStates[accountPubkey + "-" + contactPubkey] = (accountPubkey, contactPubkey, true, newerMarkedReadAt)
                    }
                    else {
                        dmStates[accountPubkey + "-" + contactPubkey] = (accountPubkey, contactPubkey, true, markedReadAt)
                    }
                }
            }
            
            
            let received = Event.fetchRequest()
            received.predicate = NSPredicate(
                format: "kind == 4 AND tagsSerialized CONTAINS %@ AND NOT pubkey == %@", serializedP(account.publicKey), account.publicKey)
            received.fetchLimit = 9999
            received.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            if let received = try? context.fetch(received) {
                for messageReceived in received {
                    
                    let contactPubkey = messageReceived.pubkey
                    guard messageReceived.firstP() == account.publicKey || messageReceived.lastP() == account.publicKey else { continue }
                    let accountPubkey = account.publicKey
                    messageReceived.otherPubkey = accountPubkey
                    
                    guard accountPubkey != contactPubkey else { continue }
                    
                    let didSend = dmStates[accountPubkey + "-" + contactPubkey] != nil
                    
                    // received is "accepted" if we manually accepted before, or if we replied
                    if messageReceived.dmAccepted || didSend {
                        let markedReadAt = messageReceived.lastSeenDMCreatedAt != 0 ? Date(timeIntervalSince1970: TimeInterval(messageReceived.lastSeenDMCreatedAt)) : nil
                        
                        // Set or update the DM conversation state, use the most recent markedReadAt (lastSeenDMCreatedAt)
                        if let existingDMState = dmStates[accountPubkey + "-" + contactPubkey], let newerMarkedReadAt = markedReadAt, newerMarkedReadAt > (existingDMState.3 ?? Date(timeIntervalSince1970: 0) ) {
                            dmStates[accountPubkey + "-" + contactPubkey] = (accountPubkey, contactPubkey, true, newerMarkedReadAt)
                        }
                        else {
                            dmStates[accountPubkey + "-" + contactPubkey] = (accountPubkey, contactPubkey, true, markedReadAt)
                        }
                    }
                    else {
                        let markedReadAt = messageReceived.lastSeenDMCreatedAt != 0 ? Date(timeIntervalSince1970: TimeInterval(messageReceived.lastSeenDMCreatedAt)) : nil
                        
                        // Set or update the DM conversation state, use the most recent markedReadAt (lastSeenDMCreatedAt)
                        if let existingDMState = dmStates[accountPubkey + "-" + contactPubkey], let newerMarkedReadAt = markedReadAt, newerMarkedReadAt > (existingDMState.3 ?? Date(timeIntervalSince1970: 0) ) {
                            dmStates[accountPubkey + "-" + contactPubkey] = (accountPubkey, contactPubkey, existingDMState.2, newerMarkedReadAt)
                        }
                        else {
                            dmStates[accountPubkey + "-" + contactPubkey] = (accountPubkey, contactPubkey, false, markedReadAt)
                        }
                    }
                }
            }
        }
        
        for (key, value) in dmStates {
            if existingDMkeys.contains(key) { continue }
            let record = DMState(context: context)
            record.accountPubkey = value.0
            record.contactPubkey = value.1
            record.accepted = value.2
            record.markedReadAt = value.3
        }

                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.migrateDMState.rawValue
    }
    
    static func runTempAlways(context: NSManagedObjectContext) {
        
    }
    
    
    // Run once to fix ZappedContactPubkey not migrated to otherPubkey, ughh Xcode
    static func runFixZappedContactPubkey(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.fixZappedContactPubkey, context: context) else { return }
        
        // Find all zaps 9735
        // if otherPubkey is nil:
        // get it from first P
        // set otherPubkey
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 9735 AND otherPubkey == nil")
        
        var fixed = 0
        if let zaps = try? context.fetch(fr) {
            L.maintenance.info("runFixZappedContactPubkey: Found \(zaps.count) zaps without otherPubkey")
            for zap in zaps {
                if let firstP = zap.firstP() {
                    zap.otherPubkey = firstP
                    zap.zappedContact = Contact.fetchByPubkey(firstP, context: context)
                    fixed += 1
                }
            }
            L.maintenance.info("runFixZappedContactPubkey: Fixed \(fixed) otherPubkey in zaps")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.fixZappedContactPubkey.rawValue
    }
    
    // Run once to put .firstQuote.pubkey in .otherPubkey, for fast reposts notification querying
    static func runPutRepostedPubkeyInOtherPubkey(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.runPutRepostedPubkeyInOtherPubkey, context: context) else { return }
        
        // Find all reposts
        // if otherPubkey is nil:
        // get it from firstQuote
        // if we don't have firstQuote, get it from firstP
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 6 AND otherPubkey == nil")
        
        var fixed = 0
        if let reposts = try? context.fetch(fr) {
            L.maintenance.info("runPutRepostedPubkeyInOtherPubkey: Found \(reposts.count) reposts without otherPubkey")
            for repost in reposts {
                
                // Same code as in saveEvent():
                // Save reposted pubkey in .otherPubkey for easy querying for repost notifications
                // if we already have the firstQuote (reposted post), we use that .pubkey
                if let otherPubkey = repost.firstQuote?.pubkey {
                    repost.otherPubkey = otherPubkey
                    fixed += 1
                } // else we take the pubkey from the tags (should be there)
                else if let firstP = repost.firstP() {
                    repost.otherPubkey = firstP
                    fixed += 1
                }
            }
            L.maintenance.info("runPutRepostedPubkeyInOtherPubkey: Fixed \(fixed) otherPubkey in reposts")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.runPutRepostedPubkeyInOtherPubkey.rawValue
    }
    
    // Run once to put .reactionTo.pubkey in .otherPubkey, for fast reaction notification querying
    static func runPutReactionToPubkeyInOtherPubkey(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.runPutReactionToPubkeyInOtherPubkey, context: context) else { return }
        
        // Find all reposts
        // if otherPubkey is nil:
        // get it from firstQuote
        // if we don't have firstQuote, get it from firstP
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 7 AND otherPubkey == nil")
        
        var fixed = 0
        if let reactions = try? context.fetch(fr) {
            L.maintenance.info("runPutReactionToPubkeyInOtherPubkey: Found \(reactions.count) reactions without otherPubkey")
            for reaction in reactions {
                
                // Similar as in saveEvent()
                if let lastP = reaction.lastP() {
                    reaction.otherPubkey = lastP
                    fixed += 1
                }
                else if let otherPubkey = reaction.reactionTo?.pubkey {
                    reaction.otherPubkey = otherPubkey
                    fixed += 1
                }
            }
            L.maintenance.info("runPutReactionToPubkeyInOtherPubkey: Fixed \(fixed) otherPubkey in reactions")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.runPutReactionToPubkeyInOtherPubkey.rawValue
    }
    
    // Run once to put first A tag in .otherAtag, for fast reaction notification querying
    static func runPutReferencedAtag(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.putReferencedAtag, context: context) else { return }
        
        
        // Only need to live chats now (chat messages and zaps)
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind IN {1311,9735} AND otherAtag == nil")
        
        var fixed = 0
        if let items = try? context.fetch(fr) {
            L.maintenance.info("runPutReferencedAtag: Found \(items.count) items with possible a tag")
            for item in items {
                if let firstA = item.firstA() {
                    item.otherAtag = firstA
                    fixed += 1
                }
            }
            L.maintenance.info("runPutReferencedAtag: Fixed \(fixed) otherAtag in items")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.putReferencedAtag.rawValue
    }
    
    // Migrate Bookmarks to iCloud-ready table
    static func runMigrateBookmarks(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.migrateBookmarks, context: context) else { return }
        
        // find all bookmarks, add them to Bookmark table
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "bookmarkedBy.@count > 0")
        
        var migratedBookmarks:Int = 0
        if let bookmarks = try? context.fetch(fr) {
            L.maintenance.info("migrateBookmarks: Found \(bookmarks.count) bookmarks")
            for bookmark in bookmarks {
                let migratedBookmark = Bookmark(context: context)
                migratedBookmark.eventId = bookmark.id
                migratedBookmark.json = bookmark.toNEvent().eventJson()
                migratedBookmark.createdAt = bookmark.date // (We don't know when the bookmark was added, so use event created_at here)
                migratedBookmarks += 1
            }
            L.maintenance.info("migrateBookmarks: Migrated \(migratedBookmarks) bokmarks")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.migrateBookmarks.rawValue
    }
    
    // Migrate Bookmarks to iCloud-ready table
    static func runMigratePrivateNotes(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.migratePrivateNotes, context: context) else { return }
        
        // Oops code. Uncomment during testing if we need to run this again.
//        let fr0 = CloudPrivateNote.fetchRequest()
//        fr0.predicate = NSPredicate(value: true)
//        if let cpns = try? context.fetch(fr0) {
//            for cpn in cpns {
//                context.delete(cpn)
//            }
//        }
        
        
        // find all private notes, migrate to CloudPrivateNote
        // set type, eventId or pubkey based on type, and json
        let fr = PrivateNote.fetchRequest()
        fr.predicate = NSPredicate(value: true)
        
        var migratedPrivateNotes:Int = 0
        if let privateNotes = try? context.fetch(fr) {
            L.maintenance.info("migratePrivateNotes: Found \(privateNotes.count) private notes")
            for pn in privateNotes {
                if let post = pn.post { // Note on post
                    let migratedPN = CloudPrivateNote(context: context)
                    migratedPN.type = CloudPrivateNote.PrivateNoteType.post.rawValue
                    migratedPN.eventId = post.id
                    migratedPN.content = pn.content
                    migratedPN.createdAt = pn.createdAt
                    migratedPN.updatedAt = pn.updatedAt
                    migratedPN.json = post.toNEvent().eventJson()
                }
                else if let contact = pn.contact { // Note on contat
                    let migratedPN = CloudPrivateNote(context: context)
                    migratedPN.type = CloudPrivateNote.PrivateNoteType.contact.rawValue
                    migratedPN.pubkey = contact.pubkey
                    migratedPN.content = pn.content
                    migratedPN.createdAt = pn.createdAt
                    migratedPN.updatedAt = pn.updatedAt
                    migratedPN.json = Event.fetchReplacableEvent(0, pubkey: contact.pubkey, context: context)?.toNEvent().eventJson() // probaby won't have the kind 0 eventd
                    
                }
                migratedPrivateNotes += 1
            }
            L.maintenance.info("migratePrivateNotes: Migrated \(migratedPrivateNotes) private notes")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.migratePrivateNotes.rawValue
    }
    
    // Migrate Custom feeds to iCloud-ready table
    static func runMigrateCustomFeeds(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.migrateCustomFeeds, context: context) else { return }
        
        // Oops code. Uncomment during testing if we need to run this again.
//        let fr0 = CloudFeed.fetchRequest()
//        fr0.predicate = NSPredicate(value: true)
//        if let cfs = try? context.fetch(fr0) {
//            for cf in cfs {
//                context.delete(cf)
//            }
//        }
        
        
        // find all custom feeds, migrate to CloudPrivateNote
        // set same attributes and convert Contacts and Relays to space seperated strings of pubkeys and relay urls
        let fr = NosturList.fetchRequest()
        fr.predicate = NSPredicate(value: true)
        
        var migratedCustomFeed:Int = 0
        if let customFeeds = try? context.fetch(fr) {
            L.maintenance.info("migrateCustomFeeds: Found \(customFeeds.count) custom feeds")
            for cf in customFeeds {
                if let type = cf.type, type == ListType.relays.rawValue {
                    // Relays
                    let migratedCF = CloudFeed(context: context)
                    migratedCF.type = ListType.relays.rawValue
                    migratedCF.createdAt = cf.createdAt ?? .now
                    migratedCF.followingHashtags_ = cf.followingHashtags_
                    migratedCF.id = cf.id
                    migratedCF.name = cf.name
                    migratedCF.refreshedAt = cf.refreshedAt
                    migratedCF.showAsTab = cf.showAsTab
                    migratedCF.wotEnabled = cf.wotEnabled
                    migratedCF.relays = cf.relays_.compactMap { $0.url }.joined(separator: " ")
                }
                else { // Pubkeys
                    let migratedCF = CloudFeed(context: context)
                    migratedCF.type = ListType.pubkeys.rawValue
                    migratedCF.createdAt = cf.createdAt ?? .now
                    migratedCF.followingHashtags_ = cf.followingHashtags_
                    migratedCF.id = cf.id
                    migratedCF.name = cf.name
                    migratedCF.refreshedAt = cf.refreshedAt
                    migratedCF.showAsTab = cf.showAsTab
                    migratedCF.wotEnabled = cf.wotEnabled
                    migratedCF.contactPubkeys = Set(cf.contacts_.map { $0.pubkey })
                }
                migratedCustomFeed += 1
            }
            L.maintenance.info("migrateCustomFeeds: Migrated \(migratedCustomFeed) custom feeds")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.migrateCustomFeeds.rawValue
    }
    
    
    // Migrate Blocks/Muted Conversations to iCloud-ready table
    static func runMigrateBlocks(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.migrateBlocks, context: context) else { return }
        
        // for all accounts, get mutedRootIds and blockedPubkeys
        var mutedRootIds = Set<String>()
        var blockedPubkeys = Set<String>()
        
        for account in Account.fetchAccounts(context: context) {
            blockedPubkeys.formUnion(account.blockedPubkeys_)
            mutedRootIds.formUnion(account.mutedRootIds_)
        }
        
        L.maintenance.info("runMigrateBlocks: migrating \(mutedRootIds.count) muted conversations and \(blockedPubkeys.count) blocked contacts")
        
        // Create new records in iCloud tables
        for blockedPubkey in blockedPubkeys {
            let block = CloudBlocked(context: context)
            block.type = .contact
            block.fixedName = Contact.fetchByPubkey(blockedPubkey, context: context)?.fixedName ?? ""
            block.pubkey = blockedPubkey
            block.createdAt_ = .now // use .now because we don't know at migration
        }
        
        for mutedRootId in mutedRootIds {
            let block = CloudBlocked(context: context)
            block.type = .post
            block.eventId = mutedRootId
            block.createdAt_ = .now // use .now because we don't know at migration
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.migrateBlocks.rawValue
    }
    
    // Migrate Accounts to iCloud-ready table
    static func runMigrateAccounts(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.migrateAccounts, context: context) else { return }
        
        // Oops code. Uncomment during testing if we need to run this again.
//        let fr0 = CloudAccount.fetchRequest()
//        fr0.predicate = NSPredicate(value: true)
//        if let cfs = try? context.fetch(fr0) {
//            for cf in cfs {
//                context.delete(cf)
//            }
//        }
        
        
        // find all Accounts, migrate to CloudAccount
        // set same attributes and convert follows to followingPubkeys
        let fr = Account.fetchRequest()
        fr.predicate = NSPredicate(value: true)
        
        var migratedAccounts:Int = 0
        if let accounts = try? context.fetch(fr) {
            L.maintenance.info("migrateAccounts: Found \(accounts.count) accounts")
            for account in accounts {
                let migrated = CloudAccount(context: context)
                migrated.about_ = account.about
                migrated.banner_ = account.banner
                migrated.createdAt = account.createdAt
                migrated.display_name_ = account.display_name
                migrated.flags = account.flags
                migrated.followingHashtags_ = account.followingHashtags_
                
                // Account.follows DB relation is removed, so we fallback to kind 3 now
                if let followingList = Event.fetchReplacableEvent(3, pubkey: account.publicKey, context: context) {
                    let followingPubkeys = followingList.fastPs.map { $0.1 }
                    let followingContacts = Contact.fetchByPubkeys(followingPubkeys, context: context)
                    migrated.followingPubkeys_ = followingContacts.filter { !$0.privateFollow } .map { $0.pubkey }.joined(separator: " ")
                    migrated.privateFollowingPubkeys_ = followingContacts.filter { $0.privateFollow } .map { $0.pubkey }.joined(separator: " ")
                }

                migrated.isNC = account.isNC
                migrated.lastFollowerCreatedAt = account.lastFollowerCreatedAt
                migrated.lastProfileReceivedAt = account.lastProfileReceivedAt
                migrated.lastSeenDMRequestCreatedAt = account.lastSeenDMRequestCreatedAt
                migrated.lastSeenPostCreatedAt = account.lastSeenPostCreatedAt
                migrated.lastSeenReactionCreatedAt = account.lastSeenReactionCreatedAt
                migrated.lastSeenRepostCreatedAt = account.lastSeenRepostCreatedAt
                migrated.lastSeenZapCreatedAt = account.lastSeenZapCreatedAt
                migrated.lud06_ = account.lud06
                migrated.lud16_ = account.lud16
                migrated.name_ = account.name
                migrated.ncRelay_ = account.ncRelay
                migrated.nip05_ = account.nip05
                migrated.picture_ = account.picture
                migrated.publicKey_ = account.publicKey
                
                if let pk = account.privateKey { // This should sync for accounts that may not have .synchronizable(true) when initially created
                    AccountManager.shared.storePrivateKey(privateKeyHex: pk, forPublicKeyHex: account.publicKey)
                    migrated.flagsSet.insert("full_account")
                }
                
                migratedAccounts += 1
            }
            L.maintenance.info("migrateAccounts: Migrated \(migratedAccounts) accounts")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.migrateAccounts.rawValue
    }
    
    // Migrate DM conversation states to iCloud-ready table
    static func runMigrateDMsToCloud(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.migrateDMsToCloud, context: context) else { return }
        
        // Oops code. Uncomment during testing if we need to run this again.
//        let fr0 = CloudDMState.fetchRequest()
//        fr0.predicate = NSPredicate(value: true)
//        if let dmStates = try? context.fetch(fr0) {
//            for dmState in dmStates {
//                context.delete(dmState)
//            }
//        }
        
        let fr = DMState.fetchRequest()
        fr.predicate = NSPredicate(value: true)
        
        var migratedDMStates:Int = 0
        if let dmStates = try? context.fetch(fr) {
            L.maintenance.info("migrateDMs: Found \(dmStates.count) DM conversations")
            for dmState in dmStates {
                let migratedDMState = CloudDMState(context: context)
                migratedDMState.accepted = dmState.accepted
                migratedDMState.accountPubkey_ = dmState.accountPubkey
                migratedDMState.contactPubkey_ = dmState.contactPubkey
                migratedDMState.markedReadAt_ = dmState.markedReadAt
                migratedDMState.isPinned = false
                migratedDMState.isHidden = false
                migratedDMStates += 1
            }
            L.maintenance.info("migrateDMs: Migrated \(migratedDMStates) DM conversations")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.migrateDMsToCloud.rawValue
    }
    
    // Fix private follows
    static func runFixPrivateFollows(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.fixPrivateFollows, context: context) else { return }
        
        // find all Accounts, migrate to CloudAccount
        // set same attributes and convert follows to followingPubkeys
        let fr = CloudAccount.fetchRequest()
        fr.predicate = NSPredicate(value: true)
        
        var fixed:Int = 0
        if let accounts = try? context.fetch(fr) {
            L.maintenance.info("fixPrivateFollows: Found \(accounts.count) accounts")
            for account in accounts {
                let privateFollows = Set(account.follows.filter { $0.privateFollow }.map { $0.pubkey })
                account.privateFollowingPubkeys = privateFollows
                fixed += 1
            }
            L.maintenance.info("fixPrivateFollows: Fixed \(fixed) accounts")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.fixPrivateFollows.rawValue
    }
    
    // Migrate Relays to iCloud-ready table
    static func runMigrateRelays(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.migrateRelays, context: context) else { return }
        
        let fr = Relay.fetchRequest()
        fr.predicate = NSPredicate(value: true)
        
        var migrateRelays:Int = 0
        if let relays = try? context.fetch(fr) {
            L.maintenance.info("migrateRelays: Found \(relays.count) relays")
            for r in relays {
                // Relays
                let migratedRelay = CloudRelay(context: context)
                migratedRelay.createdAt_ = (r.createdAt ?? .now)
                migratedRelay.excludedPubkeys_ = r.excludedPubkeys_
                migratedRelay.read = r.read
                migratedRelay.write = r.write
                migratedRelay.url_ = r.url
                migrateRelays += 1
            }
            L.maintenance.info("migrateCustomFeeds: Migrated \(migrateRelays) relays")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.migrateRelays.rawValue
    }
    
    // Add "full_account" flag to accounts for which we have private key
    static func runSaveFullAccountFlag(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.saveFullAccountFlag, context: context) else { return }
        
        let accounts = CloudAccount.fetchAccounts(context: context)
        
        for account in accounts {
            if account.privateKey != nil {
                account.flagsSet.insert("full_account")
            }
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.saveFullAccountFlag.rawValue
    }
    
    // Fix missing Cloud DM States: A received DM could be saved under a read-only alt account (as sender), if that account is the sender.
    // Here we create the missing DM state for the receiver
    static func runFixMissingDMStates(context: NSManagedObjectContext, firstRun: Bool = true) {
        
        // Run at one time at startup, or again if firstRun is false
        guard !firstRun || !Self.didRun(migrationCode: migrationCode.fixMissingDMStates, context: context) else { return }
        
        // Find all DMs sent to full accounts as receiver
        
        // Our full account pubkeys
        let accounts = CloudAccount.fetchAccounts(context: context)
            .filter { $0.flagsSet.contains("full_account") }
        let fullAccountPubkeys = accounts.map { $0.publicKey }
        
        guard fullAccountPubkeys.count > 0 else { return }
        
        // Find DMs sent to our full account pubkeys
        let fr1 = Event.fetchRequest()
        fr1.predicate = NSPredicate(format: "kind == 4 AND NOT otherPubkey == nil AND otherPubkey IN %@", fullAccountPubkeys)
        guard let dmsReceived = try? context.fetch(fr1) else { return }
        
        // Which DM states do we already have?
        let fr2 = CloudDMState.fetchRequest()
        fr2.predicate = NSPredicate(format: "NOT accountPubkey_ == nil AND accountPubkey_ IN %@", fullAccountPubkeys)
        guard let dmStates = try? context.fetch(fr2) else { return }
        
        var createdPairs: Set<String> = [] // Keep track of accountPubkey + otherPubkey pairs we create here so we don't create duplicates
        
        // Create the missing DM states. (our account + other pubkey)
        for dmReceived in dmsReceived {
            guard let dmReceivedOtherPubkey = dmReceived.otherPubkey else { continue }
            
            // Skip if we already have DM state for this
            guard !dmStates.contains(where: { dmState in
                guard let accountPubkey = dmState.accountPubkey_, let otherPubkey = dmState.contactPubkey_ else {
                    return false
                }
                if dmReceived.pubkey == otherPubkey && dmReceivedOtherPubkey == accountPubkey {
                    return true
                }
                return false
            })
            else { // Skip
                continue
            }
            
            let pairId = dmReceivedOtherPubkey + dmReceived.pubkey
            
            // Skip if we already created a new DMState for this pair
            guard !createdPairs.contains(pairId) else { continue }
            
            // We don't have it, so create it
            let newDMState = CloudDMState(context: context)
            newDMState.accepted = false
            newDMState.accountPubkey_ = dmReceivedOtherPubkey
            newDMState.contactPubkey_ = dmReceived.pubkey
            createdPairs.insert(pairId)
            L.maintenance.info("runFixMissingDMStates: Create new DM state for \(dmReceivedOtherPubkey) - \(dmReceived.pubkey)")
        }
        
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.fixMissingDMStates.rawValue
    }
    
    // Update Keychain info. Change from .whenUnlocked to .afterFirstUnlock and store name
    static func runUpdateKeychainInfo(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.updateKeychainInfo, context: context) else { return }
        
        // change to .afterFirstUnlock
        
        // store .anyName so recovery on other device is user friendly (show list of accounts found to recover)
        
        let accounts = CloudAccount.fetchAccounts(context: context)
        
        let keychain = Keychain(service: "nostur.com.Nostur")
            .synchronizable(true)
        let items = keychain.allItems()
        for item in items {
            let pubkey = item["key"] as! String
            let nameOrNpub = accounts.first(where: { $0.publicKey == pubkey })?.anyName ?? npub(pubkey)
            guard let pk = try? keychain.get(pubkey) else { continue }
            do {
                try keychain
                    .label(nameOrNpub)
                    .accessibility(.afterFirstUnlock)
                    .set(pk, key: pubkey)
                
                L.maintenance.info("updateKeychainInfo: updated \(nameOrNpub)")
            } catch {
                L.og.error("🔴🔴🔴 Could not update keychain")
            }
        }
        
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.updateKeychainInfo.rawValue
    }
    
    // Migrate ListState fields to CloudFeed
    static func runMigrateListStateToCustomFeeds(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.migrateListStateToCloudFeed, context: context) else { return }
        

        // For every existing CloudFeed, find the related ListState, and migrate hideReplies to repliesEnabled (inverted)
        let fr = CloudFeed.fetchRequest()
        fr.predicate = NSPredicate(value: true)
        
        var migratedListStates: Int = 0
        if let customFeeds = try? context.fetch(fr) {
            L.maintenance.info("runMigrateListStateToCustomFeeds: Found \(customFeeds.count) custom feeds")
            for cf in customFeeds {
                
                guard cf.subscriptionId.starts(with: "List-") else { continue }
                
                // We have related ListState?
                let fr = ListState.fetchRequest()
                fr.predicate = NSPredicate(format: "listId == %@", cf.subscriptionId)
                
                if let listState =  try? context.fetch(fr).first {
                    cf.repliesEnabled = !listState.hideReplies
                    migratedListStates += 1
                }
            }
            L.maintenance.info("runMigrateListStateToCustomFeeds: Migrated \(migratedListStates) list states")
        }
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.migrateListStateToCloudFeed.rawValue
    }
    
    // Run once to fill aTag
    // Removed, can't query relays for multiple aTags so nevermind. Maybe useful in the future but not now
//    static func runSetAtagForReplacableEvents(context: NSManagedObjectContext) {
//        guard !Self.didRun(migrationCode: migrationCode.runSetAtagForReplacableEvents, context: context) else { return }
//        
//        // 1. For each replacable event, save the atag
//        let fr = Event.fetchRequest()
//        fr.predicate = NSPredicate(format: "kind >= 30000 AND kind < 40000")
//        
//        guard let replacableEvents = try? context.fetch(fr) else {
//            L.maintenance.error("runSetAtagForReplacableEvents: Could not fetch replacable events")
//            return
//        }
//        
//        L.maintenance.info("runSetAtagForReplacableEvents: Found \(replacableEvents.count) replacable events")
//        
//        for event in replacableEvents {
//            event.aTag = (String(event.kind) + ":" + event.pubkey  + ":" + event.dTag)
//            if event.aTag != "" {
//                L.maintenance.info("runSetAtagForReplacableEvents: aTag set to: \(event.aTag) for \(event.id)")
//            }
//        }
//    
//        let migration = Migration(context: context)
//        migration.migrationCode = migrationCode.runSetAtagForReplacableEvents.rawValue
//    }
    
    // All available migrations
    enum migrationCode:String {
        
        // Run once to delete events without id (old bug)
        case deleteEventsWithoutId = "deleteEventsWithoutId"
        
        // Run once to fill dTag and delete old replacable events
        case useDtagForReplacableEvents = "useDtagForReplacableEvents"
        
        // Run once to put .anyName in fixedName
        case insertFixedNames = "insertFixedNames"
        
        // Run once to put .picture in fixedPfp
        case insertFixedPfps = "insertFixedPfps"
        
        // Run once to fix replies to existing replacable events
        case fixArticleReplies = "fixArticleReplies"
        
        // Run once to fix false positive results incorrectly cached
        case fixImposterFalsePositives = "fixImposterFalsePositives"
        
        case migrateDMState = "runMigrateDMState20231017"
        
        // Need to run it again... false positives still
        // And again - found another bug during new account onboarding
        case fixImposterFalsePositivesAgainAgain = "fixImposterFalsePositivesAgainAgain"
        
        // Move zappedContactPubkey to otherPubkey
        case fixZappedContactPubkey = "fixZappedContactPubkey"
        
        // Cache .firstQuote.pubkey in .otherPubkey
        case runPutRepostedPubkeyInOtherPubkey = "runPutRepostedPubkeyInOtherPubkey"
        
        // Cache .reactionTo.pubkey in .otherPubkey
        case runPutReactionToPubkeyInOtherPubkey = "runPutReactionToPubkeyInOtherPubkey"  
        
        // Migrate Bookmarks to iCloud table
        case migrateBookmarks = "migrateBookmarks03112023"
        
        // Migrate Private Notes to iCloud
        case migratePrivateNotes = "migratePrivateNotes"        
        
        // Migrate Custom feeds to iCloud
        case migrateCustomFeeds = "migrateCustomFeeds"   
        
        // Migrate blocks/mutes to iCloud
        case migrateBlocks = "migrateBlocks"
        
        // Migrate Accounts to iCloud
        case migrateAccounts = "migrateAccounts"
        
        // Migrate DM conversation state to iCloud
        case migrateDMsToCloud = "migrateDMs"   
        
        // Fix private follows
        case fixPrivateFollows = "fixPrivateFollows"
        
        // Migrate relays state to iCloud
        case migrateRelays = "migrateRelays"        
        
        // Update keychain info
        case updateKeychainInfo = "updateKeychainInfo"
        
        // Add "full_account" flag
        case saveFullAccountFlag = "saveFullAccountFlag4"        

        // Fix missing DM States
        case fixMissingDMStates = "fixMissingDMStates"
        
        // Migrate ListState fields to CloudFeed
        case migrateListStateToCloudFeed = "migrateListStateToCloudFeed"
        
        // Put first A tag in .otherAtag
        case putReferencedAtag = "putReferencedAtag"
        
        // make aTag field for easy lookups
        // Removed, can't query relays for multiple aTags so nevermind. Maybe useful in the future but not now
//        case runSetAtagForReplacableEvents = "runSetAtagForReplacableEvents"
    }
}
