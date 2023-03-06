//
//  ProfilePicView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2023.
//

import SwiftUI
import NukeUI
import Nuke

struct ProfilePic: View {
    
    @ObservedObject var event:Event
    var size:CGFloat = 50
    var color:Color
    
    init(event:Event, size: CGFloat = 50) {
        self.event = event
        self.size = size
        self.color = randomColor(seed: event.pubkey)
    }
    
    var body: some View {
        let picture = event.contact?.picture
        
        if (picture == nil || (picture != nil && picture!.prefix(7) == "http://")) { // TODO: is this slow??
            Circle().foregroundColor(color).frame(width: size, height: size)
        }
        else {
            LazyImage(url: URL(string: picture!)) { state in
                if let image = state.image {
                    image.frame(width: size, height: size).clipShape(Circle())
                }
                else {
                    Circle().foregroundColor(color).frame(width: size, height: size)
                }
            }
            .processors([ImageProcessors.Resize(width: 100), ImageProcessors.Circle()])
//            .processors([ImageProcessors.Resize(size: CGSize(width: 50, height: 150), unit: .pixels, contentMode: .aspectFit, crop: true, upscale: true)])
            .animation(nil)
            .priority(.low)
            .pipeline(ImageProcessing.shared.pipeline)
//                .pipeline(ImagePipeline {
//                    $0.dataLoader = DataLoader(configuration: {
//                        // Disable disk caching built into URLSession
//                        let conf = DataLoader.defaultConfiguration
//                        conf.urlCache = nil
//                        return conf
//                    }())
//
//                    $0.dataCachePolicy = .storeEncodedImages
//                    $0.imageCache = ImageCache.shared
//                    $0.dataCache = try! DataCache(name: "com.nostur.2140.picture")
//                })
        }
    }
}

struct ProfilePicView: View {
    
    var pubkey:String
    var contact:Contact?
    var account:Account?
    var size:CGFloat = 50
    var color:Color
    
    init(pubkey: String, contact: Contact? = nil, account: Account? = nil, size: CGFloat = 50) {
        self.pubkey = pubkey
        self.contact = contact
        self.account = account
        self.size = size
        self.color = randomColor(seed: pubkey)
    }
    
    var body: some View {
        let picture = contact != nil ? contact!.picture : account?.picture
        
        if (picture == nil || (picture != nil && picture!.prefix(7) == "http://")) { // TODO: is this slow??
            Circle().foregroundColor(color).frame(width: size, height: size)
        }
        else {
            LazyImage(url: URL(string: picture!)) { state in
                if let image = state.image {
                    image.frame(width: size, height: size).clipShape(Circle())
                }
                else {
                    Circle().foregroundColor(color).frame(width: size, height: size)
                }
            }
            .processors([ImageProcessors.Resize(width: 100), ImageProcessors.Circle()])
//            .processors([ImageProcessors.Resize(size: CGSize(width: 50, height: 150), unit: .pixels, contentMode: .aspectFit, crop: true, upscale: true)])
            .animation(nil)
            .priority(.low)
            .pipeline(ImageProcessing.shared.pipeline)
//                .pipeline(ImagePipeline {
//                    $0.dataLoader = DataLoader(configuration: {
//                        // Disable disk caching built into URLSession
//                        let conf = DataLoader.defaultConfiguration
//                        conf.urlCache = nil
//                        return conf
//                    }())
//
//                    $0.dataCachePolicy = .storeEncodedImages
//                    $0.imageCache = ImageCache.shared
//                    $0.dataCache = try! DataCache(name: "com.nostur.2140.picture")
//                })
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
        ProfilePicView(pubkey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", contact: contacts.first)
            .frame(width: 150, height: 150)
    }
}

struct ProfilePicView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicViewWrapper()
            .withPreviewEnvironment()
    }
}
