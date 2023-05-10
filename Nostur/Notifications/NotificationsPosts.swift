//
//  NotificationsPostsNew.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/05/2023.
//

import SwiftUI
import CoreData

@MainActor
struct NotificationsPosts: View {
    
    let pubkey:String
    let mutedRootIds:[String]
    let blockedPubkeys:[String]
     
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var ns:NosturState
    @StateObject var fl = FastLoader()
    @State var backlog = Backlog()
    
    init(pubkey: String, mutedRootIds: [String] = [], blockedPubkeys: [String] = []) {
        self.pubkey = pubkey
        self.mutedRootIds = mutedRootIds
        self.blockedPubkeys = blockedPubkeys
    }
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(fl.vPosts) { vPost in
                    NoteRow(vPost: vPost)
                        .background(Color.systemBackground)
                        .boxShadow()
                        .padding(.vertical, 10)
                        .padding(.horizontal, settings.fullWidthImages ? 0 : 10)
                        .id(vPost.id)
                }
                Button("Show more") {
                    fl.loadMore()
                }
                .padding(.bottom, 40)
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .hCentered()
            }
        }
        .background(Color("ListBackground"))
        .onAppear {
            fl.followingKeys = ns.followingPublicKeys
            fl.predicate = NSPredicate(
                format:
                    "NOT pubkey IN %@ " + // blockedPubkeys + [pubkey]
                    "AND kind == 1 " +
                    "AND tagsSerialized CONTAINS %@ " + // serializedP(pubkey)
                    "AND NOT id IN %@ " + // mutedRootIds
                    "AND (replyToRootId == nil OR NOT replyToRootId IN %@) " + // mutedRootIds
                    "AND (replyToId == nil OR NOT replyToId IN %@) ", // mutedRootIds
                    blockedPubkeys + [pubkey],
                    serializedP(pubkey),
                    mutedRootIds,
                    mutedRootIds,
                    mutedRootIds
              )
            fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            fl.loadMore(5)
            fl.loadMoreBG(15)
            
            if let first = fl.vPosts.first, let account = ns.account {
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
                        since: NTimestamp(timestamp: Int(fl.vPosts.first?.created_at ?? 0))
                    ))
                },
                processResponseCommand: { (taskId) in
//                    print("🟠🟠🟠 processResponseCommand \(taskId)")
                    let currentNewestCreatedAt = fl.vPosts.first?.created_at ?? 0
                    fl.predicate = NSPredicate(
                        format:
                            "created_at >= %i " +
                            "AND NOT pubkey IN %@ " + // blockedPubkeys + [pubkey]
                            "AND kind == 1 " +
                            "AND tagsSerialized CONTAINS %@ " + // serializedP(pubkey)
                            "AND NOT id IN %@ " + // mutedRootIds
                            "AND (replyToRootId == nil OR NOT replyToRootId IN %@) " + // mutedRootIds
                            "AND (replyToId == nil OR NOT replyToId IN %@) ", // mutedRootIds
                            currentNewestCreatedAt,
                            blockedPubkeys + [pubkey],
                            serializedP(pubkey),
                            mutedRootIds,
                            mutedRootIds,
                            mutedRootIds
                      )
                    fl.loadNewerBG(250, taskId: taskId)
                })

            backlog.add(fetchNewerTask)
            fetchNewerTask.fetch()
        }
        .onReceive(receiveNotification(.newMentions)) { _ in
            let currentNewestCreatedAt = fl.vPosts.first?.created_at ?? 0
            fl.predicate = NSPredicate(
                format:
                    "created_at >= %i " +
                    "AND NOT pubkey IN %@ " + // blockedPubkeys + [pubkey]
                    "AND kind == 1 " +
                    "AND tagsSerialized CONTAINS %@ " + // serializedP(pubkey)
                    "AND NOT id IN %@ " + // mutedRootIds
                    "AND (replyToRootId == nil OR NOT replyToRootId IN %@) " + // mutedRootIds
                    "AND (replyToId == nil OR NOT replyToId IN %@) ", // mutedRootIds
                    currentNewestCreatedAt,
                    blockedPubkeys + [pubkey],
                    serializedP(pubkey),
                    mutedRootIds,
                    mutedRootIds,
                    mutedRootIds
            )
            fl.loadNewerBG(250, taskId:"newMentions")
        }
        .onReceive(receiveNotification(.importedMessagesFromSubscriptionIds)) { notification in
            let importedSubIds = notification.object as! ImportedNotification
            
            let reqTasks = backlog.tasks(with: importedSubIds.subscriptionIds)
            
            reqTasks.forEach { task in
                task.process()
            }
        }
    }
}

struct NotificationsNotes_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9"
        NotificationsPosts(pubkey: pubkey, mutedRootIds: [], blockedPubkeys: [])
                .withPreviewEnvironment()
    }
}
