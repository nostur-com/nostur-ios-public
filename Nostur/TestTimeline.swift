//
//  TestTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//

import SwiftUI
import CoreData

class XEvents : ObservableObject {
    @Published var events:[Event] = []
    @Published var metaDataEvent:Event?
    @Published var contacts:[Contact] = [Contact]()
    @Published var contactsFR:FetchedResults<Contact>?
    
    func byPubkey(_ pubkey:String?) -> String {
        guard pubkey != nil else {
            return ""
        }
        return contacts.first(where: { ($0.pubkey != nil) && $0.pubkey == pubkey})?.name! ?? ""
    }
}

struct Wrapper: View {

    @Environment(\.managedObjectContext) var viewContext
    var cloudContainer:NSPersistentCloudKitContainer
    
    var body: some View {
        VStack {
            TestTimeline(cloudContainer: cloudContainer)
        }
    }
}

struct TestTimeline: View {
    
    var cloudContainer:NSPersistentCloudKitContainer
    
    var contacts:FetchedResults<Contact>? = nil
    
//    @FetchRequest(fetchRequest:Event.textNotes(byAuthorPubkey:"5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"))
    @FetchRequest(fetchRequest:Event.textNotes())
    var events: FetchedResults<Event>
    
    var xevents:XEvents = XEvents()
    
//    private var contacts:[Contact] = [Contact]()
    
    init(cloudContainer:NSPersistentCloudKitContainer) {
        self.cloudContainer = cloudContainer

        let request = NSFetchRequest<Contact>()
        request.entity = Contact.entity()
//        request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        let fetchedContacts = try! self.cloudContainer.viewContext.fetch(request)
        
    
        xevents.contacts.append(contentsOf: fetchedContacts)
    }
    
        
    var body: some View {
    
        
        
        var tweets:[Tweet] = events.map { event in Tweet(text: event.content ?? "", hasImage: false, isVerified: true, imageName: "", username: xevents.byPubkey(event.pubkey), name: xevents.byPubkey(event.pubkey), profileImageName: "peterschiffDummy", retweetCount: "28", likeCount: "189", replyCount: "8", retweetedByName: "", replyToUsername: "", ago: "1m", hasThread: false)
        }
//
        
        VStack {
//            Text("Hello, World! contacts: \(contacts.count)")
            
            
//            ForEach(contacts) { contact in
//                Text(contact.name ?? "no name")
//            }
            
//            Text("Hello, World! contacts: \(xevents.contactsFR?.count ?? 0)")
//            Text("Hello, World! contacts: \(xevents.contacts.count)")
            NotesViewer(tweets:tweets)
        }
    }
}

struct NotesViewer: View {
    
//    var events:FetchedResults<Event>
    var tweets:[Tweet]
    
    var body: some View {
        ScrollView {
            ForEach(tweets) { tweet in
                TweetView(tweet: tweet)
            }
        }
//        ForEach(events) { event in
//            Text("event: \(event.id ?? "<id missing>")")
//        }
    }
    
}

struct TestTimeline_Previews: PreviewProvider {
    
    static var cloudContainer = PersistenceController.preview.cloudContainer
    
    static var previews: some View {
        Wrapper(cloudContainer:cloudContainer)
            .environment(\.managedObjectContext, PersistenceController.preview.localContainer.viewContext)
    }
}
