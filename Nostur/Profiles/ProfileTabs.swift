//
//  ProfileTabs.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/05/2023.
//

import SwiftUI

struct ProfileTabs: View {
    @ObservedObject public var nrContact:NRContact
    @Binding public var selectedSubTab:String
    
    @EnvironmentObject private var themes:Themes
    private var pubkey:String { nrContact.pubkey }
    @EnvironmentObject private var dim:DIMENSIONS

    var body: some View {
        Section {
            VStack {
                switch selectedSubTab {
                    case "Posts":
                        ProfilePostsView(pubkey: pubkey)
                    case "Following":
                        ProfileFollowingList(pubkey: pubkey)
                    case "Media":
                        ProfileMediaView(pubkey: pubkey)
                    case "Likes":
                        ProfileLikesView(pubkey: pubkey)
                    case "Zaps":
                        if #available(iOS 16.0, *), let mainContact = nrContact.mainContact {
                            ProfileZaps(pubkey: pubkey, contact: mainContact)
                        }
                        else {
                            EmptyView()
                        }
                    case "Relays":
                        ProfileRelays(pubkey: pubkey, name: nrContact.anyName)
                    case "Followers":
                        VStack {
                            Text("Followers", comment: "Heading").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                            FollowersList(pubkey: nrContact.pubkey)
                        }
                    default:
                        Text("🥪")
                }
                Spacer()
            }
            .padding(.top, 10)
            .background(themes.theme.listBackground)
            .frame(minHeight: 800)
        } header: {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    TabButton(
                        action: { selectedSubTab = "Posts" },
                        title: String(localized:"Posts", comment:"Tab title"),
                        selected: selectedSubTab == "Posts")
                    Spacer()
                    TabButton(
                        action: { selectedSubTab = "Following" },
                        title: String(localized:"Following", comment:"Tab title"),
                        selected: selectedSubTab == "Following")
                    Spacer()
                    TabButton(
                        action: { selectedSubTab = "Media" },
                        title: String(localized:"Media", comment:"Tab title"),
                        selected: selectedSubTab == "Media")
                    Spacer()
                    TabButton(
                        action: { selectedSubTab = "Likes" },
                        title: String(localized:"Likes", comment:"Tab title"),
                        selected: selectedSubTab == "Likes")
                    Spacer()
                    if #available(iOS 16.0, *) {
                        TabButton(
                            action: { selectedSubTab = "Zaps" },
                            title: String(localized:"Zaps", comment:"Tab title"),
                            selected: selectedSubTab == "Zaps")
                        Spacer()
                    }
                    TabButton(
                        action: { selectedSubTab = "Relays" },
                        title: "Relays",
                        selected: selectedSubTab == "Relays")
                }
                .frame(width: dim.listWidth)
            }
            .padding(.top, 10)
            .background(themes.theme.background)
        }
    }
}

#Preview("ProfileTabs") {
    let f = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
    return PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        ScrollView {
            if let nrContact = PreviewFetcher.fetchNRContact(f) {
                ProfileTabs(nrContact: nrContact, selectedSubTab: .constant("Posts"))
            }
        }
    }
}
