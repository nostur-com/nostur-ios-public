////
////  NotificationsRepostsGrouped.swift
////  Nostur
////
////  Created by Fabian Lachman on 26/09/2023.
////
//
//import SwiftUI
//import CoreData
//
//// Copy pasta from NotificationsMentions, which was copy pasta from NotificationsPosts
//struct NotificationsRepostsGrouped: View {
//    @EnvironmentObject private var themes:Themes
//    @ObservedObject private var settings:SettingsStore = .shared
//    @StateObject private var fl = FastLoader()
//    @State private var backlog = Backlog()
//    @State private var didLoad = false
//    
//    private var selectedTab: String {
//        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
//        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
//    }
//    
//    private var selectedNotificationsTab: String {
//        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Reposts" }
//        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
//    }
//        
//    var body: some View {
//        ScrollView {
//            LazyVStack(spacing: GUTTER) {
//                ForEach(fl.nrPosts) { nrPost in
//                    Box(nrPost: nrPost) {
//                        // TODO: Put grouped repost header here
//                        KindResolver(nrPost: nrPost, fullWidth: settings.fullWidthImages, hideFooter: !settings.rowFooterEnabled, missingReplyTo: true, isDetail: false, theme: themes.theme)
//                    }
//                    .id(nrPost.id)
//                }
//                VStack {
//                    if !fl.nrPosts.isEmpty {
//                        Button("Show more") {
//                            loadMore()
//                        }
//                        .padding(.bottom, 40)
//                        .buttonStyle(.bordered)
//                    }
//                    else {
//                        ProgressView()
//                    }
//                }
//                .hCentered()
//            }
//        }
//        .background(themes.theme.listBackground)
//        .onAppear {
//            guard !didLoad else { return }
//            load()
//        }
//        .onReceive(receiveNotification(.newReposts)) { [weak fl] _ in
//            guard let fl else { return }
//            guard let account = account() else { return }
//            let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
//            fl.onComplete = {
//                saveLastSeenRepostCreatedAt() // onComplete from local database
//            }
//            fl.predicate = NSPredicate(
//                format:
//                    "created_at >= %i AND NOT pubkey IN %@ AND kind == 6 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@) AND flags != \"is_update\" ",
//                    currentNewestCreatedAt,
//                AppState.shared.bgAppState.blockedPubkeys + [account.publicKey],
//                serializedP(account.publicKey),
//                AppState.shared.bgAppState.mutedRootIds,
//                AppState.shared.bgAppState.mutedRootIds,
//                AppState.shared.bgAppState.mutedRootIds
//            )
//            fl.loadNewer(250, taskId: "newReposts")
//        }
//        .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { [weak backlog] subscriptionIds in
//            bg().perform {
//                guard let backlog else { return }
//                let reqTasks = backlog.tasks(with: subscriptionIds)
//                reqTasks.forEach { task in
//                    task.process()
//                }
//            }
//        }
//        .onReceive(receiveNotification(.activeAccountChanged)) { [weak fl, weak backlog] _ in
//            guard let fl, let backlog else { return }
//            fl.nrPosts = []
//            backlog.clear()
//            load()
//        }
//        .onChange(of: settings.webOfTrustLevel) { [weak fl, weak backlog] _ in
//            guard let fl, let backlog else { return }
//            fl.nrPosts = []
//            backlog.clear()
//            load()
//        }
//        .onReceive(receiveNotification(.blockListUpdated)) { [weak fl] notification in
//            guard let fl else { return }
//            let blockedPubkeys = notification.object as! Set<String>
//            fl.nrPosts = fl.nrPosts.filter { !blockedPubkeys.contains($0.pubkey)  }
//        }
//        .onReceive(receiveNotification(.muteListUpdated)) { [weak fl] _ in
//            guard let fl else { return }
//            fl.nrPosts = fl.nrPosts.filter(notMuted)
//        }
//    }
//    
//    private func load() {
//        guard let account = account() else { return }
//        didLoad = true
//        fl.predicate = NSPredicate(
//            format: "NOT pubkey IN %@ AND kind == 6 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@) AND flags != \"is_update\" ",
//            (AppState.shared.bgAppState.blockedPubkeys + [account.publicKey]),
//            serializedP(account.publicKey),
//            AppState.shared.bgAppState.mutedRootIds,
//            AppState.shared.bgAppState.mutedRootIds,
//            AppState.shared.bgAppState.mutedRootIds)
//        
//        
//        fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
//        fl.onComplete = { [weak fl] in
//            guard let fl else { return }
//            saveLastSeenRepostCreatedAt() // onComplete from local database
//            self.fetchNewer()
//            fl.onComplete = {
//                saveLastSeenRepostCreatedAt() // onComplete from local database
//            }
//        }
//        fl.loadMore(25)
//    }
//    
//    private func fetchNewer() {
//        guard let account = account() else { return }
//        let fetchNewerTask = ReqTask(
//            reqCommand: { [weak fl] (taskId) in
//                guard let fl else { return }
//                req(RM.getMentions(
//                    pubkeys: [account.publicKey],
//                    kinds: [6],
//                    limit: 500,
//                    subscriptionId: taskId,
//                    since: NTimestamp(timestamp: Int(fl.nrPosts.first?.created_at ?? 0))
//                ))
//            },
//            processResponseCommand: { [weak fl] (taskId, _, _) in
//                guard let fl else { return }
//                let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
//                fl.predicate = NSPredicate(
//                    format:
//                        "created_at >= %i AND NOT pubkey IN %@ AND kind == 6 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@) AND flags != \"is_update\" ",
//                        currentNewestCreatedAt,
//                    (AppState.shared.bgAppState.blockedPubkeys + [account.publicKey]),
//                    serializedP(account.publicKey),
//                    AppState.shared.bgAppState.mutedRootIds,
//                    AppState.shared.bgAppState.mutedRootIds,
//                    AppState.shared.bgAppState.mutedRootIds
//                  )
//                fl.loadNewer(taskId: taskId)
//            },
//            timeoutCommand: { [weak fl] taskId in
//                guard let fl else { return }
//                fl.loadNewer(taskId: taskId)
//            })
//
//        backlog.add(fetchNewerTask)
//        fetchNewerTask.fetch()
//    }
//    
//    private func saveLastSeenRepostCreatedAt() {
//        guard selectedTab == "Notifications" && selectedNotificationsTab == "Reposts" else { return }
//        if let first = fl.nrPosts.first {
//            let firstCreatedAt = first.created_at
//            bg().perform {
//                if let account = account() {
//                    if account.lastSeenRepostCreatedAt != firstCreatedAt {
//                        account.lastSeenRepostCreatedAt = firstCreatedAt
//                    }
//                }
//                DataProvider.shared().bgSave()
//            }
//        }
//    }
//    
//    private func loadMore() {
//        guard let account = account() else { return }
//        fl.predicate = NSPredicate(
//            format: "NOT pubkey IN %@ AND kind == 6 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
//            (AppState.shared.bgAppState.blockedPubkeys + [account.publicKey]),
//            serializedP(account.publicKey),
//            AppState.shared.bgAppState.mutedRootIds,
//            AppState.shared.bgAppState.mutedRootIds,
//            AppState.shared.bgAppState.mutedRootIds)
//        fl.loadMore(25)
//        let fetchMoreTask = ReqTask(
//            reqCommand: { [weak fl] (taskId) in
//                guard let fl else { return }
//                req(RM.getMentions(
//                    pubkeys: [account.publicKey],
//                    kinds: [6],
//                    limit: 50,
//                    subscriptionId: taskId,
//                    until: NTimestamp(timestamp: Int(fl.nrPosts.last?.created_at ?? Int64(Date.now.timeIntervalSince1970)))
//                ))
//            },
//            processResponseCommand: { [weak fl] (taskId, _, _) in
//                guard let fl else { return }
//                fl.predicate = NSPredicate(
//                    format: "NOT pubkey IN %@ AND kind == 6 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
//                    (AppState.shared.bgAppState.blockedPubkeys + [account.publicKey]),
//                    serializedP(account.publicKey),
//                    AppState.shared.bgAppState.mutedRootIds,
//                    AppState.shared.bgAppState.mutedRootIds,
//                    AppState.shared.bgAppState.mutedRootIds)
//                fl.loadMore(25)
//            })
//
//        backlog.add(fetchMoreTask)
//        fetchMoreTask.fetch()
//    }
//}
//
//#Preview("Notifications Grouped Reposts") {
//    return PreviewContainer({ pe in
//        pe.loadContacts()
//        pe.loadPosts()
//    }) {
//        VStack {
//            NotificationsRepostsGrouped()
//        }
//    }
//}
