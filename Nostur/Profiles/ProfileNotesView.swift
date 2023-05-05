//
//  TestTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//

import SwiftUI
import CoreData

// Posts on user profile screen
struct ProfileNotesView: View {
    
    let pubkey:String
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var ns:NosturState
    @StateObject var fl = FastLoader()
    @State var backlog = Backlog()
    
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(fl.vPosts) { vPost in
                NoteRow(vPost: vPost)
                    .background(Color.systemBackground)
                    .boxShadow()
                    .padding(.vertical, 10)
                    .padding(.horizontal, settings.fullWidthImages ? 0 : 10)
                    .onTapGesture { navigateTo(vPost) }
                    .id(vPost.id)
            }
            Button("Show more") {
                fl.predicate = NSPredicate(format: "pubkey == %@ AND kind IN {1,6,9802}", pubkey)
//                fl.offset = (fl.vPosts.count - 1)
                fl.loadMore(25)
                if let until = fl.vPosts.last?.created_at {
                    req(RM.getAuthorNotesUntil(pubkey: pubkey, until: NTimestamp(timestamp: Int(until)), limit:250))
                }
                else {
                    req(RM.getAuthorNotes(pubkey: pubkey, limit:250))
                }
            }
            .hCentered()
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
        .background(Color("ListBackground"))
        .onAppear {
            fl.followingKeys = ns.followingPublicKeys
            fl.predicate = NSPredicate(format: "pubkey == %@ AND kind IN {1,6,9802} ", pubkey)
            fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            fl.loadMore(5)
            fl.loadMoreBG(15)
            
            let fetchNewerLimit = 250
            let fetchNewerTask = ReqTask(
                reqCommand: { (taskId) in
                    print("\(taskId) 🟠🟠 fetchNewerTask.fetch()")
                    // Just get max 250 most recent events:
                    req(RM.getAuthorNotes(pubkey: pubkey, limit:fetchNewerLimit, subscriptionId: taskId))
                },
                processResponseCommand: { (taskId) in
                    print("\(taskId) 🟠🟠🟠 processResponseCommand")
                    let currentNewestCreatedAt = fl.vPosts.first?.created_at ?? 0
                    fl.predicate = NSPredicate(
                        format:
                            "created_at >= %i " +
                            "AND pubkey == %@ " + // blockedPubkeys + [pubkey]
                            "AND kind IN {1,6,9802} ",
                            currentNewestCreatedAt,
                            pubkey
                    )
                    fl.loadNewerBG(fetchNewerLimit, taskId:taskId)
                })

            backlog.add(fetchNewerTask)
            fetchNewerTask.fetch()
        }
        .onReceive(receiveNotification(.importedMessagesFromSubscriptionIds)) { notification in
            let importedNotification = notification.object as! ImportedNotification
            let reqTasks = backlog.tasks(with: importedNotification.subscriptionIds)
            reqTasks.forEach { task in
                task.process()
            }
        }
    }
}

struct ProfileNotesView_Previews: PreviewProvider {
    static var previews: some View {
//        let pubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
//        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        
        ScrollView {
            LazyVStack {
                ProfileNotesView(pubkey: pubkey)
            }
        }
        .withPreviewEnvironment()
    }
}
