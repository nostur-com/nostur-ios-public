//
//  ProfilePicView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2023.
//

import SwiftUI
import NukeUI
import Nuke

struct ProfilePicView : View {
    
    var pubkey:String
    var contact:Contact?
    
    var body: some View {
        
        if (contact?.picture != nil) { // TODO: is this slow??
            
            if (contact!.picture!.prefix(7) == "http://") {
                Circle().foregroundColor(randomColor(seed: pubkey)).frame(width: 50, height: 50)
            }
            else {
                LazyImage(url: URL(string: contact!.picture!)) { state in
                    if let image = state.image {
                        image.frame(width: 50, height: 50).clipShape(Circle())
                    }
                    else {
                        Circle().foregroundColor(randomColor(seed: pubkey)).frame(width: 50, height: 50)
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
        else {
            Circle().foregroundColor(randomColor(seed: pubkey)).frame(width: 50, height: 50)
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
