//
//  NotificationsMentions.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/09/2023.
//

import SwiftUI
import CoreData
import NavigationBackport

struct NotificationsMentions: View {
    public let pubkey: String
    @Binding public var navPath: NBNavigationPath
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @StateObject private var model = MentionsFeedModel()
    @ObservedObject private var settings: SettingsStore = .shared

    @State private var backlog = Backlog(timeout: 12, backlogDebugName: "NotificationsMentions")
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Notifications" }
        set { setSelectedTab(newValue) }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Mentions" }
        set { setSelectedNotificationsTab(newValue) }
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            List {
                ForEach (model.mentions) { nrPost in
                    ZStack { // Without this ZStack wrapper the bookmark list crashes on load ¯\_(ツ)_/¯
                        Box(nrPost: nrPost) {
                            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: theme)
                        }
                    }
                    .id(nrPost.id) // <-- must use .id or can't .scrollTo
                    .listRowSeparator(.hidden)
                    .listRowBackground(theme.listBackground)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .padding(.bottom, GUTTER)
                }
                
                VStack {
                    if !model.mentions.isEmpty {
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
            .environment(\.defaultMinListRowHeight, 50)
            .listStyle(.plain)
            .scrollContentBackgroundHidden()
            
            .onReceive(receiveNotification(.didTapTab)) { notification in
                guard selectedNotificationsTab == "Mentions" else { return }
                guard let tabName = notification.object as? String, tabName == "Notifications" else { return }
                if navPath.count == 0, let topId = model.mentions.first?.id {
                    withAnimation {
                        proxy.scrollTo(topId)
                    }
                }
            }
        }
        .background(theme.listBackground)
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
        .onReceive(receiveNotification(.newMentions)) { _ in
            // Receive here for logged in account (from NotificationsViewModel). In multi-column we don't track .newReposts for other accounts (unread badge)
            model.load(limit: 50) { mostRecentCreatedAt in
                saveLastSeenMentionCreatedAt(mostCreatedAt: mostRecentCreatedAt)
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
#if DEBUG
        L.og.debug("🥎🥎 fetchNewer() (MENTIONS)")
#endif
        let fetchNewerTask = ReqTask(
            reqCommand: { taskId in
                bg().perform {
                    req(RM.getMentions(
                        pubkeys: [pubkey],
                        kinds: [1,1111,1222,1244,20,9802,30023,34235],
                        limit: 500,
                        subscriptionId: taskId,
                        since: NTimestamp(timestamp: Int(model.mostRecentMentionCreatedAt))
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
    
    private func saveLastSeenMentionCreatedAt(mostCreatedAt: Int64) {
        guard selectedTab == "Notifications" && selectedNotificationsTab == "Mentions" else { return }
        guard mostCreatedAt != 0 else { return }
        if let account = account() {
            if account.lastSeenPostCreatedAt < mostCreatedAt {
                account.lastSeenPostCreatedAt = mostCreatedAt
                DataProvider.shared().saveToDiskNow(.viewContext)
            }
        }
    }
}

#Preview("Notifications Mentions") {
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        VStack {
            NotificationsMentions(pubkey: AccountsState.shared.activeAccountPublicKey, navPath: .constant(NBNavigationPath()))
        }
    }
}
