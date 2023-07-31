//
//  Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import SwiftUI
import CoreData
import Combine

struct NotificationsReactions: View {
    
    @StateObject var fl = FastLoader()
    @State var didLoad = false
    @State var backlog = Backlog()
    @EnvironmentObject var ns:NosturState
    @ObservedObject var settings:SettingsStore = .shared
    
    func myNotesReactedTo(_ events:[Event]) -> [Event] {
        
        var sortingDict:[Event: Int64] = [:] // Event and most recent reaction created_At
        
        for reaction in events {
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
    
    @State var myNotesReactedToAsNRPosts:[NRPost] = []
    
    func reactionsForNote(_ id:String) -> [Event] {
        fl.events.compactMap {  $0.reactionToId == id ? $0 : nil }
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        ScrollView {
            LazyVStack(alignment:.leading, spacing: 0) {
                ForEach(myNotesReactedToAsNRPosts) { nrPost in
                    VStack(alignment:.leading, spacing: 3) {
                        ReactionsForThisNote(reactions:reactionsForNote(nrPost.id))
                        NoteMinimalContentView(nrPost: nrPost)
                    }
                    .padding(10)
                    .roundedBoxShadow()
                    .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                    .padding(.vertical, 10)
                    .onTapGesture {
                        navigateTo(nrPost)
                    }
                    .id(nrPost.id)
                }
                VStack {
                    if !myNotesReactedToAsNRPosts.isEmpty {
                        Button("Show more") {
                            guard let account = NosturState.shared.account else { return }
                            fl.predicate = NSPredicate(
                                format: "NOT pubkey IN %@ AND kind == 7 AND reactionTo.pubkey == %@",
                                account.blockedPubkeys_,
                                account.publicKey)
        //                    fl.offset = (fl.events.count - 1)
                            fl.loadMore(500)
                            if let until = fl.events.last?.created_at {
                                req(RM.getMentions(
                                    pubkeys: [account.publicKey],
                                    kinds: [7],
                                    limit: 500,
                                    until: NTimestamp(timestamp: Int(until))
                                ))
                            }
                            else {
                                req(RM.getMentions(pubkeys: [account.publicKey], kinds: [7], limit:500))
                            }
                        }
                        .padding(.bottom, 40)
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                    }
                    else {
                        ProgressView()
                    }
                }
                .hCentered()
            }
        }
        .background(Color("ListBackground"))
        .onAppear {
            guard !didLoad else { return }
            load()
        }
        .onReceive(receiveNotification(.newReactions)) { _ in
            guard let account = NosturState.shared.account else { return }
            let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
            fl.predicate = NSPredicate(
                format:
                    "created_at >= %i AND NOT pubkey IN %@ AND kind == 7 AND reactionTo.pubkey == %@",
                    currentNewestCreatedAt,
                account.blockedPubkeys_,
                account.publicKey
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
        .onReceive(receiveNotification(.activeAccountChanged)) { _ in
            fl.events = []
            backlog.clear()
            load()
        }
        .onChange(of: settings.webOfTrustLevel) { _ in
            fl.nrPosts = []
            backlog.clear()
            load()
        }
        .simultaneousGesture(
               DragGesture().onChanged({
                   if 0 < $0.translation.height {
                       sendNotification(.scrollingUp)
                   }
                   else if 0 > $0.translation.height {
                       sendNotification(.scrollingDown)
                   }
               }))
    }
    
    @State var subscriptions = Set<AnyCancellable>()
    
    func load() {
        guard let account = NosturState.shared.account else { return }
        didLoad = true
        fl.$events
            .sink { events in
                let myNotesReactedTo = self.myNotesReactedTo(events)
                DataProvider.shared().bg.perform {
                    let transformed = myNotesReactedTo
                        .compactMap { $0.toBG() }
                        .map { NRPost(event: $0) }
                    
                    DispatchQueue.main.async {
                        self.myNotesReactedToAsNRPosts = transformed
                    }
                }
            }
            .store(in: &subscriptions)
        
        fl.reset()
        fl.nrPostTransform = false
        fl.predicate = NSPredicate(
            format: "NOT pubkey IN %@ AND kind == 7 AND reactionTo.pubkey == %@",
            account.blockedPubkeys_,
            account.publicKey
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
                    pubkeys: [account.publicKey],
                    kinds: [7],
                    limit: 5000,
                    subscriptionId: taskId,
                    since: NTimestamp(timestamp: Int(fl.events.first?.created_at ?? 0))
                ))
            },
            processResponseCommand: { (taskId, _) in
//                    print("🟠🟠🟠 processResponseCommand \(taskId)")
                let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
                fl.predicate = NSPredicate(
                    format: "created_at >= %i AND NOT pubkey IN %@ AND kind == 7 AND reactionTo.pubkey == %@",
                        currentNewestCreatedAt,
                    account.blockedPubkeys_,
                    account.publicKey
                  )
                fl.loadNewerEvents(5000, taskId: taskId)
            })
        
        backlog.add(fetchNewerTask)
        fetchNewerTask.fetch()
        
        fixReactionsWithMissingRelation()
    }
    
    func fixReactionsWithMissingRelation() {
        guard let account = NosturState.shared.account else { return }
        let mr = Event.fetchRequest()
        mr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        mr.predicate = NSPredicate(format: "kind == 7 AND tagsSerialized CONTAINS %@ AND reactionTo == nil", serializedP(account.publicKey))

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
                        PFP(pubkey: reactions[index].pubkey, contact: reactions[index].contact)
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
        
        guard !(missingPubkeys + emptyContactPubkeys).isEmpty else { return }
        print("Fetching  \((missingPubkeys + emptyContactPubkeys).count) missing or empty contacts")
        QueuedFetcher.shared.enqueue(pTags:  missingPubkeys + emptyContactPubkeys)
    }
}

struct NotificationsV_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadRepliesAndReactions()
        }) {
            VStack {
                NotificationsReactions()
            }
        }
    }
}
