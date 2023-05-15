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
    
    var contact:Contact?
    var nrContact:NRContact?
    var account:Account?
    var size:CGFloat? = 50

    var body: some View {
        if let contact {
            ContactPFP(contact: contact, size: size)
        }
        else if let nrContact {
            NRContactPFP(nrContact: nrContact, size: size)
        }
        else if let account {
            AccountPFP(account: account, size: size)
        }
        else {
            InnerPFP(pubkey: pubkey, size: size!, color: randomColor(seed: pubkey))
        }
    }
}

struct ContactPFP: View {
    
    @ObservedObject var contact:Contact
    var pubkey:String { contact.pubkey }
    var pictureUrl:String? { contact.picture }
    var size:CGFloat?
    var color:Color { randomColor(seed: contact.pubkey) }
    
    var body: some View {
         InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color)
    }
}

struct NRContactPFP: View {
    
    @ObservedObject var nrContact:NRContact
    var pubkey:String { nrContact.pubkey }
    var pictureUrl:String? { nrContact.pictureUrl }
    var size:CGFloat?
    var color:Color { randomColor(seed: nrContact.pubkey) }
    
    var body: some View {
        InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color)
    }
}

struct AccountPFP: View {
    
    @ObservedObject var account:Account
    var pubkey:String { account.publicKey }
    var pictureUrl:String? { account.picture }
    var size:CGFloat? = 50
    var color:Color { randomColor(seed: account.publicKey) }
    
    var body: some View {
         InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color)
    }
}

struct InnerPFP: View {
    
    var pubkey:String
    var pictureUrl:String?
    var size:CGFloat = 50
    var color:Color
    var isFollowing = false // will use later to put non following in seperate cache
    let settings:SettingsStore = .shared
    
    var body: some View {
        if let pictureUrl, pictureUrl.prefix(7) != "http://" {
            if (!settings.animatedPFPenabled) || (pictureUrl.suffix(4) != ".gif") {
                LazyImage(request: ImageRequest(url: URL(string:pictureUrl), processors: [.resize(size: CGSize(width: size, height: size), unit: .points, contentMode: .aspectFill, crop: true, upscale: true)], userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                    if let image = state.image {
                        if pictureUrl.suffix(4) == ".gif" {
                            image
                                .resizable() // BUG: Still .gif gets wrong dimensions, so need .resizable()
                        }
                        else {
                            image
                        }
                    }
                    else {
                        color
                    }
                }
                .pipeline(isFollowing ? ImageProcessing.shared.pfp : ImageProcessing.shared.pfpNotFollowing)
                .frame(width: size, height: size)
                .background(color)
                .cornerRadius(.greatestFiniteMagnitude)
            }
            else if (pictureUrl.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                LazyImage(url: URL(string: pictureUrl)) { state in
                    if let container = state.imageContainer {
                        if container.type == .gif, let gifData = container.data {
                            ZStack {
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: size, height: size)
                                        .cornerRadius(.greatestFiniteMagnitude)
                                }
                                
                                GIFImage(data: gifData)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: size, height: size)
                                    .cornerRadius(.greatestFiniteMagnitude)
                            }
                        }
                        else if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size, height: size)
                                .cornerRadius(.greatestFiniteMagnitude)
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
                .pipeline(isFollowing ? ImageProcessing.shared.pfp : ImageProcessing.shared.pfpNotFollowing) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
            }
        }
        else {
            Circle().foregroundColor(color)
                .frame(width: size, height: size)
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
            PFP(pubkey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", contact: contacts.first, size: 150)
                .frame(width: 150, height: 150)
                .background(.green)
            
            PFP(pubkey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", contact: contacts.first)
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
