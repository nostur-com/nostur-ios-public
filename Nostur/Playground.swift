//
//  Playground.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/01/2023.
//

import SwiftUI
import CoreData

struct Playground: View {
    
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    
    var body: some View {
        VStack {
            ContactsView(pubkey: activeAccountPublicKey)
        }
    }
}

class Events : ObservableObject {
    @Published var events:[Event] = []
    @Published var metaDataEvent:Event?
    @Published var contactsFR:[Contact]?
    @Published var contacts:FetchedResults<Contact>?
}

struct ContactsView : View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    @State var pubkey:String = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
    
    
    private var contacts:[Contact] = [Contact]()
    @ObservedObject var events = Events()
    
    init(pubkey:String) {
        
        self.pubkey = pubkey
//        let request = NSFetchRequest<Contact>()
//        request.entity = Contact.entity()
//        request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
//        contacts = try! viewContext.fetch(request)
//        
//        let xrequest = NSFetchRequest<Event>()
//        xrequest.entity = Event.entity()
//        let fetchedEvents = (try! viewContext.fetch(xrequest))
//        
//        events.events.append(contentsOf: fetchedEvents)
    }
    
    func searchByPubkey() {
        guard pubkey != "" else {
            return
        }
        let metaDataMessage = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey))
        ConnectionManager.shared.sendMessage(metaDataMessage)
        
        let notesMessage = ClientMessage(type: .REQ, message: RequestMessage.getAuthorNotes(pubkey: pubkey))
        ConnectionManager.shared.sendMessage(notesMessage)
        
        let request = NSFetchRequest<Event>()
        request.entity = Event.entity()
        let fetchedEvents = (try! viewContext.fetch(request))
        
        events.events.removeAll()
        events.events.append(contentsOf: fetchedEvents)
        
    }
    
    func refresh() {
        let request = NSFetchRequest<Event>()
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "pubkey == %@ AND kind == %d", pubkey, 1)
        let fetchedEvents = (try! viewContext.fetch(request))
        
        events.events.removeAll()
        events.events.append(contentsOf: fetchedEvents)

        let mdr = NSFetchRequest<Event>()
        mdr.entity = Event.entity()
        mdr.predicate = NSPredicate(format: "pubkey == %@ AND kind == %d", pubkey, 0)
        mdr.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]

        let fetchedmdr = (try! viewContext.fetch(mdr))
        
        self.events.metaDataEvent = fetchedmdr.first
    }
    
    var body: some View {
    
        ScrollView {
            VStack {
                Group {
                    TextField("Search by public key", text:$pubkey)
                    Button {
                        searchByPubkey()
                    } label: {
                        Text("Search")
                    }.padding()
                    Button {
                        refresh()
                    } label: {
                        Text("Refresh")
                    }.padding()
                }
                
                if (events.metaDataEvent != nil) {
                    Group {
                        Text("\(events.metaDataEvent?.content ?? "no metadata")")
                    }
                }
            
                Group {
                    Text("\(contacts.count) contacts for pubkey (cloud)").font(.title3)
                    ForEach(contacts) { contact in
                        HStack {
                            Text(contact.pubkey ?? "nopub")
                            Text(contact.name ?? "(Unknown Contact)")
                        }.background(.green)
                        Divider()
                    }
                }
                Divider()
                
                Group {
                    Text("\(events.events.count) notes (local)").font(.title3)
                    Divider()
                    ForEach(events.events) { event in
                        HStack {
                            Text(event.pubkey ?? "(Unknown Event)")
                        }.background(.red)
                        Divider()
                    }
                }
                
                Spacer()
            }
        }
        .task {
            // determine active identity
//            print(activeAccountPublicKey)
//
//            var request = NSFetchRequest<Contact>(entityName: "Contact")
//            var contacts = try! viewContext.fetch(request)
//
//            for contact in contacts {
//                print(contact.name ?? "(unknown)")
//            }
//
//
            // determine follower pubkeys
            
            
            // subscribe to notes from these pubkeys on all relays
            
            // load received events in view somehow..
            
            // determine start / stop / timer ... which notes to show or not?
        }
    }
}


// Should load from Contact (cloudkit entity), which was created and updated from kind=0 events
struct UserProfileLoader {
    
    
    
}


// Should load from Event.id kind=0
struct TweetLoader {
    
}



struct Playground_Previews: PreviewProvider {
    
    
//    static var cloudContainer = PersistenceController.preview.cloudContainer
    
    static var previewUserDefaults: UserDefaults = {
                let d = UserDefaults(suiteName: "preview_user_defaults")!
                
        d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", forKey: "activeAccountPublicKey")
                
        return d
            }()
    static var previews: some View {
        Playground()
            .defaultAppStorage(previewUserDefaults)
            .environment(\.managedObjectContext,
                          PersistenceController.preview.container.viewContext)
            
    }
}
