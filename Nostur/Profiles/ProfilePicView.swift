//
//  ProfilePicView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2023.
//

import SwiftUI
import NukeUI
import Nuke

struct PFP: View, Equatable {
    
    static func == (lhs: PFP, rhs: PFP) -> Bool {
        lhs.pubkey == rhs.pubkey
    }
    
    public var pubkey:String
    
    public var contact:Contact?
    public var nrContact:NRContact?
    public var account:Account?
    public var size:CGFloat? = 50.0

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
    var size:CGFloat? = 50.0
    var color:Color { randomColor(seed: account.publicKey) }
    
    var body: some View {
         InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color)
    }
}

struct InnerPFP: View {
    @EnvironmentObject var theme:Theme
    var pubkey:String
    var pictureUrl:String?
    var size:CGFloat = 50.0
    var color:Color
    var isFollowing = false // will use later to put non following in seperate cache
    @ObservedObject var settings:SettingsStore = .shared
    
    var body: some View {
        if let pictureUrl, pictureUrl.prefix(7) != "http://" {
            if (!settings.animatedPFPenabled) || (pictureUrl.suffix(4) != ".gif") {
                LazyImage(
                    request:
                        ImageRequest(
                            url: URL(string:pictureUrl),
                            processors: [
                                .resize(size: CGSize(width: size, height: size),
                                        unit: .points,
                                        contentMode: .aspectFill,
                                        crop: true,
                                        upscale: true)],
                            userInfo: [.scaleKey: UIScreen.main.scale])
                ) { state in
                    if let image = state.image {
                        if state.imageContainer?.type == .gif {
                            image
                                .interpolation(.none)
                                .resizable() // BUG: Still .gif gets wrong dimensions, so need .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        else {
                            image.interpolation(.none)
                        }
                    }
                    else { color }
                }
                .pipeline(ImageProcessing.shared.pfp)
                .frame(width: size, height: size)
                .cornerRadius(size/2)
                .background(
                    Circle()
                        .strokeBorder(.regularMaterial, lineWidth: 5)
                        .background(Circle().fill(theme.background))
//                        .transaction { t in
//                            t.animation = nil
//                        }
                )
//                .transaction { t in
//                    t.animation = nil
//                }
            }
            else if (pictureUrl.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                LazyImage(url: URL(string: pictureUrl)) { state in
                    if let container = state.imageContainer {
                        if !ProcessInfo.processInfo.isLowPowerModeEnabled, container.type == .gif, let gifData = container.data {
                            ZStack {
                                if let image = state.image {
                                    image
                                        .interpolation(.none)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        
                                }
                                
                                GIFImage(data: gifData, isPlaying: .constant(true))
                                    .resizable()
                                    .scaledToFit()
                            }
                            .frame(width: size, height: size)
                            .cornerRadius(size/2)
                            .background(
                                Circle()
                                    .strokeBorder(.regularMaterial, lineWidth: 5)
                                    .background(Circle().fill(theme.background))
//                                    .transaction { t in
//                                        t.animation = nil
//                                    }
                            )
//                            .transaction { t in
//                                t.animation = nil
//                            }
                        }
                        else if let image = state.image {
                            image
                                .interpolation(.none)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size, height: size)
                                .cornerRadius(size/2)
                                .background(
                                    Circle()
                                        .strokeBorder(.regularMaterial, lineWidth: 5)
                                        .background(Circle().fill(theme.background))
//                                        .transaction { t in
//                                            t.animation = nil
//                                        }
                                )
//                                .transaction { t in
//                                    t.animation = nil
//                                }
                        }
                        else {
                            Circle().foregroundColor(color)
                                .frame(width: size, height: size)
                                .background(
                                    Circle()
                                        .strokeBorder(.black, lineWidth: 5)
                                        .background(Circle().fill(theme.background))
//                                        .transaction { t in
//                                            t.animation = nil
//                                        }
                                )
//                                .transaction { t in
//                                    t.animation = nil
//                                }
                        }
                    }
                    else {
                        Circle().foregroundColor(color)
                            .frame(width: size, height: size)
                            .background(
                                Circle()
                                    .strokeBorder(.regularMaterial, lineWidth: 5)
                                    .background(Circle().fill(theme.background))
//                                    .transaction { t in
//                                        t.animation = nil
//                                    }
                            )
//                            .transaction { t in
//                                t.animation = nil
//                            }
                    }
                }
                .priority(.low) // lower prio for animated gif, saves bandwidth?
                .pipeline(ImageProcessing.shared.pfp) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
//                .transaction { t in
//                    t.animation = nil
//                }
            }
        }
        else {
            Circle().foregroundColor(color)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .strokeBorder(.regularMaterial, lineWidth: 5)
                        .background(Circle().fill(theme.background))
//                        .transaction { t in
//                            t.animation = nil
//                        }
                )
//                .transaction { t in
//                    t.animation = nil
//                }
        }
    }
}

