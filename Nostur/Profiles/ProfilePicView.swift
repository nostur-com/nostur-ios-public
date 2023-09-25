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
    
    @ObservedObject public var contact:Contact
    private var pubkey:String { contact.pubkey }
    private var pictureUrl:String? { contact.picture }
    var size:CGFloat?
    private var color:Color { randomColor(seed: contact.pubkey) }
    
    var body: some View {
         InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color)
    }
}

struct NRContactPFP: View {
    
    @ObservedObject public var nrContact:NRContact
    private var pubkey:String { nrContact.pubkey }
    private var pictureUrl:String? { nrContact.pictureUrl }
    public var size:CGFloat?
    private var color:Color { randomColor(seed: nrContact.pubkey) }
    
    var body: some View {
        InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color)
    }
}

struct AccountPFP: View {
    
    @ObservedObject public var account:Account
    private var pubkey:String { account.publicKey }
    private var pictureUrl:String? { account.picture }
    public var size:CGFloat? = 50.0
    private var color:Color { randomColor(seed: account.publicKey) }
    
    var body: some View {
         InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color)
    }
}

struct InnerPFP: View {
    @EnvironmentObject private var theme:Theme
    public var pubkey:String
    public var pictureUrl:String?
    public var size:CGFloat = 50.0
    public var color:Color
    public var isFollowing = false // will use later to put non following in seperate cache
    @ObservedObject private var settings:SettingsStore = .shared
    
    // Always render default circle (color is pubkey derived)
    // If not https don't render
    // If animated PFP disabled or image is not .gif, render flat
    // else render animated gif
    
    private enum RenderOption {
        case noUrl
        case noHttps
        case flat(String)
        case animatedGif(String)
    }
    
    private var renderCase: RenderOption {
        guard let pictureUrl else { return .noUrl }
        guard pictureUrl.prefix(8) == "https://" else { return .noHttps }
        guard (pictureUrl.suffix(4) == ".gif") && settings.animatedPFPenabled else { return .flat(pictureUrl) }
        return .animatedGif(pictureUrl)
    }
    
    var body: some View {
        Circle()
            .strokeBorder(.regularMaterial, lineWidth: 5)
            .background(color)
            .frame(width: size, height: size)
            .cornerRadius(size/2)
            
            .overlay {
                switch renderCase {
                    
                case .noUrl, .noHttps:
                    EmptyView()
                    
                case .flat(let url):
                    LazyImage(request: pfpImageRequestFor(url, size: size)) { state in
                        if let image = state.image {
                            if state.imageContainer?.type == .gif {
                                image
                                    .interpolation(.none)
                                    .resizable() // BUG: Still .gif gets wrong dimensions, so need .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size, height: size)
                                    .cornerRadius(size/2)
                                    .withoutAnimation()
                            }
                            else {
                                image.interpolation(.none)
                                    .frame(width: size, height: size)
                                    .cornerRadius(size/2)
                                    .withoutAnimation()
                            }
                        }
                        else { color }
                    }
                    .pipeline(ImageProcessing.shared.pfp)
//                    .cornerRadius(size/2)
                    
                case .animatedGif(let url):
                    LazyImage(request: pfpImageRequestFor(url, size: size)) { state in
                        if let container = state.imageContainer {
                            if !ProcessInfo.processInfo.isLowPowerModeEnabled, container.type == .gif, let gifData = container.data {
                                ZStack {
                                    if let image = state.image {
                                        image
                                            .interpolation(.none)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .withoutAnimation()
                                    }
        
                                    GIFImage(data: gifData, isPlaying: .constant(true))
                                        .resizable()
                                        .scaledToFit()
                                        .withoutAnimation()
                                }
                                .frame(width: size, height: size)
                                .cornerRadius(size/2)
                            }
                            else if let image = state.image {
                                image
                                    .interpolation(.none)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size, height: size)
                                    .cornerRadius(size/2)
                                    .withoutAnimation()
                            }

                        }
                    }
                    .priority(.low) // lower prio for animated gif, saves bandwidth?
                    .pipeline(ImageProcessing.shared.pfp) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                }
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
            
            
            if let any = PreviewFetcher.fetchContact() {
                PFP(pubkey: any.pubkey, contact: any)
            }
            if let any = PreviewFetcher.fetchContact() {
                PFP(pubkey: any.pubkey, contact: any)
            }

            if let any = PreviewFetcher.fetchNRContact() {
                PFP(pubkey: any.pubkey, nrContact: any, size: 150)
            }
            
            HStack {
                if let pfp = PreviewFetcher.fetchNRContact() {
                    PFP(pubkey: pfp.pubkey, nrContact: pfp)
                }
                
                if let pfp = PreviewFetcher.fetchNRContact() {
                    PFP(pubkey: pfp.pubkey, nrContact: pfp, size: 150)
                        .background(.green)
                }
            }
            if let pfp = PreviewFetcher.fetchNRContact() {
                PFP(pubkey: pfp.pubkey, nrContact: pfp, size: 150)
                    .background(.black)
            }
            if let pfp = PreviewFetcher.fetchNRContact() {
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
    public var pictureUrl:URL
    public var size:CGFloat = 20.0
    private var pictureUrlString:String { pictureUrl.absoluteString }
    
    var body: some View {
        LazyImage(request: pfpImageRequestFor(pictureUrlString, size: size)) { state in
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
