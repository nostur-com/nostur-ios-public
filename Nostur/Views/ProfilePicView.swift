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
        
        if (contact?.picture != nil) {
            
            LazyImage(url: URL(string: contact!.picture!)) { state in
                if let image = state.image {
                    image // Displays the loaded image
                }
                else {
                    Circle().foregroundColor(randomColor(seed: pubkey)).frame(maxWidth:50, maxHeight:50)
                }
            }
            
            .processors([ImageProcessors.Resize(width: 50), ImageProcessors.Circle()])
            .animation(nil)
            .priority(.high)
            .pipeline(ImagePipeline {
                $0.dataLoader = DataLoader(configuration: {
                    // Disable disk caching built into URLSession
                    let conf = DataLoader.defaultConfiguration
                    conf.urlCache = nil
                    return conf
                }())

                $0.imageCache = ImageCache()
                $0.dataCache = try! DataCache(name: "com.nostur.2140.picture")
            })
        }
        else {
            Circle().foregroundColor(randomColor(seed: pubkey)).frame(maxWidth:50, maxHeight:50)
        }
    }
}


// FOR PREVIEW
struct ProfilePicViewWrapper: View {
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(format: "pubkey == %@", "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"),
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    var body: some View {
        ProfilePicView(pubkey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", contact: contacts.first)
            .frame(width: 100, height: 100)
    }
}

struct ProfilePicView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicViewWrapper()
            .environment(\.managedObjectContext,
                          PersistenceController.preview.container.viewContext)
    }
}
