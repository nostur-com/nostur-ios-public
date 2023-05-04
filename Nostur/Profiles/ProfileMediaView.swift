//
//  ProfileMediaView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI
import CoreData
import Nuke
import NukeUI

// MEDIA ON USER PROFILE SCREEN
struct ProfileMediaView: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var dim:DIMENSIONS
    let pubkey:String
//    @State var imageUrls:[URL] = []
    @StateObject var fl = FastLoader()
    @State var backlog = Backlog()
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var squareSize:CGFloat { CGFloat(Int((dim.listWidth-26)/3)) }
    
    var imageUrls:[URL] {
        fl.events.flatMap { getImgUrlsFromContent($0.content!) }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(imageUrls.indices, id: \.self) { index in
                    // Lazy image here
                    LazyImage(request:
                                ImageRequest(url: imageUrls[index],
                                             processors: [.resize(width: squareSize, upscale: true)],
                                             userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width:squareSize, height:squareSize)
                                .clipped()
                                .contentShape(Path(CGRect(x: 0, y: 0, width: squareSize, height: squareSize)))
                                .onTapGesture {
                                    sendNotification(.fullScreenView, FullScreenItem(url: imageUrls[index]))
                                }
                        }
                        else if state.error != nil {
                            Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                                .centered()
                                .frame(width:squareSize, height:squareSize)
                                .background(Color("LightGray"))
                        }
                        else {
                            CenteredProgressView()
                                .frame(width:squareSize, height:squareSize)
                                .background(Color("LightGray"))
                        }
                        
                    }
                    .pipeline(ImageProcessing.shared.content)
                }
            }
            .padding(10)
        }
        .onAppear {
            fl.vPostTransform = false
            fl.predicate = NSPredicate(format: "pubkey == %@ AND kind == 1", pubkey)
            fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            fl.loadMore(1000)
            
            // if there is nothing on screen, fetch most recent 1000
            let fetchNewerLimit = 1000
            let fetchNewerTask = ReqTask(
                reqCommand: { (taskId) in
                    print("\(taskId) 🟠🟠 fetchNewerTask.fetch()")
                    req(RM.getAuthorKind1(pubkey: pubkey, limit:fetchNewerLimit, subscriptionId: taskId))
                },
                processResponseCommand: { (taskId) in
                    print("\(taskId) 🟠🟠🟠 processResponseCommand")
                    let currentNewestCreatedAt = fl.vPosts.first?.created_at ?? 0
                    fl.predicate = NSPredicate(
                        format:
                            "created_at >= %i " +
                            "AND pubkey == %@ " + // blockedPubkeys + [pubkey]
                            "AND kind == 1",
                            currentNewestCreatedAt,
                            pubkey
                    )
                    fl.loadNewerEvents(fetchNewerLimit, taskId:taskId)
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


struct ProfileMediaView_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"
        
        NavigationStack {
            ProfileMediaView(pubkey: pubkey)
        }
        .withPreviewEnvironment()
    }
}