// FOR PREVIEW
struct ProfilePicViewWrapper: View {
    
    // animated gif profile pic
    // 3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24
    
    var body: some View {
        //        EmptyView()
        VStack {
            PFP(pubkey: "gfhfghfgg")
            
            
            if let gladstein = PreviewFetcher.fetchContact("58c741aa630c2da35a56a77c1d05381908bd10504fdd2d8b43f725efa6d23196") {
                PFP(pubkey: gladstein.pubkey, contact: gladstein)
            }
            if let ani = PreviewFetcher.fetchContact("3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24") {
                PFP(pubkey: ani.pubkey, contact: ani)
            }
            
            if let gladstein = PreviewFetcher.fetchNRContact("58c741aa630c2da35a56a77c1d05381908bd10504fdd2d8b43f725efa6d23196") {
                PFP(pubkey: gladstein.pubkey, nrContact: gladstein, size: 150)
            }
            
            HStack {
                if let pfp = PreviewFetcher.fetchNRContact("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e") {
                    PFP(pubkey: pfp.pubkey, nrContact: pfp)
                }
                
                if let pfp = PreviewFetcher.fetchNRContact("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e") {
                    PFP(pubkey: pfp.pubkey, nrContact: pfp, size: 150)
                        .background(.green)
                }
            }
            if let pfp = PreviewFetcher.fetchNRContact("7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194") {
                PFP(pubkey: pfp.pubkey, nrContact: pfp, size: 150)
                    .background(.black)
            }
            if let pfp = PreviewFetcher.fetchNRContact("7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194") {
                PFP(pubkey: pfp.pubkey, nrContact: pfp, size: 150)
                    .background(.white)
            }
            
            HStack {
                PFP(pubkey: "fgfdggf", size: 150)
                    .background(.white)
                
                PFP(pubkey:"hghfghfgh", size: 150)
                    .background(.black)
            }
        }
    }
}

struct ProfilePicView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            ProfilePicViewWrapper()
        }
    }
}



struct MiniPFP: View {
    var pictureUrl:URL
    var size:CGFloat = 20.0
    
    var body: some View {
        LazyImage(
            request:
                ImageRequest(
                    url: pictureUrl,
                    processors: [
                        .resize(size: CGSize(width: size, height: size),
                                unit: .points,
                                contentMode: .aspectFill,
                                crop: true,
                                upscale: true)],
                    userInfo: [.scaleKey: UIScreen.main.scale])
        ) { state in
            if let image = state.image {
                if state.imageContainer?.type == .gif {
                    image
                        .interpolation(.none)
                        .resizable() // BUG: Still .gif gets wrong dimensions, so need .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                else {
                    image.interpolation(.none)
                }
            }
            else { Color.systemBackground }
        }
        .pipeline(ImageProcessing.shared.pfp)
        .frame(width: size, height: size)
        .cornerRadius(size/2)
        .background(
            Circle()
                .strokeBorder(.regularMaterial, lineWidth: 5)
                .background(Circle().fill(Color.systemBackground))
        )
    }
}
