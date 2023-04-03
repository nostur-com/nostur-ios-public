//
//  ProfilePicView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2023.
//

import SwiftUI
import NukeUI
import Nuke
//import AnimatedImage

struct PFP: View {
    
    var pubkey:String
    var pictureUrl:String?
    var size:CGFloat = 50
    var color:Color
    
    init(pubkey:String, pictureUrl:String? = nil, size: CGFloat = 50) {
        self.pubkey = pubkey
        self.pictureUrl = pictureUrl
        self.size = size
        self.color = randomColor(seed: pubkey)
    }
    
    var body: some View {
        if (pictureUrl == nil || (pictureUrl != nil && pictureUrl!.prefix(7) == "http://")) { // TODO: is this slow??
            Circle().foregroundColor(color).frame(width: size, height: size)
        }
        else {

                if (pictureUrl!.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                    LazyImage(url: URL(string: pictureUrl!)) { state in
                        if let container = state.imageContainer {
                            if container.type == .gif, let gifData = container.data {
                                ZStack {
                                    if let image = state.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: size, height: size)
                                            .clipShape(Circle())
                                    }
                                    AnimatedGifView(gifData: gifData, width: size, height: size)
                                        .scaledToFit()
                                        .frame(width: size, height: size)
                                        .clipShape(Circle())
                                }
                            }
                            else if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size, height: size)
                                    .clipShape(Circle())
                            }
                            else {
                                Circle().foregroundColor(color).frame(width: size, height: size)
                            }
                        }
                        else {
                            Circle().foregroundColor(color).frame(width: size, height: size)
                        }
                    }
                    .pipeline(ImageProcessing.shared.pfp) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                    .priority(.low) // lower prio for animated gif, saves bandwidth?
                    .frame(width: size, height: size)
                }
                else {
                    LazyImage(url: URL(string: pictureUrl!)) { state in
                        if let image = state.image {
                            image
                                .resizable()
//                                .aspectRatio(contentMode: .fill)
//                                .frame(width: size, height: size)
//                                .clipShape(Circle())
                        }
                        else {
                            Circle().foregroundColor(color)//.frame(width: size, height: size)
                        }
                    }
                    .pipeline(ImageProcessing.shared.pfp)
                    .processors([.resize(width: size, unit: .points), .circle()])
//                    .processors([.resize(width: size, unit: .pixels), .circle()])
//                    .priority(.low)
                    .frame(width: size, height: size)
                }
            
        }
    }
}


// FOR PREVIEW
struct ProfilePicViewWrapper: View {
    
    // animated gif profile pic
    // 3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24
    
    // me
    // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(format: "pubkey == %@", "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"),
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    var body: some View {
        //        EmptyView()
        VStack {
            PFP(pubkey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", pictureUrl: contacts.first?.picture, size: 150)
                .frame(width: 150, height: 150)
                .background(.green)
            
            PFP(pubkey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", pictureUrl: contacts.first?.picture)
                .frame(width: 50, height: 50)
                .background(.red)
        }
    }
}

struct ProfilePicView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicViewWrapper()
            .withPreviewEnvironment()
    }
}
