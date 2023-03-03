//
//  ProfileBadgesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/03/2023.
//
//
//  BadgesReceivedView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//
import SwiftUI
import Nuke
import NukeUI
import CoreData

struct ProfileBadgesContainer: View {
    @Environment(\.managedObjectContext) var viewContext
    let pubkey:String
    
    @FetchRequest
    var profileBadges:FetchedResults<Event>

    init(pubkey:String) {
        self.pubkey = pubkey

        _profileBadges = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "kind == 30008 AND pubkey == %@", pubkey)
        )
    }
    
    var body: some View {
        if (profileBadges.first != nil) {
            ProfileBadgesView(profileBadges:profileBadges.first!)
                .onAppear {
                    // 30008 is already fetched when profile loads
                    // here we fetch any related 30009 + 8
                    if (profileBadges.first != nil) {
                        let allAandEs = profileBadges.first!.tags()
                            .filter { $0.type == "e" || $0.type == "a" }
                            .map { $0.id }
                        
                        let req = RequestMessage.getEvents(ids: allAandEs)
                        let message = ClientMessage(type: .REQ, message: req)
                        SocketPool.shared.sendMessage(message)
                    }
                }
        }
        else {
            EmptyView()
        }
        
    }
}

struct ProfileBadgesView: View {
    var profileBadges:Event
    @Environment(\.dismiss) private var dismiss
    @State var selectedBadge:Event? = nil
    @State var badgeInfoIsShown = false
    
    var body: some View {
        HStack {
            ForEach(profileBadges.verifiedBadges) { profileBadge in
                BadgeIcon(badge: profileBadge.badge)
                    .onTapGesture {
                        badgeInfoIsShown = true
                    }
//                    .help("\(profileBadge.badge.toNEvent().tagNamed("name") ?? "Badge"): \(profileBadge.badge.toNEvent().tagNamed("description") ?? "No description")")
            }
        }
        .sheet(isPresented: $badgeInfoIsShown) {
            VStack {
                if IS_IPAD {
                    HStack {
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .padding(30)
                            .onTapGesture {
                                dismiss()
                            }
                    }
                }
                ForEach(profileBadges.verifiedBadges) { profileBadge in
                    BadgeRow(badge: profileBadge.badge)
                }
                Spacer()
            }
            .padding(.top, 20)
            .presentationDetents([.height(250), .medium])
        }
    }
}

struct BadgeIcon: View {
    var badge:Event
    var nBadge:NEvent { badge.toNEvent() }

    var body: some View {
        if nBadge.badgeImage?.otherInformation[safe: 0] != nil {
            LazyImage(url: URL(string: nBadge.badgeImage!.otherInformation[safe: 0]!)) { state in
                if let image = state.image {
                    image.frame(width: 32, height: 32)
                }
                else {
                    ProgressView()
                }
            }
            .processors([ImageProcessors.Resize(width: 32)])
            .animation(nil)
            .pipeline(ImageProcessing.shared.pipeline)
            .padding(0)
            .frame(width: 32, height: 32)
        }
    }
}

struct ProfileBadgesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            let p = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
            let pb = "5273115b3fad8a2d102e3335c0755083ed0baba48bd92c0c149a610212ccc3eb" // kind 30008
            
            let profileBadgesEvent = PreviewFetcher.fetchEvent(pb)
            if (profileBadgesEvent != nil) {
//                ProfileBadgesView(pubkey:p, profileBadges: profileBadgesEvent!)
                ProfileBadgesView(profileBadges: profileBadgesEvent!)
                    .withPreviewEnvironment()
            }
        }
    }
}
