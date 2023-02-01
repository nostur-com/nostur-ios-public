//
//  Maintenance.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import Foundation
import CoreData

struct Maintenance {
    
    
    
    
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
        if (1 == 1) { return }
        EventsProvider.shared.container.viewContext.perform {
            do {
                let r = NSFetchRequest<Contact>()
                r.entity = Contact.entity()
                r.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
                
                guard let allContacts = try? r.execute() else {
                    print("😢 XX")
                    return
                }
                
                for contact in allContacts {
                    EventsProvider.shared.container.viewContext.delete(contact)
                }
                
                try EventsProvider.shared.container.viewContext.save()
            } catch let error as NSError {
                // TODO: handle the error
                print("😢😢😢 XX \(error)")
            }
        }
    }
}
