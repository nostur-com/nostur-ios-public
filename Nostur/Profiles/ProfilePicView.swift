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
    
    public var pubkey: String
    
    public var contact: Contact?
    public var nrContact: NRContact?
    public var account: CloudAccount?
    public var size: CGFloat? = 50.0
    public var forceFlat = false

    var body: some View {
        if let contact {
            ContactPFP(contact: contact, size: size, forceFlat: forceFlat)
        }
        else if let nrContact {
            NRContactPFP(nrContact: nrContact, size: size, forceFlat: forceFlat)
        }
        else if let account {
            AccountPFP(account: account, size: size, forceFlat: forceFlat)
        }
        else {
            InnerPFP(pubkey: pubkey, size: size!, color: randomColor(seed: pubkey), forceFlat: forceFlat)
        }
    }
}

struct ContactPFP: View {
    
    @ObservedObject public var contact: Contact
    private var pubkey:String { contact.pubkey }
    private var pictureUrl:URL? { contact.pictureUrl }
    var size:CGFloat?
    public var forceFlat = false
    private var color:Color { randomColor(seed: contact.pubkey) }
    
    var body: some View {
         InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color, forceFlat: forceFlat)
    }
}

struct NRContactPFP: View {
    
    @ObservedObject public var nrContact: NRContact
    private var pubkey:String { nrContact.pubkey }
    private var pictureUrl:URL? { nrContact.pictureUrl }
    public var size:CGFloat?
    public var forceFlat = false
    private var color: Color { nrContact.randomColor }
    
    var body: some View {
        InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color, forceFlat: forceFlat)
    }
}

struct AccountPFP: View {
    
    @ObservedObject public var account: CloudAccount
    private var pubkey: String { account.publicKey }
    private var pictureUrl: URL? { account.pictureUrl }
    public var size: CGFloat? = 50.0
    public var forceFlat = false
    private var color: Color { randomColor(seed: account.publicKey) }
    
    var body: some View {
         InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size!, color: color, forceFlat: forceFlat)
    }
}

struct InnerPFP: View {
    @EnvironmentObject private var themes: Themes
    public var pubkey: String
    public var pictureUrl: URL?
    public var size: CGFloat = 50.0
    public var color: Color? = nil
    public var forceFlat = false
    private var innerColor: Color {
        color ?? randomColor(seed: pubkey)
    }

    @ObservedObject private var settings: SettingsStore = .shared
    @State private var updatedPictureUrl: URL?
    
    // Always render default circle (color is pubkey derived)
    // If not https don't render
    // If animated PFP disabled or image is not .gif, render flat
    // else render animated gif
    
    private enum RenderOption {
        case noUrl
        case noHttps
        case flat(URL)
        case animatedGif(URL)
    }
    
    private var renderCase: RenderOption {
        guard let pictureUrl = updatedPictureUrl ?? pictureUrl else { return .noUrl }
        guard pictureUrl.absoluteString.prefix(8) == "https://" else { return .noHttps }
        if forceFlat { return .flat(pictureUrl) }
        guard (pictureUrl.absoluteString.suffix(4) == ".gif") && settings.animatedPFPenabled else { return .flat(pictureUrl) }
        return .animatedGif(pictureUrl)
    }
    
    var body: some View {
        Circle()
            .strokeBorder(.regularMaterial, lineWidth: 2)
            .background(innerColor)
            .frame(width: size, height: size)
            .overlay {
                switch renderCase {
                    
                case .noUrl, .noHttps:
                    EmptyView()
                        .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
                            guard profile.pubkey == pubkey, let pictureUrl = profile.pictureUrl else { return }
                            updatedPictureUrl = pictureUrl
                        }
                    
                case .flat(let url):
                    LazyImage(request: pfpImageRequestFor(url, size: size)) { state in
                        if let image = state.image {
                            if state.imageContainer?.type == .gif {
                                image
                                    .interpolation(.none)
                                    .resizable() // BUG: Still .gif gets wrong dimensions, so need .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size, height: size)
//                                    .withoutAnimation()
                            }
                            else {
                                image.interpolation(.none)
                                    .frame(width: size, height: size)
//                                    .withoutAnimation()
                            }
                        }
                        else { color }
                    }
                    .pipeline(ImageProcessing.shared.pfp)
                    .drawingGroup()
                    .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
                        guard profile.pubkey == pubkey, let pictureUrl = profile.pictureUrl else { return }
                        updatedPictureUrl = pictureUrl
                    }
                    
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
//                                            .withoutAnimation()
                                    }
        
                                    GIFImage(data: gifData, isPlaying: .constant(true))
//                                        .scaledToFit()
//                                        .withoutAnimation()
                                }
                                .frame(width: size, height: size)
//                                .cornerRadius(size/2)
                            }
                            else if let image = state.image {
                                image
                                    .interpolation(.none)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size, height: size)
//                                    .cornerRadius(size/2)
//                                    .withoutAnimation()
                            }

                        }
                    }
                    .priority(.low) // lower prio for animated gif, saves bandwidth?
                    .pipeline(ImageProcessing.shared.pfp) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                    .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
                        guard profile.pubkey == pubkey, let pictureUrl = profile.pictureUrl else { return }
                        updatedPictureUrl = pictureUrl
                    }
                }
            }
            .cornerRadius(size/2)
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
    
    var body: some View {
        LazyImage(request: pfpImageRequestFor(pictureUrl, size: size)) { state in
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
