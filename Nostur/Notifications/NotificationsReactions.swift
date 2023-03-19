//
//  Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import SwiftUI
import CoreData

// NIP-25: The last p tag MUST be the pubkey of the event being reacted to.
// TODO: Maybe when performance problems: store lastE + lasteE in Events table
struct NotificationsReactions: View {

    let pubkey:String
//    let FETCH_LIMIT = 1000
    let sp:SocketPool = .shared
    let nav:NavigationModel = .shared
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    var onAppear:(Int64) -> ()
    
    @FetchRequest
    var reactions:FetchedResults<Event>
    
    var myNotesReactedTo:[Event] {
        
        var sortingDict:[Event: Int64] = [:] // Event and most recent reaction created_At

        for reaction in reactions {
            guard let reactionTo = reaction.reactionTo else { continue }
            if (sortingDict.keys.contains(reactionTo)) {
                if reaction.created_at > sortingDict[reactionTo]! {
                    sortingDict[reactionTo] = reaction.created_at
                }
            }
            else {
                sortingDict[reactionTo] = reaction.created_at
            }
        }
        return sortingDict.keys.sorted(by: { (sortingDict[$0] ?? 0) > (sortingDict[$1] ?? 0) } )
    }
    
    var myNotesReactedToAsVPosts:[VPost] {
        myNotesReactedTo.map(VPostTransformer.shared.toVPost)
    }
    
    func reactionsForNote(_ note:Event) -> [Event] {
        reactions.compactMap {  $0.reactionTo == note ? $0 : nil }
    }
    
    init(pubkey:String, blockedPubkeys:[String], context:NSManagedObjectContext, onAppear: @escaping (Int64) -> ()) {
        self.pubkey = pubkey
        self.onAppear = onAppear
//        le
        let r1 = Event.fetchRequest()
        r1.predicate = NSPredicate(format: "NOT pubkey IN %@ AND kind == 7 AND reactionTo.contact.pubkey == %@", blockedPubkeys, pubkey)
//        r1.fetchLimit = FETCH_LIMIT
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        let oldestCreatedAt = (try? context.fetch(r1).last?.created_at) ?? 0
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format: "NOT pubkey IN %@ AND created_at >= %i AND kind == 7 AND reactionTo.contact.pubkey == %@", blockedPubkeys, oldestCreatedAt, pubkey)
//        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _reactions = FetchRequest(fetchRequest: r2)
    }
    
    var body: some View {
        let _ = print("🧨🧨🧨🧨🧨  NOTIFICATONS REACTIONS 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        let _ = Self._printChanges()
        VStack {
            List {
                Section {
                    ForEach(myNotesReactedToAsVPosts) { vPost in
                        VStack(alignment:.leading, spacing: 3) {
                            ReactionsForThisNote(reactions:reactionsForNote(vPost.event), onAppear: self.onAppear)
//                            Text("vPost.post.id \(vPost.ev.id.prefix(10).description)")
//                            Text("vPost.post.firstQuoteId \(vPost.post.firstQuoteId?.prefix(10).description ?? "")")
//                            Text("vPost.firstQuoteObjectId \(vPost.firstQuoteObjectId?.description.prefix(10).description ?? "")")
//                            Text("vPost.firstQuoteEvent.id \(vPost.firstQuoteEvent?.id.prefix(10).description ?? "")")
                            Divider()
                            NoteMinimalContentView(vPost: vPost)
                        }
                        .padding()
                        .listRowInsets(EdgeInsets())
                        .onTapGesture {
                            nav.navigateTo(vPost)
                        }
                    }
                }
                Section {
                    HStack {
                        Spacer()
                        Button("Fetch older") {
                            fetchOlderReactions()
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
            .onAppear {
                fetchReactions()
            }
        }
    }
    
    func fetchOlderReactions() {
        guard ns.account != nil else { return }
        sp.sendMessage(
            ClientMessage(type: .REQ,
                          message:
                            RequestMessage.getMentions(
                                pubkeys: [ns.account!.publicKey],
                                kinds: [7],
                                limit: 500,
                                until: NTimestamp(timestamp: Int(reactions.last?.created_at ?? 0)))
                         )
        )
    }
    
    func fetchReactions() {
        guard let account = ns.account else { return }
        let req = RequestMessage.getMentions(
            pubkeys: [account.publicKey],
            kinds: [7],
            limit: 500,
            since: NTimestamp(timestamp: Int(reactions.first?.created_at ?? 0)))
        
        print(req)
//        sp.sendMessage(
//            ClientMessage(type: .REQ,
//                          message: req
//                         )
//        )
    }
}

struct ReactionsForThisNote: View {
    var reactions:[Event]
    @Environment(\.managedObjectContext) var viewContext
    var onAppear:(Int64) -> ()
    
    var withoutDuplicates:[Event] { // Author may accidentally like multiple times 
        reactions
            .reduce(into: [String: Event]()) { result, event in
                result[event.pubkey] = event
            }.values.sorted(by: { $0.created_at > $1.created_at })
    }
    
    var body: some View {
        VStack(alignment:.leading) {
            ZStack {
                ForEach(withoutDuplicates.prefix(10).indices, id:\.self) { index in
                    ZStack {
                        ProfilePic(event: reactions[index])
                            .id(reactions[index].id)
                            .onAppear {
                                onAppear(reactions[index].created_at)
                            }
                            .zIndex(-Double(index))
                        Text(reactions[index].content == "+" ? "❤️" : reactions[index].content ?? "❤️")
                            .offset(x:-10, y:+15)
                            .zIndex(20)
                        
                    }
                    .offset(x:Double(0 + (25*index)))
                    .id(reactions[index].id)
                }
            }
            if (withoutDuplicates.count > 1) {
                Text("**\(withoutDuplicates.first(where: { $0.contact?.authorName != nil })?.contact?.authorName ?? "???")** and \(withoutDuplicates.count - 1) others reacted to your post")
            }
            else {
                Text("**\(withoutDuplicates.first(where: { $0.contact?.authorName != nil })?.contact?.authorName ?? "???")** reacted on your post")
            }
        }
        .onAppear {
            self.fetchMissingEventContacts(events:Array(withoutDuplicates.prefix(10)))
        }
    }
    
    func fetchMissingEventContacts(events:[Event]) {
        let pubkeys = pubkeys(events)
        let contacts = Contact.fetchByPubkeys(pubkeys, context: viewContext)
        let missingPubkeys = pubkeys.filter {
            contacts.map { $0.pubkey }.firstIndex(of: $0) == nil
        }
        let emptyContactPubkeys = pubkeys
            .compactMap { pubkey in
                contacts.first(where: { $0.pubkey == pubkey })
            }
            .filter { $0.metadata_created_at == 0 }
            .map { $0.pubkey }
        
        guard (missingPubkeys + emptyContactPubkeys).count > 0 else { return }
        print("Fetching  \((missingPubkeys + emptyContactPubkeys).count) missing or empty contacts")
        SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingPubkeys + emptyContactPubkeys )))
    }
}

struct NotificationsV_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9"
        NotificationsReactions(pubkey: pubkey, blockedPubkeys: [], context: EventsProvider.preview.container.viewContext) { _ in
            
        }
            .withPreviewEnvironment()
    }
}
