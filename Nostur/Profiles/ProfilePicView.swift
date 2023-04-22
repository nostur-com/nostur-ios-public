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
    var color:Color { randomColor(seed: pubkey) }
    var isFollowing = true // will use later to put non following in seperate cache
    @ObservedObject var settings:SettingsStore = .shared
    
    var body: some View {
        VStack {
            if (pictureUrl == nil || (pictureUrl != nil && pictureUrl!.prefix(7) == "http://")) {
                Circle().foregroundColor(color).frame(width: size, height: size)
            }
            else if (!settings.animatedPFPenabled) {
//                let options = ImageRequest.ThumbnailOptions(size: CGSize(width: size, height: size), unit: .points, contentMode: .aspectFill)
//                LazyImage(request: ImageRequest(url: URL(string:pictureUrl!), userInfo: [.thumbnailKey: options])) { state in
                    LazyImage(request: ImageRequest(url: URL(string:pictureUrl!),
                                                processors: [.resize(size: CGSize(width: size, height: size), unit: .points, contentMode: .aspectFill, crop: true, upscale: true)],
                            userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                    if let image = state.image {
                        image
//                            .resizable()
//                            .scaledToFill()
//                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .background(color)
                            .cornerRadius(.greatestFiniteMagnitude)
//                            .compositingGroup()
                    }
                    else {
                        Circle().foregroundColor(color)//.frame(width: size, height: size)
                            .frame(width: size, height: size)
                    }
                }
//                .processors([.resize(width: size)])
                .pipeline(ImageProcessing.shared.pfp)
                .frame(width: size, height: size)
            }
            else if (pictureUrl!.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                LazyImage(url: URL(string: pictureUrl!)) { state in
                    if let container = state.imageContainer {
                        if container.type == .gif, let gifData = container.data {
                            ZStack {
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: size, height: size)
                                        .cornerRadius(.greatestFiniteMagnitude)
//                                        .compositingGroup()
                                }
                                AnimatedGifView(gifData: gifData, width: size, height: size)
                                    .scaledToFit()
                                    .frame(width: size, height: size)
                                    .cornerRadius(.greatestFiniteMagnitude)
//                                    .clipShape(Circle())
                            }
                        }
                        else if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size, height: size)
                                .cornerRadius(.greatestFiniteMagnitude)
                            //                                .compositingGroup()
                        }
                        else {
                            Circle().foregroundColor(color).frame(width: size, height: size)
                                .frame(width: size, height: size)
                        }
                    }
                    else {
                        Circle().foregroundColor(color).frame(width: size, height: size)
                            .frame(width: size, height: size)
                    }
                }
                .priority(.low) // lower prio for animated gif, saves bandwidth?
                .pipeline(ImageProcessing.shared.pfp) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
             // .frame(width: size, height: size)
            }
            else {
                LazyImage(request: ImageRequest(url: URL(string:pictureUrl!),
                                                processors: [.resize(size: CGSize(width: size, height: size), unit: .points, contentMode: .aspectFill, crop: true, upscale: true)],
                            userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                    if let image = state.image {
                        image
//                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .cornerRadius(.greatestFiniteMagnitude)
                    }
                    else {
                        Circle().foregroundColor(color)//.frame(width: size, height: size)
                            .frame(width: size, height: size)
                    }
                }
//                .processors([.resize(width: size)])
                .pipeline(ImageProcessing.shared.pfp)
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
