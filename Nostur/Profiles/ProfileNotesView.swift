//
//  ProfileNotesView.swift
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
    @State var didLoad = false
    @State var backlog = Backlog()
    
    var body: some View {
        LazyVStack {
            ForEach(fl.nrPosts) { nrPost in
                PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages)
                    .roundedBoxShadow()
                    .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                    .id(nrPost.id)
            }
            if !fl.nrPosts.isEmpty {
                Button(String(localized:"Show more", comment: "Button to show more items")) {
                    fl.predicate = NSPredicate(format: "pubkey == %@ AND kind IN {1,6,9802,30023}", pubkey)
                    fl.loadMore(50, includeSpam: true)
                    if let until = fl.nrPosts.last?.created_at {
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
            else {
                CenteredProgressView()
            }
            Spacer()
                .frame(minHeight: 800)
        }
        .padding(.top, 5)
        .background(Color("ListBackground"))
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            fl.predicate = NSPredicate(format: "pubkey == %@ AND kind IN {1,6,9802,30023} ", pubkey)
            fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            fl.loadMore(50, includeSpam: true)
            
            let fetchNewerLimit = 1000
            let fetchNewerTask = ReqTask(
                reqCommand: { (taskId) in
                    L.og.debug("\(taskId) 🟠🟠 fetchNewerTask.fetch()")
                    // Just get max 250 most recent events:
                    req(RM.getAuthorNotes(pubkey: pubkey, limit:fetchNewerLimit, subscriptionId: taskId))
                },
                processResponseCommand: { (taskId, _) in
                    L.og.debug("\(taskId) 🟠🟠🟠 processResponseCommand")
                    let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
                    fl.predicate = NSPredicate(
                        format:
                            "created_at >= %i " +
                            "AND pubkey == %@ " + // blockedPubkeys + [pubkey]
                            "AND kind IN {1,6,9802,30023} ",
                            currentNewestCreatedAt,
                            pubkey
                    )
                    fl.loadNewer(fetchNewerLimit, taskId:taskId, includeSpam: true)
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
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
//        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
//        let pubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            ScrollView {
                LazyVStack {
                    ProfileNotesView(pubkey: pubkey)
                }
            }
        }
    }
}
