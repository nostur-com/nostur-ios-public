//
//  Maintenance.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import Foundation
import CoreData
import KeychainAccess
import NostrEssentials

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
                        
                        // don't try to write if payment is required for new first-time user
                        bootstrapRelay.write = ["wss://nostr.wine"].contains(url) ? false : true
                        
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
#if DEBUG
        L.maintenance.info("Starting version based maintenance")
#endif
        await context.perform {
            Self.upgradeToFullWidth(context: context)
            Self.runAddKtag(context: context)
            Self.runRestoreFooterButtons(context: context)
            Self.runDeleteEventsWithoutId(context: context)
            Self.runUseDtagForReplacableEvents(context: context)
//            Self.runSetAtagForReplacableEvents(context: context) // Removed, can't query relays for multiple aTags so nevermind. Maybe useful in the future but not now
            Self.runInsertFixedNames(context: context)
            Self.runFixArticleReplies(context: context)
            Self.runFixImposterFalsePositivesAgainAgain(context: context)
            Self.runFixZappedContactPubkey(context: context)
            Self.runPutRepostedPubkeyInOtherPubkey(context: context)
            Self.runPutReactionToPubkeyInOtherPubkey(context: context)
            Self.runUpdateKeychainInfo(context: context)
            Self.runSaveFullAccountFlag(context: context)
            Self.runFixMissingDMStates(context: context)
            Self.runUpgradeDMformat(context: context)
            Self.runInsertFixedPfps(context: context)
            Self.runPutReferencedAtag(context: context)
            Self.runSetCloudFeedOrder(context: context)
            Self.runTempAlways(context: context)
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
            Self.audioDownloadCacheCleanUp()
            Self.databaseCleanUp(context)
            Self.runFixMissingDMStates(force: true, context: context)
            Self.runUpgradeDMformat(force: true, context: context)
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
    
    static func audioDownloadCacheCleanUp() {
        let tmpPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let ownRecordingsPath = tmpPath.appendingPathComponent("a0-own-recordings")
        let otherAudioFilesPath = tmpPath.appendingPathComponent("a0")
        
        // Define 8-hour threshold
        let eightHoursAgo = Date().addingTimeInterval(-2 * 60 * 60)
        
        // Clean up ownRecordingsPath
        if FileManager.default.fileExists(atPath: ownRecordingsPath.path) {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: ownRecordingsPath,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: [.skipsHiddenFiles]
                )
                for fileURL in fileURLs {
                    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    if let creationDate = attributes[.creationDate] as? Date,
                       creationDate < eightHoursAgo {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                }
            } catch {
                L.maintenance.error("Error cleaning own recordings cache: \(error)")
            }
        }
        
        // Clean up otherAudioFilesPath
        if FileManager.default.fileExists(atPath: otherAudioFilesPath.path) {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: otherAudioFilesPath,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: [.skipsHiddenFiles]
                )
                for fileURL in fileURLs {
                    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    if let creationDate = attributes[.creationDate] as? Date,
                       creationDate < eightHoursAgo {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                }
            } catch {
                L.maintenance.error("Error cleaning other audio files cache: \(error)")
            }
        }
    }
    
    // TODO: NEED TO INVERT, DELETE ALL EXCEPT.. (instead of now: delete only *these*)
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
        
        let xDaysAgo = IS_CATALYST ? Date.now.addingTimeInterval(-2_678_400) : Date.now.addingTimeInterval(-345_600) // 4 days on phone, 31 days on Desktop
        
        
        
        // CLEAN UP EVENTS WITHOUT SIG (BUG FROM PostPreview)
        let frNoSig = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        frNoSig.predicate = NSPredicate(format: "(sig == nil OR sig == \"\") AND flags != \"nsecbunker_unsigned\" AND otherId == nil")
        
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
        
        
        
        
        // KIND 1,1111,1222,1244,4,14,5,6,20,9802,30023,34235,34236
        // OLDER THAN X DAYS
        // IS NOT BOOKMARKED
        // IS NOT OWN EVENT
        // DOES NOT HAVE OUR PUBKEY IN p (Notifications)
        // DONT DELETE MUTED BLOCKED, SO OUR BLOCK LIST STILL FUNCTIONS....
        // DONT DELETE POSTS THAT SHOULD BE SAVED FOR LOCAL FEED STATE RESTORE (LocalFeedState.onScreenIds/.parentIds) ONLY PINNED TABS (CLOUDFEED)
        // TODO: DONT EXPORT MUTED / BLOCKED. KEEP HERE SO WE DONT HAVE TO KEEP ..REPARSING
        
        let feedStateIdsToKeep: Set<String> = Set(LocalFeedStateManager.shared.getFeedStates()
            .flatMap { $0.onScreenIds + Array($0.parentIds) }) // All on screen ids and parent ids from all feed states in 1 set.
        
        // Ids to keep: own bookmarks, privatenotes
        let mergedIds = Set(ownAccountBookmarkIds).union(Set(ownAccountPrivateNoteEventIds)).union(feedStateIdsToKeep)
        
        let fr16 = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        fr16.predicate = NSPredicate(format: "created_at < %i AND kind IN {1,1111,1222,1244,4,14,5,6,20,9802,30311,30023,34235,34236} AND NOT id IN %@ AND NOT (pubkey IN %@ OR tagsSerialized MATCHES %@)", Int64(xDaysAgo.timeIntervalSince1970), mergedIds, ownAccountPubkeys, regex)
        
        let fr16batchDelete = NSBatchDeleteRequest(fetchRequest: fr16)
        fr16batchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(fr16batchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) kind {1,1111,1222,1244,4,14,5,6,20,9802,30311,30023,34235} events - keeping \(mergedIds.count) ids")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete {1,1111,1222,1244,4,14,5,6,20,9802,30311,30023,34235,34236} data")
        }
        
        
        // KIND 7,8
        // OLDER THAN X DAYS
        // PUBKEY NOT IN OWN ACCOUNTS
        // OR PUBKEY OF OWN ACCOUNTS NOT IN SERIALIZED TAGS
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

        
        // DELETE OLDER KIND 3 + 10002 + 10050 EVENTS
        // BUT NOT OUR OWN OR THOSE WE ARE FOLLOWING (FOR WoT follows-follows)
        // AND NOT OUR PUBKEY IN p (is following us, for following notifications)
        
        var followingPubkeys = Set(ownAccountPubkeys)
        for account in allAccounts {
            if account.privateKey != nil {
                followingPubkeys = followingPubkeys.union(account.followingPubkeys)
            }
        }
        
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.predicate = NSPredicate(format: "kind IN {3,10002,10050} AND NOT (pubkey IN %@ OR tagsSerialized MATCHES %@)", followingPubkeys, regex)
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
            L.maintenance.info("🧹🧹 Deleted \(forDeletion.count) duplicate kind 3,10002,10050 events")
        }
        if olderKind3DeletedCount > 0 {
            L.maintenance.info("🧹🧹 Deleted \(olderKind3DeletedCount) older kind 3,10002,10050 events")
        }
        
        // DELETE ALL REPLACEABLE EVENTS THAT ARE NOT THE MOST RECENT
        let frReplaceableDelete = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        
        frReplaceableDelete.predicate = NSPredicate(format: "kind >= 30000 AND kind < 40000 AND NOT mostRecentId = nil")
        
        let frReplaceableBatchDelete = NSBatchDeleteRequest(fetchRequest: frReplaceableDelete)
        frReplaceableBatchDelete.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(frReplaceableBatchDelete) as! NSBatchDeleteResult
            if let count = result.result as? Int, count > 0 {
                L.maintenance.info("🧹🧹 Deleted \(count) replaceable events")
            }
        } catch {
            L.maintenance.info("🔴🔴 Failed to delete replaceable events")
        }
        
        // ALL OTHER UNKNOWN KINDS
        // OLDER THAN X DAYS
        // PUBKEY NOT IN OWN ACCOUNTS
        // OR PUBKEY OF OWN ACCOUNTS NOT IN SERIALIZED TAGS
        let frOther = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        
        frOther.predicate = NSPredicate(format: "created_at < %i AND NOT kind IN {0,1,1111,1222,1244,3,4,14,5,6,7,8,20,9734,9735,9802,10002,10050,30311,30023,34235,34236} AND NOT (pubkey IN %@ OR tagsSerialized MATCHES %@)", Int64(xDaysAgo.timeIntervalSince1970), ownAccountPubkeys, regex)
        
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
        let frTagsSerialized = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        
        frTagsSerialized.predicate = NSPredicate(format: "(created_at < %i AND kind IN {1,1111,1222,1244,7,9734,9735} AND NOT pubkey IN %@) AND tagsSerialized MATCHES %@", Int64(monthsAgo.timeIntervalSince1970), ownAccountPubkeys, regex)
        
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
        // not our own accounts + following (followingPubkeys = own + following)
        let frContacts = NSFetchRequest<NSFetchRequestResult>(entityName: "Contact")
        frContacts.predicate = NSPredicate(format: "couldBeImposter == -1 AND zapperPubkey == nil AND metadata_created_at == 0 AND NOT pubkey IN %@", followingPubkeys)
        
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
        // not our own accounts + following (followingPubkeys = own + following)
        
        guard WebOfTrust.shared.allowedKeysCount > 7000 else { return }
        
        // Keep imposter cache
        let frContactsWoT = Contact.fetchRequest()
        frContactsWoT.predicate = NSPredicate(format: "updated_at < %i AND couldBeImposter == -1 AND NOT pubkey IN %@", Int64(monthsAgo.timeIntervalSince1970), followingPubkeys)
        
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
    
    // Run once to add kTag
    static func runAddKtag(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.addKtag, context: context) else { return }
        
        // 1. For each kind:1 add k-tag to (backwards compatible other kind)
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 1")
        
        guard let kind1s = try? context.fetch(fr) else {
            L.maintenance.error("runAddKtag: Could not fetch (runAddKtag)")
            return
        }
        
        L.maintenance.info("runAddKtag: Found \(kind1s.count) events")
        
        var countKtags = 0
        for event in kind1s {
            if let kTag = event.fastTags.first(where: { $0.0 == "k" })?.1, let kTagInt = Int64(kTag) {
                event.kTag = kTagInt
                countKtags += 1
            }
        }
        
        if countKtags > 0 {
            L.maintenance.info("runAddKtag: kTag updated for \(countKtags) events")
        }
        
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.addKtag.rawValue
    }
    
    // Run once to apply full width on iOS 26 (remove toggle)
    static func upgradeToFullWidth(context: NSManagedObjectContext) {
        if #available(iOS 26.0, *) {
            guard !Self.didRun(migrationCode: migrationCode.upgradeToFullWidth, context: context) else { return }
            
            SettingsStore.shared.fullWidthImages = true
            
            let migration = Migration(context: context)
            migration.migrationCode = migrationCode.upgradeToFullWidth.rawValue
        }
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
                    contact.similarToPubkey = nil
                    imposterCacheFixedCount += 1
                }
                else if contact.couldBeImposter == -1 { // We are following so can't be imposter
                    contact.couldBeImposter = 0
                    contact.similarToPubkey = nil
                    imposterCacheFollowCount += 1
                }
            }
        }
        
        L.maintenance.info("fixImposterFalsePositivesAgain: Fixed \(imposterCacheFixedCount) false positives, preset-to-0 \(imposterCacheFollowCount) contacts")
                
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.fixImposterFalsePositivesAgainAgain.rawValue
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
    static func runFixMissingDMStates(force: Bool = false, context: NSManagedObjectContext) {
        
        // Run at one time at startup, or again if force is true
        guard force || !Self.didRun(migrationCode: migrationCode.fixMissingDMStatesAgain, context: context) else { return }
        
        // Find all DMs sent to full accounts as receiver
        
        // Our full account pubkeys
        let accounts = CloudAccount.fetchAccounts(context: context)
            .filter { $0.flagsSet.contains("full_account") }
        let fullAccountPubkeys = accounts.map { $0.publicKey }
        
        guard fullAccountPubkeys.count > 0 else { return }
        
        // Find DMs sent to our full account pubkeys
        let fr1 = Event.fetchRequest()
        fr1.predicate = NSPredicate(format: "kind IN {4,14} AND NOT otherPubkey == nil AND otherPubkey IN %@", fullAccountPubkeys)
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
        migration.migrationCode = migrationCode.fixMissingDMStatesAgain.rawValue
    }
    
    // Upgrade to new DM format
    static func runUpgradeDMformat(force: Bool = false, context: NSManagedObjectContext) {
        guard force || !Self.didRun(migrationCode: migrationCode.upgradeDMformat, context: context) else { return }
        
        // track timestamps and initiatorPubkey, newestId to make blurb, ourNewest to set markedReadAt
        var earliestAndNewestByGroupId: [String: (earliest: Int64, initiatorPubkey: String?, newest: Int64, newestId: String, didSend: Bool, ourNewest: Int64?)] = [:]
        
        // get all kind 4 + 14
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind IN %@", [4,14])
        let allDMs = (try? context.fetch(fr)) ?? []
        
        var groupIdsSetCounter = 0
        
        // Our full account pubkeys
        let accounts = CloudAccount.fetchAccounts(context: context)
            .filter { $0.flagsSet.contains("full_account") }
        let fullAccountPubkeys = accounts.map { $0.publicKey }
        
        // set .groupId on all kind 4, 14
        // track earliest and newest message for
        // 1) initiator pubkey (for WoT)
        // 2) newest for last received message and blurb
        // also track did we send (to auto .accept = true) and set markReadAt to at least .created_at of our own messagfe
        for dmEvent in allDMs {
            groupIdsSetCounter += 1
            let groupId = dmConversationId(event: dmEvent)
            dmEvent.groupId = groupId
            
            // track earliest timestamp and initiatorPubkey, and newest timestamp for last message received blurb
            if let timestamps = earliestAndNewestByGroupId[groupId] {
                // did we send from our account?
                let didSend = fullAccountPubkeys.contains(dmEvent.pubkey) || timestamps.didSend
                
                // update newest for last message timestamp
                let newest = dmEvent.created_at > timestamps.newest ? dmEvent.created_at : timestamps.newest
                
                // update newest id for blurb
                let newestId = dmEvent.created_at > timestamps.newest ? dmEvent.id : timestamps.newestId
                
                // update our newest for markedReadAt
                let ourNewest: Int64? = fullAccountPubkeys.contains(dmEvent.pubkey) && (dmEvent.created_at > timestamps.ourNewest ?? 0) ? dmEvent.created_at : timestamps.ourNewest
                
                // update earliest for iniatorPubkey
                let earliest = dmEvent.created_at < timestamps.earliest ? dmEvent.created_at : timestamps.earliest
                
                // update earliest initiatorPubkey
                let initiatorPubkey = dmEvent.created_at < timestamps.earliest ? dmEvent.pubkey : timestamps.initiatorPubkey
                
                // store results as tuple in dict
                earliestAndNewestByGroupId[groupId] = (earliest: earliest, initiatorPubkey: initiatorPubkey, newest: newest, newestId: newestId, didSend: didSend, ourNewest: ourNewest)
            }
            
            // insert new if there wasn't any match before
            if earliestAndNewestByGroupId[groupId] == nil {
                let didSend = fullAccountPubkeys.contains(dmEvent.pubkey)
                let ourNewest: Int64? = didSend ? dmEvent.created_at : nil
                earliestAndNewestByGroupId[groupId] = (earliest: dmEvent.created_at, initiatorPubkey: dmEvent.pubkey, newest: dmEvent.created_at, newestId: dmEvent.id, didSend: didSend, ourNewest: ourNewest)
            }
        }
        
        // update participants and update last received timestamp and set initiator pubkey
        let fr2 = CloudDMState.fetchRequest()
        fr2.predicate = NSPredicate(value: true)
        let dmStates = (try? context.fetch(fr2)) ?? []
        
        var dmStatesUpdatedCounter = 0
        for dmState in dmStates {
            var didUpdate = false
            // set participants (.pubkey + P tags)
            if let contactPubkey = dmState.contactPubkey_, contactPubkey.count == 64, let accountPubkey = dmState.accountPubkey_ {
                dmState.participantPubkeys = [contactPubkey, accountPubkey]
                didUpdate = true
            }
            
            if let timestamps = earliestAndNewestByGroupId[dmState.conversationId] {
                dmState.lastMessageTimestamp_ = Date(timeIntervalSince1970: TimeInterval(timestamps.newest))
                dmState.initiatorPubkey_ = timestamps.initiatorPubkey
                if let ourNewest = timestamps.ourNewest {
                    let ourNewestDate = Date(timeIntervalSince1970: TimeInterval(ourNewest))
                    if let existingMarkedReadAt = dmState.markedReadAt_ { // if we have existing
                        if ourNewestDate > existingMarkedReadAt { // only set if newer
                            dmState.markedReadAt_ = ourNewestDate
                        }
                    }
                    else { // always set if there is no existing
                        dmState.markedReadAt_ = ourNewestDate
                    }
                }
                
                // get blurb
                if let mostRecent = allDMs.first(where: { $0.id == timestamps.newestId }) {
                    
                    // decrypt if kind 4
                    if mostRecent.kind == 4, let accountPubkey = dmState.accountPubkey_ {
                        if let account = try? CloudAccount.fetchAccount(publicKey: accountPubkey, context: context), let privateKey = account.privateKey {
                            let keyPair = (publicKey: account.publicKey, privateKey: privateKey)
                            
                            let content = if mostRecent.pubkey == keyPair.publicKey, let firstP = mostRecent.firstP() {
                                Keys.decryptDirectMessageContent(withPrivateKey: keyPair.privateKey, pubkey: firstP, content: mostRecent.content ?? "") ?? "(Encrypted content)"
                            }
                            else {
                                Keys.decryptDirectMessageContent(withPrivateKey: keyPair.privateKey, pubkey: mostRecent.pubkey, content: mostRecent.content ?? "") ?? "(Encrypted content)"
                            }
                            // prefix blurb with "You: " if we sent it
                            let fromName = accountPubkey == mostRecent.pubkey ? "You: " : ""
                            dmState.blurb = "\(fromName)\(content)"
                        }
                    }
                    else { // kind 14 is already decrypted rumor
                        // prefix blurb with "You: " if we sent it
                        let fromName = dmState.accountPubkey_ == mostRecent.pubkey ? "You: " : ""
                        dmState.blurb = "\(fromName)\(mostRecent.content ?? "")"
                    }
                }
                
                
                dmState.accepted = timestamps.didSend || dmState.accepted
                didUpdate = true
            }
            
            if didUpdate {
                dmStatesUpdatedCounter += 1
            }
        }
       
        L.maintenance.info("runUpgradeDMformat: \(groupIdsSetCounter) dm groupIds set.  \(dmStatesUpdatedCounter) DM states updated.")
       
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.upgradeDMformat.rawValue
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
    
    // Run once to restore footer buttons
    static func runRestoreFooterButtons(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.restoreFooterButtons, context: context) else { return }
        defer {
            let migration = Migration(context: context)
            migration.migrationCode = migrationCode.restoreFooterButtons.rawValue
        }
        
        var footerButtons = SettingsStore.shared.footerButtons
        
        if footerButtons.contains("⚡️") { return }
        if footerButtons.contains("⚡") { return }
        if footerButtons.count >= 7 { return }
        
        if let likeIndex = footerButtons.firstIndex(of: "+") {
            footerButtons.insert("⚡️", at: footerButtons.index(after: likeIndex))
        } else if !footerButtons.isEmpty {
            let lastIndex = footerButtons.index(before: footerButtons.endIndex)
            footerButtons.insert("⚡️", at: lastIndex)
        }
        
        SettingsStore.shared.footerButtons = footerButtons
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
    
    // Run once to set current feed order
    static func runSetCloudFeedOrder(context: NSManagedObjectContext) {
        guard !Self.didRun(migrationCode: migrationCode.setCloudFeedOrder, context: context) else { return }
        
        let fr = CloudFeed.fetchRequest()
        fr.predicate = NSPredicate(value: true)
        
        guard let feeds = try? context.fetch(fr).reversed() else {
            L.maintenance.error("runSetCloudFeedOrder: Could not fetch")
            return
        }
        
        L.maintenance.info("runSetCloudFeedOrder: Setting order for \(feeds.count) feeds")
        
        var index = 0
        for feed in feeds {
            feed.order = Int16(index)
            index += 1
        }
        
        let migration = Migration(context: context)
        migration.migrationCode = migrationCode.setCloudFeedOrder.rawValue
    }
    
    // All available migrations
    enum migrationCode: String {
        
        // Run once to delete events without id (old bug)
        case deleteEventsWithoutId = "deleteEventsWithoutId"
        
        // Run once to add k tag
        case addKtag = "addKtag2" // Needed to run again because forgot to add kTag in .saveEvent()
        
        // Run once to upgrade to full width on iOS 26
        case upgradeToFullWidth = "upgradeToFullWidth"
        
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
        
        // Need to run it again... false positives still
        // And again - found another bug during new account onboarding
        case fixImposterFalsePositivesAgainAgain = "fixImposterFalsePositivesAgainAgain"
        
        // Move zappedContactPubkey to otherPubkey
        case fixZappedContactPubkey = "fixZappedContactPubkey"
        
        // Cache .firstQuote.pubkey in .otherPubkey
        case runPutRepostedPubkeyInOtherPubkey = "runPutRepostedPubkeyInOtherPubkey"
        
        // Cache .reactionTo.pubkey in .otherPubkey
        case runPutReactionToPubkeyInOtherPubkey = "runPutReactionToPubkeyInOtherPubkey"
        
        // Migrate Private Notes to iCloud
        case migratePrivateNotes = "migratePrivateNotes"
        
        // Fix private follows
        case fixPrivateFollows = "fixPrivateFollows"
        
        // Update keychain info
        case updateKeychainInfo = "updateKeychainInfo"
        
        // Add "full_account" flag
        case saveFullAccountFlag = "saveFullAccountFlag4"        

        // Fix missing DM States
        case fixMissingDMStates = "fixMissingDMStates"
        
        // Fix missing DM States (again)
        case fixMissingDMStatesAgain = "fixMissingDMStatesAgain"
        
        // Upgrade to new DM format
        case upgradeDMformat = "upgradeDMformat"
        
        // Put first A tag in .otherAtag
        case putReferencedAtag = "putReferencedAtag"
        
        // Set cloud feed manual order
        case setCloudFeedOrder = "setCloudFeedOrder"
        
        // Restore broken footer buttons
        case restoreFooterButtons = "restoreFooterButtons"
        
        // make aTag field for easy lookups
        // Removed, can't query relays for multiple aTags so nevermind. Maybe useful in the future but not now
//        case runSetAtagForReplacableEvents = "runSetAtagForReplacableEvents"
    }
}
