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
    let blockedPubkeys:[String]
    
    @StateObject var fl = FastLoader()
    @State var backlog = Backlog()
    @EnvironmentObject var ns:NosturState
    
    
    var myNotesReactedTo:[Event] {
        
        var sortingDict:[Event: Int64] = [:] // Event and most recent reaction created_At
        
        for reaction in fl.events {
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
        myNotesReactedTo.compactMap { VPostTransformer.shared.toVPost($0, skipParents: true, plainText: true) }
    }
    
    func reactionsForNote(_ event:Event) -> [Event] {
        fl.events.compactMap {  $0.reactionToId == event.id ? $0 : nil }
    }
    
    init(pubkey:String, blockedPubkeys:[String]) {
        self.pubkey = pubkey
        self.blockedPubkeys = blockedPubkeys
    }
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollView {
            LazyVStack(alignment:.leading, spacing: 0) {
                ForEach(myNotesReactedToAsVPosts) { vPost in
                    VStack(alignment:.leading, spacing: 3) {
                        ReactionsForThisNote(reactions:reactionsForNote(vPost.event))
                        NoteMinimalContentView(vPost: vPost)
                    }
                    .padding(10)
                    .background(Color.systemBackground)
                    .boxShadow()
                    .padding(10)
                    .onTapGesture {
                        navigateTo(vPost)
                    }
                    .id(vPost.id)
                }
                Button("Show more") {
                    fl.predicate = NSPredicate(
                        format:
                            "NOT pubkey IN %@ " +
                            "AND kind == 7 " +
                            "AND reactionTo.pubkey == %@",
                            blockedPubkeys,
                            pubkey)
//                    fl.offset = (fl.events.count - 1)
                    fl.loadMore(500)
                    if let until = fl.events.last?.created_at {
                        req(RM.getMentions(
                            pubkeys: [pubkey],
                            kinds: [7],
                            limit: 500,
                            until: NTimestamp(timestamp: Int(until))
                        ))
                    }
                    else {
                        req(RM.getMentions(pubkeys: [pubkey], limit:500))
                    }
                }
                .padding(.bottom, 40)
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .hCentered()
            }
        }
        .background(Color("ListBackground"))
        .onAppear {
            fl.vPostTransform = false
            fl.predicate = NSPredicate(
                format:
                    "NOT pubkey IN %@ " +
                    "AND kind == 7 " +
                    "AND reactionTo.pubkey == %@",
                    blockedPubkeys,
                    pubkey
                )
            fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            fl.loadMore(500)
            
            if let first = fl.events.first, let account = ns.account {
                let firstCreatedAt = first.created_at
                DataProvider.shared().bg.perform {
                    if let account = account.toBG() {
                        account.lastSeenReactionCreatedAt = firstCreatedAt
                    }
                    DataProvider.shared().bgSave()
                }
                
            }
            
            let fetchNewerTask = ReqTask(
                reqCommand: { (taskId) in
                    req(RM.getMentions(
                        pubkeys: [pubkey],
                        kinds: [7],
                        limit: 5000,
                        subscriptionId: taskId,
                        since: NTimestamp(timestamp: Int(fl.events.first?.created_at ?? 0))
                    ))
                },
                processResponseCommand: { (taskId) in
//                    print("🟠🟠🟠 processResponseCommand \(taskId)")
                    let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
                    fl.predicate = NSPredicate(
                        format:
                            "created_at >= %i " +
                            "AND NOT pubkey IN %@ " +
                            "AND kind == 7 " +
                            "AND reactionTo.pubkey == %@",
                            currentNewestCreatedAt,
                            blockedPubkeys,
                            pubkey
                      )
                    fl.loadNewerEvents(5000, taskId: taskId)
                })
            
            backlog.add(fetchNewerTask)
            fetchNewerTask.fetch()
            
            fixReactionsWithMissingRelation()
        }
        .onReceive(receiveNotification(.newReactions)) { _ in
            let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
            fl.predicate = NSPredicate(
                format:
                    "created_at >= %i " +
                    "AND NOT pubkey IN %@ " +
                    "AND kind == 7 " +
                    "AND reactionTo.pubkey == %@",
                    currentNewestCreatedAt,
                    blockedPubkeys,
                    pubkey
            )
            fl.loadNewerEvents(5000, taskId:"newReactions")
        }
        .onReceive(receiveNotification(.importedMessagesFromSubscriptionIds)) { notification in
            let importedSubIds = notification.object as! ImportedNotification
            
            let reqTasks = backlog.tasks(with: importedSubIds.subscriptionIds)
            
            reqTasks.forEach { task in
                task.process()
            }
        }
    }
    
    func fixReactionsWithMissingRelation() {
        let mr = Event.fetchRequest()
        mr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        mr.predicate = NSPredicate(format: "kind == 7 AND tagsSerialized CONTAINS %@ AND reactionTo == nil", serializedP(pubkey))
        
        Task.detached(priority: .medium) {
            let ctx = DataProvider.shared().bg
            DataProvider.shared().bg.perform {
                if let danglingReactions = try? ctx.fetch(mr) {
                    danglingReactions
//                        .filter { $0.reactionTo == nil }
                        .forEach { reaction in
                            _ = reaction.reactionTo_ // this lazy load fixes the relation
                        }
                }
            }
            
        }
    }
}

struct ReactionsForThisNote: View {
    var reactions:[Event]
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    var withoutDuplicates:[Event] { // Author may accidentally like multiple times
        reactions
            .reduce(into: [String: Event]()) { result, event in
                result[event.pubkey] = event
            }.values.sorted(by: { $0.created_at > $1.created_at })
    }
    
    var body: some View {
        VStack(alignment:.leading) {
            ZStack(alignment:.leading) {
                ForEach(withoutDuplicates.prefix(10).indices, id:\.self) { index in
                    ZStack(alignment:.leading) {
                        PFP(pubkey: reactions[index].pubkey, pictureUrl: reactions[index].contact?.picture, isFollowing: ns.followingPublicKeys.contains(reactions[index].pubkey))
                            .id(reactions[index].id)
                            .zIndex(-Double(index))
                        Text(reactions[index].content == "+" ? "❤️" : reactions[index].content ?? "❤️")
                            .offset(x:5, y:+15)
                            .zIndex(20)
                        
                    }
                    .offset(x:Double(0 + (25*index)))
                    .id(reactions[index].id)
                }
            }
            if (withoutDuplicates.count > 1) {
                Text("**\(withoutDuplicates.first(where: { $0.contact?.authorName != nil })?.contact?.authorName ?? "???")** and \(withoutDuplicates.count - 1) others reacted on your post")
                    
            }
            else {
                Text("**\(withoutDuplicates.first(where: { $0.contact?.authorName != nil })?.contact?.authorName ?? "???")** reacted on your post")
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .overlay(alignment: .topTrailing) {
            if let first = withoutDuplicates.first {
                Ago(first.created_at).layoutPriority(2)
                    .foregroundColor(.gray)
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
        NotificationsReactions(pubkey: pubkey, blockedPubkeys: [])
            .withPreviewEnvironment()
    }
}
