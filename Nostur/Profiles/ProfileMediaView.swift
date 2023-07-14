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
    @StateObject var fl = FastLoader()
    @State var didLoad = false
    @State var backlog = Backlog()
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var squareSize:CGFloat { CGFloat(Int((dim.listWidth-42)/3)) }
    
    @State var imageUrls:[URL] = []
    
    var body: some View {
        VStack {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(imageUrls.indices, id: \.self) { index in
                    MediaThumb(imageUrls[index], size: squareSize)
                }
                Spacer()
            }
            .padding(10)
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                fl.nrPostTransform = false
                fl.predicate = NSPredicate(format: "pubkey == %@ AND kind == 1", pubkey)
                fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
                fl.loadMore(1000, includeSpam: true)
            }
            .onChange(of: fl.events) { events in
                // Process fl.events to imageUrls:[URL] here, fixes microhang
                let contentArray = events.compactMap { $0.content }
                DispatchQueue.global(qos: .userInitiated).async {
                    let urls = contentArray.flatMap { getImgUrlsFromContent($0) }
                    DispatchQueue.main.async {
                        self.imageUrls = urls
                    }
                }
            }
        }
        .frame(minHeight: 800)
    }
}

struct MediaThumb: View {
    
    let url:URL
    let squareSize:CGFloat
    @State var priority:ImageRequest.Priority = .normal
    
    init(_ url:URL, size:CGFloat) {
        self.url = url
        self.squareSize = size
    }
    
    var body: some View {
        LazyImage(request:
                    ImageRequest(url: url,
                                 processors: [.resize(width: squareSize, upscale: true)],
                                 userInfo: [.scaleKey: UIScreen.main.scale])) { state in
            if state.error != nil {
                Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                    .centered()
                    .frame(width:squareSize, height:squareSize)
                    .background(Color("LightGray").opacity(0.2))
                    .onAppear {
                        print("Failed to load image: \(state.error?.localizedDescription ?? "")")
                    }
            }
            else if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                GIFImage(data: data)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width:squareSize, height:squareSize)
                    .clipped()
                    .onTapGesture {
                        sendNotification(.fullScreenView, FullScreenItem(url: url))
                    }
            }
            else if let image = state.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width:squareSize, height:squareSize)
                    .background(Color("LightGray").opacity(0.2))
                    .clipped()
                    .contentShape(Path(CGRect(x: 0, y: 0, width: squareSize, height: squareSize)))
                    .onTapGesture {
                        sendNotification(.fullScreenView, FullScreenItem(url: url))
                    }
            }
            else if state.isLoading { // does this conflict with showing preview images??
                HStack(spacing: 5) {
                    ImageProgressView(progress: state.progress)
                        .onTapGesture {
                            priority = .veryHigh
                        }
                }
                .centered()
                .frame(width:squareSize, height:squareSize)
                .background(Color("LightGray"))
            }
            else {
                Color("LightGray").opacity(0.2)
            }
        }
        .pipeline(ImageProcessing.shared.content)
        .priority(priority)
        .onDisappear {
            priority = .low
        }
        .onAppear {
            priority = .normal
        }
    }
}


struct ProfileMediaView_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadMedia()
        }) {
            NavigationStack {
                ProfileMediaView(pubkey: pubkey)
            }
        }
    }
}
