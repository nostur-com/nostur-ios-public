//
//  Maintenance.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import Foundation
import CoreData

struct Maintenance {
    
    static let BOOTSTRAP_RELAYS = ["wss://relay.damus.io" , "wss://nostr.fmt.wiz.biz", "wss://relay.snort.social", "wss://nostr.mutinywallet.com", "wss://purplepag.es"]
    
    static func firstTimeStartup(context:NSManagedObjectContext) {
        context.performAndWait {
            let r = Relay.fetchRequest()
            if let relaysCount = try? context.fetch(r).count {
                var relays:[Relay] = []
                let ot = OnboardingTracker.shared
                if (relaysCount == 0) {
                    ot.startOnboarding(pubkey: NosturState.GUEST_ACCOUNT_PUBKEY)
                    for url in BOOTSTRAP_RELAYS {
                        let bootstrapRelay = Relay(context: context)
                        bootstrapRelay.read = url == "wss://nostr.mutinywallet.com" ? false : true // this one is write only
                        bootstrapRelay.write = true
                        bootstrapRelay.createdAt = Date.now
                        bootstrapRelay.url = url
                        relays.append(bootstrapRelay)
                    }
                    
                    let account = Account(context: context)
                    account.id = UUID()
                    account.createdAt = Date()
                    account.createdAt = Date()
                    account.display_name = "Nostur Rookie"
                    account.name = "NosturRookie"
                    account.about = "Just trying things out"
                    account.publicKey = NosturState.GUEST_ACCOUNT_PUBKEY
                }
                
                let sp = SocketPool.shared
                // CONNECT TO RELAYS
                for relay in relays {
                    _ = sp.addSocket(relayId: relay.objectID, url: relay.url!, read:relay.read, write: relay.write)
                }
                
                if (!ot.didFetchKind0 || !ot.didFetchKind3) {
                    let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: NosturState.GUEST_ACCOUNT_PUBKEY))
                    SocketPool.shared.sendMessage(message)
                }
            }
            try! context.save()
        }
    }
    
    // Clean up things older than X days
    // Deletes ALL KIND=0 Events (except own), because should have Contact entity.
    // Keeps bookmarks
    // Keeps own events
    // Keeps contacts/posts with private notes
    
    //TODO: Find out which tags can be deleted..
    static func maintenance(context:NSManagedObjectContext) {
        
        let lastMaintenanceTimestamp = Date(timeIntervalSince1970: TimeInterval(SettingsStore.shared.lastMaintenanceTimestamp))
        let hoursAgo = Date(timeIntervalSinceNow: (-24 * 60 * 60))
        guard lastMaintenanceTimestamp < hoursAgo else { return } // don't do maintenance more than once every 24 hours
        SettingsStore.shared.lastMaintenanceTimestamp = Int(Date.now.timeIntervalSince1970)
        
        context.perform {
            let frA = Account.fetchRequest()
            let allAccounts = Array(try! context.fetch(frA))
            let ownAccountPubkeys = allAccounts.reduce([String]()) { partialResult, account in
                var newResult = Array(partialResult)
                if (account.privateKey != nil) { // only if it is really our account
                    newResult.append(account.publicKey)
                }
                return newResult
            }
            
            let regex = ".*(" + ownAccountPubkeys.map {
                NSRegularExpression.escapedPattern(for: $0)
            }.joined(separator: "|") + ").*"
            
            let ownAccountBookmarkIds = allAccounts.reduce([String]()) { partialResult, account in
                var newResult = Array(partialResult)
                if (account.bookmarks != nil) {
                    let ids = account.bookmarks!.map { $0.id }
                    newResult.append(contentsOf: ids)
                }
                return newResult
            }
            
            let ownAccountPrivateNoteEventIds = allAccounts.reduce([String]()) { partialResult, account in
                var newResult = Array(partialResult)
                if (account.privateNotes != nil) {
                    let ids = account.privateNotes!.compactMap { $0.post?.id }
                    newResult.append(contentsOf: ids)
                }
                return newResult
            }
            
            let xDaysAgo = Date.now.addingTimeInterval(-4 * 86400) // 4 days
            
            
            
            // CLEAN UP EVENTS WITHOUT SIG (BUG FROM PostPreview)
            let frNoSig = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            frNoSig.predicate = NSPredicate(format: "sig == nil")
            
            let frNoSigbatchDelete = NSBatchDeleteRequest(fetchRequest: frNoSig)
            frNoSigbatchDelete.resultType = .resultTypeCount
            
            do {
                let result = try context.execute(frNoSigbatchDelete) as! NSBatchDeleteResult
                if ((result.result as? Int ?? 0) > 0) {
                    print("🧹🧹 Deleted \(result.result!) events without signature")
                }
            } catch {
                print("🔴🔴 Failed to delete events without signature")
            }
            
            
            
            
            // KIND 1,6
            // OUDER DAN X DAGEN
            // IS GEEN BOOKMARK
            // IS GEEN EIGEN EVENT
            // DOES NOT HAVE OUR PUBKEY IN P (Notifications)
            // DONT DELETE MUTED BLOCKED, SO OUR BLOCK LIST STILL FUNCTIONS....
            // TODO: DONT EXPORT MUTED / BLOCKED. KEEP HERE SO WE DONT HAVE TO KEEP ..REPARSING
            
            let fr16 = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            fr16.predicate = NSPredicate(format: "created_at < %i AND kind IN {1,6,9802} AND NOT id IN %@ AND NOT id IN %@ AND NOT (pubkey IN %@ OR tagsSerialized MATCHES %@)", Int64(xDaysAgo.timeIntervalSince1970), ownAccountBookmarkIds, ownAccountPrivateNoteEventIds, ownAccountPubkeys, regex)
            
            let fr16batchDelete = NSBatchDeleteRequest(fetchRequest: fr16)
            fr16batchDelete.resultType = .resultTypeCount
            
            do {
                let result = try context.execute(fr16batchDelete) as! NSBatchDeleteResult
                if ((result.result as? Int ?? 0) > 0) {
                    print("🧹🧹 Deleted \(result.result!) kind {1,6,1,6,9802} events")
                }
            } catch {
                print("🔴🔴 Failed to delete {1,6,1,9802} data")
            }
            
            
            //            do {
            //                try context.save()
            //            }
            //            catch {
            //                print("maintenance error on save(): \(error)")
            //            }
            //
            
            // KIND 9734,7,8
            // OUDER DAN X DAGEN
            // PUBKEY NOT IN OWN ACCOUNTS
            // OR PUBKEY OF OWN ACCOUNTS NOT IN SERIALIZED TAGS
            //            context.perform {
            let fr9734 = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            
            fr9734.predicate = NSPredicate(format: "created_at < %i AND kind IN {9734,8,7} AND NOT (pubkey IN %@ OR tagsSerialized MATCHES %@)", Int64(xDaysAgo.timeIntervalSince1970), ownAccountPubkeys, regex)
            
            let fr9734batchDelete = NSBatchDeleteRequest(fetchRequest: fr9734)
            fr9734batchDelete.resultType = .resultTypeCount
            
            do {
                let result = try context.execute(fr9734batchDelete) as! NSBatchDeleteResult
                if ((result.result as? Int ?? 0) > 0) {
                    print("🧹🧹 Deleted \(result.result!) kind {9734,8,7} events")
                }
            } catch {
                print("🔴🔴 Failed to delete 9734,7,8 data")
            }
            //            }
            
            //            do {
            //                try context.save()
            //            }
            //            catch {
            //                print("maintenance error on save(): \(error)")
            //            }
            
            // KIND 9735
            // OUDER DAN X DAGEN
            // zappedContactPubkey NOT IN OWN ACCOUNTS
            //            context.perform {
            let fr9735 = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            fr9735.predicate = NSPredicate(format: "created_at < %i AND kind == 9735 AND NOT zappedContactPubkey IN %@", Int64(xDaysAgo.timeIntervalSince1970), ownAccountPubkeys)
            
            let fr9735batchDelete = NSBatchDeleteRequest(fetchRequest: fr9735)
            fr9735batchDelete.resultType = .resultTypeCount
            
            do {
                let result = try context.execute(fr9735batchDelete) as! NSBatchDeleteResult
                if ((result.result as? Int ?? 0) > 0) {
                    print("🧹🧹 Deleted \(result.result!) kind 9735 events")
                }
            } catch {
                print("🔴🔴 Failed to delete 9734 data")
            }
            //            }
            
            //            do {
            //                try context.save()
            //            }
            //            catch {
            //                print("maintenance error on save(): \(error)")
            //            }
            
            
            // KIND 0
            // ALLES WEG WANT IEDERE KIND 0 HEEFT EEN CONTACT
            // EIGEN KIND 0 NIET WEG
            //            context.perform {
            let fr0 = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            fr0.predicate = NSPredicate(format: "(kind == 0) AND NOT pubkey IN %@", ownAccountPubkeys)
            
            let fr0batchDelete = NSBatchDeleteRequest(fetchRequest: fr0)
            fr0batchDelete.resultType = .resultTypeCount
            
            do {
                let result = try context.execute(fr0batchDelete) as! NSBatchDeleteResult
                if ((result.result as? Int ?? 0) > 0) {
                    print("🧹🧹 Deleted \(result.result!) kind=0 events")
                }
            } catch {
                print("🔴🔴 Failed to delete kind=0 data")
            }
            //            }
            
            //            do {
            //                try context.save()
            //            }
            //            catch {
            //                print("maintenance error on save(): \(error)")
            //            }
            //
            // DELETE OLDER KIND 3 EVENTS
            //            context.perform {
            let r = NSFetchRequest<Event>(entityName: "Event")
            r.predicate = NSPredicate(format: "kind == 3")
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            let kind3 = try! context.fetch(r)
            
            var noDuplicates:Dictionary<String, Event> = [:]
            var forDeletion:[Event] = []
            
            for event in kind3 {
                if noDuplicates[event.pubkey] != nil {
                    forDeletion.append(event)
                }
                else {
                    noDuplicates[event.pubkey] = event
                }
            }
            for toDelete in forDeletion {
                context.delete(toDelete)
            }
            //            }
            
            do {
                if forDeletion.count > 0 {
                    print("🧹🧹 Deleted \(forDeletion.count) kind 3 events")
                }
                try context.save()
            }
            catch {
                print("🧹🧹 🔴🔴 maintenance error on save(), nothing deleted: \(error)")
            }
        }
    }
    
    
    // SetMetadata can have a banner field now.
    func rescanForBannerFields() {
        EventsProvider.shared.container.viewContext.perform {
            
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
                            print("🟡🟡 Updated banner \(metaData.banner!) for \(contact.pubkey)")
                        }
                    }
                }
                try EventsProvider.shared.container.viewContext.save()
            }
            
            catch let error {
                print("😢😢😢 XX \(error)")
            }
        }
    }
    
    func deleteAllContacts() {
        //        if (1 == 1) { return }
        //        EventsProvider.shared.container.viewContext.perform {
        //            do {
        //                let r = NSFetchRequest<Contact>()
        //                r.entity = Contact.entity()
        //                r.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
        //
        //                guard let allContacts = try? r.execute() else {
        //                    print("😢 XX")
        //                    return
        //                }
        //
        //                for contact in allContacts {
        //                    EventsProvider.shared.container.viewContext.delete(contact)
        //                }
        //
        //                try EventsProvider.shared.container.viewContext.save()
        //            } catch let error  {
        //                print("😢😢😢 XX \(error)")
        //            }
        //        }
    }
}
