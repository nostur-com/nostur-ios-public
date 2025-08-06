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
        lhs.pubkey == rhs.pubkey &&
        lhs.pictureUrl == rhs.pictureUrl &&
        lhs.contact == rhs.contact &&
        lhs.nrContact == rhs.nrContact &&
        lhs.account == rhs.account
    }
    
    public var pubkey: String
    public var pictureUrl: URL?
    public var contact: Contact?
    public var nrContact: NRContact?
    public var account: CloudAccount?
    public var size: CGFloat = 50.0
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
            InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size, color: randomColor(seed: pubkey), forceFlat: forceFlat)
        }
    }
}

struct ObservedPFP: View {
    
    @ObservedObject private var nrContact: NRContact
    private var pubkey: String { nrContact.pubkey }
    private var pictureUrl: URL? { nrContact.pictureUrl }
    private var size: CGFloat = 50.0
    private var forceFlat = false
    private var color: Color { nrContact.randomColor }
    
    init(nrContact: NRContact, size: CGFloat = 50.0, forceFlat: Bool = false) {
        self.nrContact = nrContact
        self.size = size
        self.forceFlat = forceFlat
    }
    
    init(pubkey: String, size: CGFloat = 50.0, forceFlat: Bool = false) {
        self.nrContact = NRContact.instance(of: pubkey)
        self.size = size
        self.forceFlat = forceFlat
    }
    
    var body: some View {
        InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size, color: color, forceFlat: forceFlat)
    }
}

struct ContactPFP: View {
    
    @ObservedObject public var contact: Contact
    private var pubkey: String { contact.pubkey }
    private var pictureUrl: URL? { contact.pictureUrl }
    public var size: CGFloat = 50.0
    public var forceFlat = false
    private var color: Color { randomColor(seed: contact.pubkey) }
    
    var body: some View {
         InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size, color: color, forceFlat: forceFlat)
    }
}

struct NRContactPFP: View {
    
    @ObservedObject public var nrContact: NRContact
    private var pubkey:String { nrContact.pubkey }
    private var pictureUrl:URL? { nrContact.pictureUrl }
    public var size: CGFloat = 50.0
    public var forceFlat = false
    private var color: Color { nrContact.randomColor }
    
    var body: some View {
        InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size, color: color, forceFlat: forceFlat)
    }
}

struct AccountPFP: View {
    
    @ObservedObject public var account: CloudAccount
    private var pubkey: String { account.publicKey }
    private var pictureUrl: URL? { account.pictureUrl }
    public var size: CGFloat = 50.0
    public var forceFlat = false
    private var color: Color { randomColor(seed: account.publicKey) }
    
    var body: some View {
         InnerPFP(pubkey: pubkey, pictureUrl: pictureUrl, size: size, color: color, forceFlat: forceFlat)
    }
}

struct InnerPFP: View {
    public var pubkey: String
    public var pictureUrl: URL?
    public var size: CGFloat = 50.0
    public var color: Color? = nil
    public var forceFlat = false
    private var innerColor: Color {
        color ?? randomColor(seed: pubkey)
    }

    @ObservedObject private var settings: SettingsStore = .shared
    
    // Always render default circle (color is pubkey derived)
    // If not https don't render
    // If animated PFP disabled or image is not .gif, render flat
    // else render animated gif
    
    private enum RenderOption: Equatable {
        case noUrl
        case noHttps
        case flat(URL)
        case animatedGif(URL)
    }
    
    private var renderCase: RenderOption {
        guard let pictureUrl = pictureUrl else { return .noUrl }
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
                    
                case .flat(let url):
                    LazyImage(request: pfpImageRequestFor(url), transaction: .init(animation: .easeIn)) { state in
                        if let image = state.image {
                            if state.imageContainer?.type == .gif {
                                image
                                    .resizable() // BUG: Still .gif gets wrong dimensions, so need .resizable()
                                    .interpolation(.none)
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size, height: size)
                            }
                            else {
                                image
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: size, height: size)
                            }
                        }
                        else { color }
                    }
                    .pipeline(ImageProcessing.shared.pfp)
//                    .drawingGroup()
                    
                case .animatedGif(let url):
                    LazyImage(request: pfpImageRequestFor(url), transaction: .init(animation: .easeIn)) { state in
                        if let container = state.imageContainer {
                            if !ProcessInfo.processInfo.isLowPowerModeEnabled, container.type == .gif, let gifData = container.data {
                                ZStack {
                                    if let image = state.image {
                                        image
                                            .resizable()
                                            .interpolation(.none)
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
                                    .resizable()
                                    .interpolation(.none)
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size, height: size)
//                                    .cornerRadius(size/2)
//                                    .withoutAnimation()
                            }

                        }
                    }
                    .priority(.low) // lower prio for animated gif, saves bandwidth?
                    .pipeline(ImageProcessing.shared.pfp) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
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
    public var pictureUrl: URL?
    public var size: CGFloat = 20.0
    public var fallBackColor: Color? = nil
    
    var body: some View {
        if let pictureUrl {
            LazyImage(request: pfpImageRequestFor(pictureUrl), transaction: .init(animation: .easeIn)) { state in
                if let image = state.image {
                    if state.imageContainer?.type == .gif {
                        image
                            .resizable() // BUG: Still .gif gets wrong dimensions, so need .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                    }
                    else {
                        image
                            .resizable()
                            .interpolation(.none)
                            .frame(width: size, height: size)
                    }
                }
                else { fallBackColor ?? Color.defaultSecondaryBackground }
            }
            .pipeline(ImageProcessing.shared.pfp)
//            .drawingGroup()
            .frame(width: size, height: size)
            .cornerRadius(size/2)
            .background(
                Circle()
                    .strokeBorder(.regularMaterial, lineWidth: 3)
                    .background(Circle().fill(fallBackColor ?? Color.defaultSecondaryBackground))
            )
        }
        else {
            Circle()
                .strokeBorder(.regularMaterial, lineWidth: 3)
                .background(Circle().fill(fallBackColor ?? Color.defaultSecondaryBackground))
                .frame(width: size, height: size)
        }
    }
}
