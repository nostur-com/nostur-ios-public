//
//  NotificationsReposts.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/09/2023.
//

import SwiftUI
import CoreData
import NavigationBackport

// Copy pasta from NotificationsMentions, which was copy pasta from NotificationsPosts
struct NotificationsReposts: View {
    public let pubkey: String
    @Binding public var navPath: NBNavigationPath
    @EnvironmentObject private var themes: Themes
    @StateObject private var model = RepostsFeedModel()
    @ObservedObject private var settings: SettingsStore = .shared

    @State private var backlog = Backlog()
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Reposts" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
    }
        
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: GUTTER) {
                    ForEach(model.reposts) { nrPost in
                        Box(nrPost: nrPost) {
                            VStack(alignment: .leading, spacing: 0) {
                                RepostHeader(repostedHeader: nrPost.repostedHeader, pubkey: nrPost.pubkey)
                                    .offset(x: -35)
                                    .onAppear { self.enqueue(nrPost) }
                                    .onDisappear { self.dequeue(nrPost) }
                                if let firstQuote = nrPost.firstQuote {
                                    MinimalNoteTextRenderView(nrPost: firstQuote, lineLimit: 5)
                                        .onTapGesture {
                                            navigateTo(firstQuote, context: "Default")
                                        }
                                }
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Ago(nrPost.createdAt).layoutPriority(2)
                                .foregroundColor(.gray)
                                .padding(10)
                        }
                        .id(nrPost.id)
                    }
                    VStack {
                        if !model.reposts.isEmpty {
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
                guard selectedNotificationsTab == "Reposts" else { return }
                guard let tabName = notification.object as? String, tabName == "Notifications" else { return }
                if navPath.count == 0, let topId = model.reposts.first?.id {
                    withAnimation {
                        proxy.scrollTo(topId)
                    }
                }
            }
        }
        .background(themes.theme.listBackground)
        .onAppear {
            model.setup(pubkey: pubkey)
            model.load(limit: 50)
            fetchNewer()
        }
        .onChange(of: pubkey) { newPubkey in
            model.setup(pubkey: newPubkey)
            model.load(limit: 50)
            fetchNewer()
        }
        .onReceive(receiveNotification(.newReposts)) { _ in
            // Receive here for logged in account (from NotificationsViewModel). In multi-column we don't track .newReposts for other accounts (unread badge)
            model.load(limit: 50) { mostRecentCreatedAt in
                saveLastSeenRepostCreatedAt(mostCreatedAt: mostRecentCreatedAt)
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
            model.load(limit: 50)
            fetchNewer()
        }
    }
    
    private func fetchNewer() {
        L.og.debug("🥎🥎 fetchNewer() (REPOSTS)")
        let fetchNewerTask = ReqTask(
            reqCommand: { taskId in
                bg().perform {
                    req(RM.getMentions(
                        pubkeys: [pubkey],
                        kinds: [6],
                        limit: 500,
                        subscriptionId: taskId,
                        since: NTimestamp(timestamp: Int(model.mostRecentRepostCreatedAt))
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
    
    private func saveLastSeenRepostCreatedAt(mostCreatedAt: Int64) {
        guard selectedTab == "Notifications" && selectedNotificationsTab == "Reposts" else { return }
        guard mostCreatedAt != 0 else { return }
        if let account = account() {
            if account.lastSeenRepostCreatedAt < mostCreatedAt {
                account.lastSeenRepostCreatedAt = mostCreatedAt
                viewContextSave() // Account is from main context
            }
        }
    }
    
    private func enqueue(_ nrPost: NRPost) {
        if !nrPost.missingPs.isEmpty {
            bg().perform {
                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NotificationReposts.001")
                QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
            }
        }
    }
    
    private func dequeue(_ nrPost: NRPost) {
        if !nrPost.missingPs.isEmpty {
            QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
        }
    }
}

import NavigationBackport

#Preview("Notifications Reposts") {
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        VStack {
            NotificationsReposts(pubkey: AccountsState.shared.activeAccountPublicKey, navPath: .constant(NBNavigationPath()))
        }
    }
}
