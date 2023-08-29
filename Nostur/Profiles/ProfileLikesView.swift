//
//  ProfileLikesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import CoreData

struct ProfileLikesView: View {
    @EnvironmentObject var theme:Theme
    let pubkey:String
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var ns:NosturState
    @StateObject var fl = FastLoader()
    @State var didLoad = false
    @State var backlog = Backlog()
    
    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(fl.nrPosts) { nrPost in
                Box(nrPost: nrPost) {
                    PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages)
                }
                .id(nrPost.id)
                .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !fl.nrPosts.isEmpty {
                Button(String(localized:"Show more", comment: "Button to show more items")) {
                    fl.predicate = NSPredicate(format: "pubkey == %@ AND kind == 7", pubkey)
                    fl.loadMore(50, includeSpam: true)
                    if let until = fl.nrPosts.last?.created_at {
                        req(RM.getAuthorReactions(pubkey: pubkey, limit:250, until: NTimestamp(timestamp: Int(until))))
                    }
                    else {
                        req(RM.getAuthorReactions(pubkey: pubkey, limit:250))
                    }
                }
                    .hCentered()
                    .buttonStyle(.bordered)
//                    .tint(.accentColor)
                
            }
            else {
                CenteredProgressView()
            }
            Spacer()
                .frame(minHeight: 800)
        }
        .padding(.top, 5)
        .background(theme.listBackground)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            fl.transformer = { event in
                if let reactionTo = event.reactionTo_ {
                    return NRPost(event: reactionTo)
                }
                return nil
            }
            fl.predicate = NSPredicate(format: "pubkey == %@ AND kind == 7", pubkey)
            fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            fl.loadMore(50, includeSpam: true)
            
            let fetchNewerLimit = 1000
            let fetchNewerTask = ReqTask(
                reqCommand: { (taskId) in
                    print("\(taskId) 🟠🟠 fetchNewerTask.fetch()")
                    // Just get max 250 most recent events:
                    req(RM.getAuthorReactions(pubkey: pubkey, limit:fetchNewerLimit, subscriptionId: taskId))
                },
                processResponseCommand: { (taskId, _) in
                    L.og.debug("\(taskId) 🟠🟠🟠 processResponseCommand")
                    let currentNewestCreatedAt = fl.nrPosts.first?.created_at ?? 0
                    fl.predicate = NSPredicate(
                        format:
                            "created_at >= %i " +
                            "AND pubkey == %@ " + // blockedPubkeys + [pubkey]
                            "AND kind == 7 ",
                            currentNewestCreatedAt,
                            pubkey
                    )
                    fl.loadNewer(fetchNewerLimit, taskId:taskId, includeSpam:true)
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

struct ProfileLikesView_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadRepliesAndReactions()
        }) {
            ScrollView {
                ProfileLikesView(pubkey: pubkey)
            }
        }
    }
}
