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
    public let pubkey: String
    @Binding public var navPath: NBNavigationPath
    @Environment(\.theme) private var theme
    @StateObject private var model = GroupedReactionsFeedModel()
    @State private var backlog = Backlog(backlogDebugName: "NotificationsReactions")
    @ObservedObject private var settings: SettingsStore = .shared
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { setSelectedTab(newValue) }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Reactions" }
        set { setSelectedNotificationsTab(newValue) }
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.groupedReactions) { groupedReactions in
                        Box(nrPost: groupedReactions.nrPost, navMode: .view) {
                            VStack(alignment:.leading, spacing: 3) {
                                ReactionsForThisNote(reactions: groupedReactions.reactions)
                                NoteMinimalContentView(nrPost: groupedReactions.nrPost)
                            }
                        }
                        .id(groupedReactions.nrPost.id)
                    }
                    VStack {
                        if !model.groupedReactions.isEmpty {
                            Button("Show more") {
                                model.showMore()
                            }
                            .padding(.bottom, 40)
                            .buttonStyle(.bordered)
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
                if navPath.count == 0, let topId = model.groupedReactions.first?.id {
                    withAnimation {
                        proxy.scrollTo(topId)
                    }
                }
            }
        }
        .background(theme.listBackground)
        .onAppear {
            model.setup(pubkey: pubkey)
            model.load(limit: 150)
            fetchNewer()
        }
        .onChange(of: pubkey) { newPubkey in
            model.setup(pubkey: newPubkey)
            model.load(limit: 150)
            fetchNewer()
        }
        .onReceive(receiveNotification(.newReactions)) { _ in
            // Receive here for logged in account (from NotificationsViewModel). In multi-column we don't track .newReactions for other accounts (unread badge)
            model.load(limit: 150) { mostRecentCreatedAt in
                saveLastSeenReactionCreatedAt(mostCreatedAt: mostRecentCreatedAt)
            }
        }
        .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { [weak backlog] subscriptionIds in
            bg().perform {
                guard let backlog else { return }
                let reqTasks = backlog.tasks(with: subscriptionIds)
                reqTasks.forEach { task in
                    task.process()
                }
            }
        }
        .onChange(of: settings.webOfTrustLevel) { _ in
            model.setup(pubkey: pubkey)
            model.load(limit: 150)
            fetchNewer()
        }
    }
    
    func fetchNewer() {
#if DEBUG
        L.og.debug("🥎🥎 fetchNewer() (REACTIONS)")
#endif
        let fetchNewerTask = ReqTask(
            reqCommand: { taskId in
                bg().perform {
                    req(RM.getMentions(
                        pubkeys: [pubkey],
                        kinds: [7],
                        limit: 500,
                        subscriptionId: taskId,
                        since: NTimestamp(timestamp: Int(model.mostRecentReactionCreatedAt))
                    ))
                }
            },
            processResponseCommand: { (taskId, _, _) in
                model.load(limit: 500)
            },
            timeoutCommand: { taskId in
                model.load(limit: 500)
            })
        
        backlog.add(fetchNewerTask)
        fetchNewerTask.fetch()
    }
    
    func saveLastSeenReactionCreatedAt(mostCreatedAt: Int64) {
        guard selectedTab == "Notifications" && selectedNotificationsTab == "Reactions" else { return }
        guard mostCreatedAt != 0 else { return }
        if let account = account() {
            if account.lastSeenReactionCreatedAt < mostCreatedAt {
                account.lastSeenReactionCreatedAt = mostCreatedAt
                DataProvider.shared().saveToDiskNow(.viewContext) // Account is from main context
            }
        }
    }
}




struct ReactionsForThisNote: View {
    
    public var reactions: [Reaction]
    
    var body: some View {
        VStack(alignment:.leading) {
            ZStack(alignment:.leading) {
                ForEach(reactions.prefix(10).indices, id:\.self) { index in
                    ZStack(alignment:.leading) {
                        PFP(pubkey: reactions[index].pubkey, pictureUrl: reactions[index].pictureUrl, forceFlat: true)
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
            if (reactions.count > 1) {
                Text("**\(reactions.first(where: { $0.authorName != nil })?.authorName ?? "???")** and \(reactions.count - 1) others reacted on your post")
                    
            }
            else {
                Text("**\(reactions.first(where: { $0.authorName != nil })?.authorName ?? "???")** reacted on your post")
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .overlay(alignment: .topTrailing) {
            if let first = reactions.first {
                Ago(first.createdAt).layoutPriority(2)
                    .foregroundColor(.gray)
            }
        }
        .drawingGroup()
        .onAppear {
            self.fetchMissingEventContacts(reactions: Array(reactions.prefix(10)))
        }
    }
    
    private func fetchMissingEventContacts(reactions: [Reaction]) {
        let bgContext = bg()
        bgContext.perform {
            let pubkeys = reactions.map { $0.pubkey }
            let contacts = Contact.fetchByPubkeys(pubkeys, context: bgContext)
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
}

struct NotificationsV_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadRepliesAndReactions()
        }) {
            VStack {
                NotificationsReactions(pubkey: AccountsState.shared.activeAccountPublicKey, navPath: .constant(NBNavigationPath()))
            }
        }
    }
}
