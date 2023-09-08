//
//  NotificationsPostsNew.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/05/2023.
//

import SwiftUI
import CoreData

struct NotificationsPosts: View {
    @EnvironmentObject var theme:Theme
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var ns:NosturState
    @StateObject var fl = FastLoader()
    @State var backlog = Backlog()
    @State var didLoad = false
    
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_notifications_tab") var selectedNotificationsTab = "Posts"
    
    @FetchRequest
    var pNotifications:FetchedResults<PersistentNotification>
    
    init(pubkey: String) {
        let fr = PersistentNotification.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
        fr.predicate = NSPredicate(format: "pubkey == %@ AND type_ == %@", pubkey, PNType.newFollowers.rawValue)
        _pNotifications = FetchRequest(fetchRequest: fr)
    }
    
    var notifications:[PostOrNotification] {
        // combine nrPosts and PersistentNotifications in the list
        return (pNotifications.map { pNot in
            PostOrNotification(id: "NOTIF-" + pNot.id.uuidString , type: .NOTIFICATION, notification: pNot)
        } + fl.nrPosts.map({ nrPost in
            PostOrNotification(id: nrPost.id, type: .POST, post: nrPost)
        }))
        .sorted(by: { p1, p2 in
            p1.createdAt > p2.createdAt
        })
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(notifications) { pNotification in
                    switch pNotification.type {
                    case .NOTIFICATION:
                        NewFollowersNotificationView(notification: pNotification.notification!)
                            .padding(10)
                            .background(theme.background)
                            .id(pNotification.id)
                    case .POST:
                        Box(nrPost: pNotification.post!) {
                            PostRowDeletable(nrPost: pNotification.post!, missingReplyTo: true)
                        }
                        .id(pNotification.id)
                    }
                }
                VStack {
                    if !fl.nrPosts.isEmpty {
                        Button("Show more") {
                            loadMore()
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
        .background(theme.listBackground)
        .onAppear {
            guard !didLoad else { return }
            load()
        }
        .onReceive(receiveNotification(.newMentions)) { _ in
            guard let account = NosturState.shared.account else { return }
            let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
            fl.onComplete = {
                saveLastSeenPostCreatedAt() // onComplete from local database
            }
            fl.predicate = NSPredicate(
                format:
                    "created_at >= %i AND NOT pubkey IN %@ AND kind IN {1,9802,30023} AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@) AND flags != \"is_update\" ",
                    currentNewestCreatedAt,
                account.blockedPubkeys_ + [account.publicKey],
                serializedP(account.publicKey),
                account.mutedRootIds_,
                account.mutedRootIds_,
                account.mutedRootIds_
            )
            fl.loadNewer(250, taskId:"newMentions")
        }
        .onReceive(receiveNotification(.importedMessagesFromSubscriptionIds)) { notification in
            let importedSubIds = notification.object as! ImportedNotification

            let reqTasks = backlog.tasks(with: importedSubIds.subscriptionIds)

            reqTasks.forEach { task in
                task.process()
            }
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
            let account = notification.object as! Account
            pNotifications.nsPredicate = NSPredicate(format: "pubkey == %@ AND type_ == %@", account.publicKey, PNType.newFollowers.rawValue)
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
            let blockedPubkeys = notification.object as! [String]
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
    
    func load() {
        guard let account = NosturState.shared.account else { return }
        didLoad = true
        fl.predicate = NSPredicate(
            format: "NOT pubkey IN %@ AND kind IN {1,9802,30023} AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@) AND flags != \"is_update\" ",
            (account.blockedPubkeys_ + [account.publicKey]),
            serializedP(account.publicKey),
            account.mutedRootIds_,
            account.mutedRootIds_,
            account.mutedRootIds_)
        
        
        fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fl.onComplete = {
            saveLastSeenPostCreatedAt() // onComplete from local database
            self.fetchNewer()
            fl.onComplete = {
                saveLastSeenPostCreatedAt() // onComplete from local database
            }
        }
        fl.loadMore(25)
    }
    
    func fetchNewer() {
        guard let account = NosturState.shared.account else { return }
        let fetchNewerTask = ReqTask(
            reqCommand: { (taskId) in
                req(RM.getMentions(
                    pubkeys: [account.publicKey],
                    kinds: [1],
                    limit: 500,
                    subscriptionId: taskId,
                    since: NTimestamp(timestamp: Int(fl.nrPosts.first?.created_at ?? 0))
                ))
            },
            processResponseCommand: { (taskId, _) in
                let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
                fl.predicate = NSPredicate(
                    format:
                        "created_at >= %i AND NOT pubkey IN %@ AND kind IN {1,9802,30023} AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@) AND flags != \"is_update\" ",
                        currentNewestCreatedAt,
                    (account.blockedPubkeys_ + [account.publicKey]),
                    serializedP(account.publicKey),
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
    
    func saveLastSeenPostCreatedAt() {
        guard selectedTab == "Notifications" && selectedNotificationsTab == "Posts" else { return }
        if let first = fl.nrPosts.first {
            let firstCreatedAt = first.created_at
            DataProvider.shared().bg.perform {
                if let account = NosturState.shared.bgAccount {
                    if account.lastSeenPostCreatedAt != firstCreatedAt {
                        account.lastSeenPostCreatedAt = firstCreatedAt
                    }
                }
                DataProvider.shared().bgSave()
            }
        }
    }
    
    func loadMore() {
        guard let account = NosturState.shared.account else { return }
        fl.predicate = NSPredicate(
            format: "NOT pubkey IN %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
            (account.blockedPubkeys_ + [account.publicKey]),
            serializedP(account.publicKey),
            account.mutedRootIds_,
            account.mutedRootIds_,
            account.mutedRootIds_)
        fl.loadMore(25)
        let fetchMoreTask = ReqTask(
            reqCommand: { (taskId) in
                req(RM.getMentions(
                    pubkeys: [account.publicKey],
                    kinds: [1],
                    limit: 50,
                    subscriptionId: taskId,
                    until: NTimestamp(timestamp: Int(fl.nrPosts.last?.created_at ?? Int64(Date.now.timeIntervalSince1970)))
                ))
            },
            processResponseCommand: { (taskId, _) in
                fl.predicate = NSPredicate(
                    format: "NOT pubkey IN %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
                    (account.blockedPubkeys_ + [account.publicKey]),
                    serializedP(account.publicKey),
                    account.mutedRootIds_,
                    account.mutedRootIds_,
                    account.mutedRootIds_)
                fl.loadMore(25)
            })

        backlog.add(fetchMoreTask)
        fetchMoreTask.fetch()
    }
}

struct NotificationsNotes_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNewFollowersNotification()
        }) {
            VStack {
                NotificationsPosts(pubkey: pubkey)
            }
        }
    }
}



struct PostOrNotification: Identifiable {
    let id:String
    let type:PostOrNotificationType
    var post:NRPost?
    var notification:PersistentNotification?
    
    var createdAt:Date {
        (type == .POST ? post!.createdAt : notification!.createdAt)
    }
    
    enum PostOrNotificationType {
        case POST
        case NOTIFICATION
    }
}
