//
//  Maintenance.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import Foundation
import CoreData

struct Maintenance {
    
    static let BOOTSTRAP_RELAYS = ["wss://relay.damus.io", "wss://brb.io" , "wss://nostr.fmt.wiz.biz" , "wss://nostr.zebedee.cloud", "wss://relay.snort.social", "wss://nostr.plebchain.org"]
    
    static func firstTimeStartup(context:NSManagedObjectContext) {
        context.perform {
            let r = Relay.fetchRequest()
            if let relaysCount = try? context.fetch(r).count {
                if (relaysCount == 0) {
                    for url in BOOTSTRAP_RELAYS {
                        let bootstrapRelay = Relay(context: context)
                        bootstrapRelay.read = true
                        bootstrapRelay.write = true
                        bootstrapRelay.createdAt = Date.now
                        bootstrapRelay.url = url
                    }
                }
            }
            try! context.save()
        }
    }
    
    // Clean up things older than 5 days
    // Deletes ALL KIND=0 Events (except own), because should have Contact entity.
    // Keeps bookmarks
    // Keeps own events
    
    //TODO: Find out which tags can be deleted..
    static func maintenance(context:NSManagedObjectContext) {
        let frA = Account.fetchRequest()
        let allACcounts = Array(try! context.fetch(frA))
        let ownAccountPubkeys = allACcounts.reduce([String]()) { partialResult, account in
            var newResult = Array(partialResult)
            newResult.append(account.publicKey!)
            return newResult
        }
        
        let ownAccountBookmarkIds = allACcounts.reduce([String]()) { partialResult, account in
            var newResult = Array(partialResult)
            if (account.bookmarks != nil) {
                let ids = account.bookmarks!.map { $0.id! }
                newResult.append(contentsOf: ids)
            }
            return newResult
        }
        
        let xDaysAgo = Date.now.addingTimeInterval(-5 * 86400) // 3 days
        
        
        // KIND 1,6,7
        // OUDER DAN X DAGEN
        // IS GEEN BOOKMARK
        // IS GEEN EIGEN EVENT
        context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            fetchRequest.predicate = NSPredicate(format: "kind IN {1,6,7} AND created_at < %i AND NOT id IN %@ AND NOT pubkey IN %@", Int64(xDaysAgo.timeIntervalSince1970), ownAccountBookmarkIds, ownAccountPubkeys)
            
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDelete.resultType = .resultTypeCount
            
            do {
                let result = try context.execute(batchDelete) as! NSBatchDeleteResult
                print("Deleted \(result.result!) kind 1 or 7 events")
            } catch {
                print("Failed to delete kind 1 or 7 data")
            }
        }
        
        // KIND 0
        // ALLES WEG WANT IEDERE KIND 0 HEEFT EEN CONTACT
        // EIGEN KIND 0 NIET WEG
        context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            fetchRequest.predicate = NSPredicate(format: "(kind == 0) AND NOT pubkey IN %@", ownAccountPubkeys)
            
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDelete.resultType = .resultTypeCount
            
            do {
                let result = try context.execute(batchDelete) as! NSBatchDeleteResult
                print("Deleted \(result.result!) kind=0 events")
            } catch {
                print("Failed to delete kind=0 data")
            }
        }
        
        do {
            try context.save()
        }
        catch {
            print("maintenance error on save(): \(error)")
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
                            print("🟡🟡 Updated banner \(metaData.banner!) for \(contact.pubkey!)")
                        }
                    }
                }
                try EventsProvider.shared.container.viewContext.save()
            }
            
            catch let error as NSError {
                // TODO: handle the error
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
//            } catch let error as NSError {
//                // TODO: handle the error
//                print("😢😢😢 XX \(error)")
//            }
//        }
    }
}
