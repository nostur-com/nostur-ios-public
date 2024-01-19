//
//  Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import SwiftUI
import CoreData
import Combine
import NavigationBackport

struct NotificationsReactions: View {
    @Binding public var navPath: NBNavigationPath
    @EnvironmentObject private var themes:Themes
    @StateObject private var fl = FastLoader()
    @State private var didLoad = false
    @State private var backlog = Backlog()
    @ObservedObject private var settings:SettingsStore = .shared
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Reactions" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
    }
    
    @Namespace private var top
    
    private func myNotesReactedTo(_ events:[Event]) -> [Event] {
        
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
    
    @State private var myNotesReactedToAsNRPosts:[NRPost] = []
    
    private func reactionsForNote(_ id:String) -> [Event] {
        fl.events.compactMap {  $0.reactionToId == id ? $0 : nil }
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                LazyVStack(alignment:.leading, spacing: 10) {
                    ForEach(myNotesReactedToAsNRPosts) { nrPost in
                        Box(nrPost: nrPost, navMode: .view) {
                            VStack(alignment:.leading, spacing: 3) {
                                ReactionsForThisNote(reactions:reactionsForNote(nrPost.id))
                                NoteMinimalContentView(nrPost: nrPost)
                            }
                        }
                        .id(nrPost.id)
                    }
                    VStack {
                        if !myNotesReactedToAsNRPosts.isEmpty {
                            Button("Show more") {
                                guard let account = account() else { return }
                                fl.predicate = NSPredicate(
                                    format: "otherPubkey == %@ AND kind == 7 AND NOT pubkey IN %@",
                                    account.publicKey,
                                    NRState.shared.blockedPubkeys)
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
    //                        .tint(.accentColor)
                        }
                        else {
                            ProgressView()
                        }
                    }
                    .hCentered()
                }
            }
            .onReceive(receiveNotification(.didTapTab)) { notification in
                guard selectedNotificationsTab == "Reactions" else { return }
                guard let tabName = notification.object as? String, tabName == "Notifications" else { return }
                if navPath.count == 0 {
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
            }
        }
        .background(themes.theme.listBackground)
        .onAppear {
            guard !didLoad else { return }
            load()
        }
        .onReceive(receiveNotification(.newReactions)) { [weak fl] _ in
            guard let fl else { return }
            guard let account = account() else { return }
            let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
            fl.onComplete = {
                saveLastSeenReactionCreatedAt() // onComplete from local database
            }
            fl.predicate = NSPredicate(
                format:
                    "created_at >= %i AND otherPubkey == %@ AND kind == 7 AND NOT pubkey IN %@",
                    currentNewestCreatedAt,
                account.publicKey,
                NRState.shared.blockedPubkeys
            )
            fl.loadNewerEvents(5000, taskId:"newReactions")
        }
        .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { [weak fl, weak backlog] subscriptionIds in
            bg().perform {
                guard let fl, let backlog else { return }
                let reqTasks = backlog.tasks(with: subscriptionIds)
                reqTasks.forEach { task in
                    task.process()
                }
            }
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { [weak fl, weak backlog] _ in
            guard let fl, let backlog else { return }
            fl.events = []
            backlog.clear()
            load()
        }
        .onChange(of: settings.webOfTrustLevel) { [weak fl, weak backlog] _ in
            guard let fl, let backlog else { return }
            fl.events = []
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
        guard let account = account() else { return }
        didLoad = true
        fl.$events
            .sink { events in
                let myNotesReactedTo = self.myNotesReactedTo(events)
                bg().perform {
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
            format: "otherPubkey == %@ AND kind == 7 AND NOT pubkey IN %@",
            account.publicKey,
            NRState.shared.blockedPubkeys
        )
        fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fl.onComplete = { [weak fl] in
            saveLastSeenReactionCreatedAt() // onComplete from local database
            self.fetchNewer()
            fl?.onComplete = { // set onComplete again because self.fetchNewer() should only run once
                saveLastSeenReactionCreatedAt() // onComplete from local database
            }
        }
        fl.loadMore(500)
        
        fixReactionsWithMissingRelation()
    }
    
    func fetchNewer() {
        guard let account = account() else { return }
        let fetchNewerTask = ReqTask(
            reqCommand: { [weak fl] (taskId) in
                guard let fl else { return }
                req(RM.getMentions(
                    pubkeys: [account.publicKey],
                    kinds: [7],
                    limit: 5000,
                    subscriptionId: taskId,
                    since: NTimestamp(timestamp: Int(fl.events.first?.created_at ?? 0))
                ))
            },
            processResponseCommand: { [weak fl] (taskId, _, _) in
                guard let fl else { return }
//                    print("🟠🟠🟠 processResponseCommand \(taskId)")
                let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
                fl.predicate = NSPredicate(
                    format: "created_at >= %i AND otherPubkey == %@ AND kind == 7 AND NOT pubkey IN %@",
                    currentNewestCreatedAt,
                    account.publicKey,
                    NRState.shared.blockedPubkeys
                )
                fl.loadNewerEvents(5000, taskId: taskId)
            },
            timeoutCommand: { [weak fl] taskId in
                guard let fl else { return }
                fl.loadNewerEvents(5000, taskId: taskId)
            })
        
        backlog.add(fetchNewerTask)
        fetchNewerTask.fetch()
    }
    
    func saveLastSeenReactionCreatedAt() {
        guard selectedTab == "Notifications" && selectedNotificationsTab == "Reactions" else { return }
        if let first = fl.events.first {
            let firstCreatedAt = first.created_at
            bg().perform {
                if let account = account() {
                    if account.lastSeenReactionCreatedAt < firstCreatedAt {
                        account.lastSeenReactionCreatedAt = firstCreatedAt
                    }
                }
                DataProvider.shared().bgSave()
            }
        }
    }
    
    func fixReactionsWithMissingRelation() {
        guard let account = account() else { return }
        let mr = Event.fetchRequest()
        mr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        mr.predicate = NSPredicate(format: "otherPubkey == %@ AND kind == 7 AND reactionTo == nil", account.publicKey)

        Task.detached(priority: .medium) {
            bg().perform {
                if let danglingReactions = try? bg().fetch(mr) {
                    danglingReactions
                        .forEach { reaction in
                            _ = reaction.reactionTo_ // this lazy load fixes the relation
                        }
                }
            }

        }
    }
}

struct ReactionsForThisNote: View {
    public var reactions:[Event]
    
    private var withoutDuplicates:[Event] { // Author may accidentally like multiple times
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
                        PFP(pubkey: reactions[index].pubkey, contact: reactions[index].contact, forceFlat: true)
                            .id(reactions[index].id)
                            .zIndex(-Double(index))
                        Text(reactions[index].content == "+" ? "❤️" : reactions[index].content ?? "❤️")
                            .offset(x: 5, y: 15)
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
        .drawingGroup()
        .onAppear {
            self.fetchMissingEventContacts(events:Array(withoutDuplicates.prefix(10)))
        }
    }
    
    private func fetchMissingEventContacts(events:[Event]) {
        let pubkeys = pubkeys(events)
        let contacts = Contact.fetchByPubkeys(pubkeys, context: DataProvider.shared().viewContext)
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
        L.og.debug("Fetching  \((missingPubkeys + emptyContactPubkeys).count) missing or empty contacts")
        QueuedFetcher.shared.enqueue(pTags: (missingPubkeys + emptyContactPubkeys))
    }
}

struct NotificationsV_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadRepliesAndReactions()
        }) {
            VStack {
                NotificationsReactions(navPath: .constant(NBNavigationPath()))
            }
        }
    }
}
