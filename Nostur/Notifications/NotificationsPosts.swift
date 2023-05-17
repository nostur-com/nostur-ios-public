//
//  NotificationsPostsNew.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/05/2023.
//

import SwiftUI
import CoreData

struct NotificationsPosts: View {
    
    let pubkey:String
    let mutedRootIds:[String]
    let blockedPubkeys:[String]
     
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var ns:NosturState
    @StateObject var fl = FastLoader()
    @State var backlog = Backlog()
    @State var didLoad = false
    
    init(pubkey: String, mutedRootIds: [String] = [], blockedPubkeys: [String] = []) {
        self.pubkey = pubkey
        self.mutedRootIds = mutedRootIds
        self.blockedPubkeys = blockedPubkeys
    }
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(fl.nrPosts) { nrPost in
                    PostRowDeletable(nrPost: nrPost)
                        .background(Color.systemBackground)
                        .boxShadow()
                        .padding(.vertical, 10)
                        .padding(.horizontal, settings.fullWidthImages ? 0 : 10)
                        .id(nrPost.id)
                }
                VStack {
                    if fl.nrPosts.count > 0 {
                        Button("Show more") {
                            loadMore()
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
        .onReceive(receiveNotification(.newMentions)) { _ in
            let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
            fl.predicate = NSPredicate(
                format:
                    "created_at >= %i AND NOT pubkey IN %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@) ",
                    currentNewestCreatedAt,
                    blockedPubkeys + [pubkey],
                    serializedP(pubkey),
                    mutedRootIds,
                    mutedRootIds,
                    mutedRootIds
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
        .onReceive(receiveNotification(.activeAccountChanged)) { _ in
            backlog.clear()
            load()
        }
        .onReceive(receiveNotification(.blockListUpdated)) { notification in
            let blockedPubkeys = notification.object as! [String]
            fl.nrPosts = fl.nrPosts.filter { !blockedPubkeys.contains($0.id)  }
        }
    }
    
    func load() {
        didLoad = true
        if (fl.nrPosts.count == 0) {
            req(RM.getMentions(
                pubkeys: [pubkey],
                kinds: [1],
                limit: 50,
                until: NTimestamp(timestamp: Int(fl.nrPosts.last?.created_at ?? Int64(Date.now.timeIntervalSince1970)))
            ))
        }
        fl.reset()
        fl.predicate = NSPredicate(
            format: "NOT pubkey IN %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
                    (blockedPubkeys + [pubkey]),
                    serializedP(pubkey),
                    mutedRootIds,
                    mutedRootIds,
                    mutedRootIds)
        
        
        fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fl.loadMore(25)
//        fl.loadMoreBG(15)

        if let first = fl.nrPosts.first, let account = ns.account {
            let firstCreatedAt = first.created_at
            DataProvider.shared().bg.perform {
                if let account = account.toBG() {
                    account.lastSeenPostCreatedAt = firstCreatedAt
                }
                DataProvider.shared().bgSave()
            }
        }


        let fetchNewerTask = ReqTask(
            reqCommand: { (taskId) in
                req(RM.getMentions(
                    pubkeys: [pubkey],
                    kinds: [1],
                    limit: 500,
                    subscriptionId: taskId,
                    since: NTimestamp(timestamp: Int(fl.nrPosts.first?.created_at ?? 0))
                ))
            },
            processResponseCommand: { (taskId) in
//                    print("🟠🟠🟠 processResponseCommand \(taskId)")
                let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
                fl.predicate = NSPredicate(
                    format:
                        "created_at >= %i AND NOT pubkey IN %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@) ",
                        currentNewestCreatedAt,
                        (blockedPubkeys + [pubkey]),
                        serializedP(pubkey),
                        mutedRootIds,
                        mutedRootIds,
                        mutedRootIds
                  )
            })

        backlog.add(fetchNewerTask)
        fetchNewerTask.fetch()
    }
    
    func loadMore() {
        fl.predicate = NSPredicate(
            format: "NOT pubkey IN %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
                    (blockedPubkeys + [pubkey]),
                    serializedP(pubkey),
                    mutedRootIds,
                    mutedRootIds,
                    mutedRootIds)
        fl.loadMore(25)
        let fetchMoreTask = ReqTask(
            reqCommand: { (taskId) in
                req(RM.getMentions(
                    pubkeys: [pubkey],
                    kinds: [1],
                    limit: 50,
                    subscriptionId: taskId,
                    until: NTimestamp(timestamp: Int(fl.nrPosts.last?.created_at ?? Int64(Date.now.timeIntervalSince1970)))
                ))
            },
            processResponseCommand: { (taskId) in
                fl.predicate = NSPredicate(
                    format: "NOT pubkey IN %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
                            (blockedPubkeys + [pubkey]),
                            serializedP(pubkey),
                            mutedRootIds,
                            mutedRootIds,
                            mutedRootIds)
                fl.loadMore(25)
            })

        backlog.add(fetchMoreTask)
        fetchMoreTask.fetch()
    }
}

struct NotificationsNotes_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9"
        VStack {
            NotificationsPosts(pubkey: pubkey, mutedRootIds: [], blockedPubkeys: [])
        }
        .withPreviewEnvironment()
    }
}

