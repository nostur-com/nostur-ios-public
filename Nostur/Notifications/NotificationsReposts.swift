//
//  NotificationsReposts.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/09/2023.
//

import SwiftUI
import CoreData

// Copy pasta from NotificationsMentions, which was copy pasta from NotificationsPosts
struct NotificationsReposts: View {
    @Binding public var navPath:NavigationPath
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings:SettingsStore = .shared
    @StateObject private var fl = FastLoader()
    @State private var backlog = Backlog()
    @State private var didLoad = false
    @Namespace private var top
    
    @AppStorage("selected_tab") private var selectedTab = "Main"
    @AppStorage("selected_notifications_tab") private var selectedNotificationsTab = "Reposts"
        
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                LazyVStack(spacing: 10) {
                    ForEach(fl.nrPosts) { nrPost in
                        Box(nrPost: nrPost) {
                            VStack(alignment: .leading, spacing: 0) {
                                RepostHeader(repostedHeader: nrPost.repostedHeader, pubkey: nrPost.pubkey)
                                    .offset(x: -35)
                                if let firstQuote = nrPost.firstQuote {
                                    MinimalNoteTextRenderView(nrPost: firstQuote, lineLimit: 5)
                                        .onTapGesture {
                                            navigateTo(firstQuote)
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
                        if !fl.nrPosts.isEmpty {
                            Button("Show more") {
                                loadMore()
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
        .onReceive(receiveNotification(.newReposts)) { _ in
            guard let account = account() else { return }
            let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
            fl.onComplete = {
                saveLastSeenRepostCreatedAt() // onComplete from local database
            }
            fl.predicate = NSPredicate(
                format:
                    "created_at >= %i AND otherPubkey == %@ AND kind == 6 AND NOT pubkey IN %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
                currentNewestCreatedAt,
                account.publicKey,
                account.blockedPubkeys_ + [account.publicKey],
                account.mutedRootIds_,
                account.mutedRootIds_,
                account.mutedRootIds_
            )
            fl.loadNewer(250, taskId: "newReposts")
        }
        .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { subscriptionIds in
            bg().perform {
                let reqTasks = backlog.tasks(with: subscriptionIds)
                reqTasks.forEach { task in
                    task.process()
                }
            }
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { _ in
            fl.nrPosts = []
            backlog.clear()
            load()
        }
        .onChange(of: settings.webOfTrustLevel) { _ in
            fl.nrPosts = []
            backlog.clear()
            load()
        }
        .onReceive(receiveNotification(.blockListUpdated)) { notification in
            let blockedPubkeys = notification.object as! Set<String>
            fl.nrPosts = fl.nrPosts.filter { !blockedPubkeys.contains($0.pubkey)  }
        }
        .onReceive(receiveNotification(.muteListUpdated)) { _ in
            fl.nrPosts = fl.nrPosts.filter(notMuted)
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
    
    private func load() {
        guard let account = account() else { return }
        didLoad = true
        fl.predicate = NSPredicate(
            format: "otherPubkey == %@ AND kind == 6 AND NOT pubkey IN %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
            account.publicKey,
            (account.blockedPubkeys_ + [account.publicKey]),
            account.mutedRootIds_,
            account.mutedRootIds_,
            account.mutedRootIds_)
        
        
        fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fl.onComplete = {
            saveLastSeenRepostCreatedAt() // onComplete from local database
            self.fetchNewer()
            fl.onComplete = {
                saveLastSeenRepostCreatedAt() // onComplete from local database
            }
        }
        fl.loadMore(25)
    }
    
    private func fetchNewer() {
        guard let account = account() else { return }
        let fetchNewerTask = ReqTask(
            reqCommand: { (taskId) in
                req(RM.getMentions(
                    pubkeys: [account.publicKey],
                    kinds: [6],
                    limit: 500,
                    subscriptionId: taskId,
                    since: NTimestamp(timestamp: Int(fl.nrPosts.first?.created_at ?? 0))
                ))
            },
            processResponseCommand: { (taskId, _, _) in
                let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
                fl.predicate = NSPredicate(
                    format:
                        "created_at >= %i AND otherPubkey == %@ AND kind == 6 AND NOT pubkey IN %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
                    currentNewestCreatedAt,
                    account.publicKey,
                    (account.blockedPubkeys_ + [account.publicKey]),
                    account.mutedRootIds_,
                    account.mutedRootIds_,
                    account.mutedRootIds_
                  )
                fl.loadNewer(taskId: taskId)
            },
            timeoutCommand: { taskId in
                fl.loadNewer(taskId: taskId)
            })

        backlog.add(fetchNewerTask)
        fetchNewerTask.fetch()
    }
    
    private func saveLastSeenRepostCreatedAt() {
        guard selectedTab == "Notifications" && selectedNotificationsTab == "Reposts" else { return }
        if let first = fl.nrPosts.first {
            let firstCreatedAt = first.created_at
            bg().perform {
                if let account = account() {
                    if account.lastSeenRepostCreatedAt < firstCreatedAt {
                        account.lastSeenRepostCreatedAt = firstCreatedAt
                    }
                }
                DataProvider.shared().bgSave()
            }
        }
    }
    
    private func loadMore() {
        guard let account = account() else { return }
        fl.predicate = NSPredicate(
            format: "otherPubkey == %@ AND kind == 6 AND NOT pubkey IN %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
            account.publicKey,
            (account.blockedPubkeys_ + [account.publicKey]),
            account.mutedRootIds_,
            account.mutedRootIds_,
            account.mutedRootIds_)
        fl.loadMore(25)
        let fetchMoreTask = ReqTask(
            reqCommand: { (taskId) in
                req(RM.getMentions(
                    pubkeys: [account.publicKey],
                    kinds: [6],
                    limit: 50,
                    subscriptionId: taskId,
                    until: NTimestamp(timestamp: Int(fl.nrPosts.last?.created_at ?? Int64(Date.now.timeIntervalSince1970)))
                ))
            },
            processResponseCommand: { (taskId, _, _) in
                fl.predicate = NSPredicate(
                    format: "otherPubkey == %@ AND kind == 6 AND NOT pubkey IN %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
                    account.publicKey,
                    (account.blockedPubkeys_ + [account.publicKey]),
                    account.mutedRootIds_,
                    account.mutedRootIds_,
                    account.mutedRootIds_)
                fl.loadMore(25)
            })

        backlog.add(fetchMoreTask)
        fetchMoreTask.fetch()
    }
}

#Preview("Notifications Reposts") {
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        VStack {
            NotificationsReposts(navPath: .constant(NavigationPath()))
        }
    }
}
