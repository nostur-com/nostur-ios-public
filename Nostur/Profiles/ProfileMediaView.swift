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
    
    let sp:SocketPool = .shared
    let pubkey:String
    @State var limit = 150
    @State var imageUrls:[URL] = []
    @State var offset = 0
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var squareSize:CGFloat { CGFloat(Int((dim.listWidth-26)/3)) }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
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
                    .pipeline(ImageProcessing.shared.content) // No processing again here, we probably never show the
//                    .id(imageUrls[index].absoluteString)
                }
            }
            .padding(10)
        }
//        .background(Color.systemBackground)
        .onAppear {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "pubkey == %@ AND kind == 1", pubkey)
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            fr.fetchBatchSize = 250
            fr.fetchOffset = offset
            
            if let posts = try? viewContext.fetch(fr) {
                imageUrls = posts.flatMap { getImgUrlsFromContent($0.content!) }
            }
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorKind1(pubkey: pubkey, limit:250)))
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
