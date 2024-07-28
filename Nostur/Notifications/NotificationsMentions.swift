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
    @EnvironmentObject private var themes: Themes
    @StateObject private var model = MentionsFeedModel()
    @ObservedObject private var settings: SettingsStore = .shared

    @State private var backlog = Backlog()
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Notifications" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Mentions" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
    }
    
    @Namespace private var top
        
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                LazyVStack(spacing: 2) {
                    ForEach(model.mentions) { nrPost in
                        Box(nrPost: nrPost) {
                            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                        }
                        .id(nrPost.id)
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
            }
            .onReceive(receiveNotification(.didTapTab)) { notification in
                guard selectedNotificationsTab == "Mentions" else { return }
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
        .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { [weak backlog] subscriptionIds in
            bg().perform {
                guard let backlog else { return }
                let reqTasks = backlog.tasks(with: subscriptionIds)
                reqTasks.forEach { task in
                    task.process()
                }
            }
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
    
    private func fetchNewer() {
        L.og.debug("🥎🥎 fetchNewer() (MENTIONS)")
        let fetchNewerTask = ReqTask(
            reqCommand: { taskId in
                bg().perform {
                    req(RM.getMentions(
                        pubkeys: [pubkey],
                        kinds: [1,9802,30023,34235],
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
                viewContextSave() // Account is from main context
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
            NotificationsMentions(pubkey: NRState.shared.activeAccountPublicKey, navPath: .constant(NBNavigationPath()))
        }
    }
}
