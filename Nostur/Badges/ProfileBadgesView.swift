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
    var profileBadgesSorted:[Event] {
        profileBadges.sorted(by: { $0.created_at > $1.created_at})
    }
    
    @State var refreshHack = false

    init(pubkey:String) {
        self.pubkey = pubkey

        _profileBadges = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "kind == 30008 AND pubkey == %@", pubkey)
        )
    }
    
    var body: some View {
        if (profileBadgesSorted.first != nil) {
            ProfileBadgesView(verifiedBadges:profileBadgesSorted.first!.verifiedBadges)
                .task {
                    
                    // 30008 is already fetched when profile loads
                    // here we fetch any related 30009 + 8
                    if (profileBadgesSorted.first != nil) {
                        let allEs = profileBadgesSorted.first!.tags()
                            .filter { $0.type == "e" }
                            .map { $0.id }
                        
                        var filters: [(Int64, String, String)] = []
                        profileBadgesSorted.first!.tags()
                            .filter { $0.type == "a" }
                            .forEach {
                                let a = BadgeATag($0)
                                let filter = (a.kind, a.badgeCode, a.pubkey)
                                filters.append(filter)
                            }
                        
                        print("🚺🚺 \(allEs.count)")
                        if (allEs.count > 0) {
                            let reqE = RequestMessage.getEvents(ids: allEs)
                            let messageE = ClientMessage(type: .REQ, message: reqE)
                            SocketPool.shared.sendMessage(messageE) // Get badge awards (kind .8)
                        }
                        
                        if (filters.count > 0) {
                            let reqD = RequestMessage.getBadgeDefinitions(filters: Array(filters.prefix(10)))
                            let messageD = ClientMessage(type: .REQ, message: reqD)
                            SocketPool.shared.sendMessage(messageD) // Get badge definitions (kind 30009)
                        }
                    }
                }
                .onChange(of: profileBadgesSorted.first) { newValue in
                    if (newValue != nil) {
                        let allEs = newValue!.tags()
                            .filter { $0.type == "e" }
                            .map { $0.id }
                        
                        var filters: [(Int64, String, String)] = []
                        newValue!.tags()
                            .filter { $0.type == "a" }
                            .forEach {
                                let a = BadgeATag($0)
                                let filter = (a.kind, a.badgeCode, a.pubkey)
                                filters.append(filter)
                            }
                        
                        print("🚺🚺🚺🚺🚺 \(allEs.count)")
                        if (allEs.count > 0) {
                            let reqE = RequestMessage.getEvents(ids: allEs)
                            let messageE = ClientMessage(type: .REQ, message: reqE)
                            SocketPool.shared.sendMessage(messageE) // Get badge awards (kind .8)
                            
                        }
                        
                        if (filters.count > 0) {
                            let reqD = RequestMessage.getBadgeDefinitions(filters: filters)
                            let messageD = ClientMessage(type: .REQ, message: reqD)
                            SocketPool.shared.sendMessage(messageD) // Get badge definitions (kind 30009)
                        }
                        refreshHack.toggle()
                    }
                }
        }
        else {
            EmptyView()
        }
        
    }
}

struct ProfileBadgesView: View {
    var verifiedBadges:[ProfileBadge]
    @Environment(\.dismiss) private var dismiss
    @State var selectedBadge:Event? = nil
    @State var badgeInfoIsShown = false
    @State var refreshHack = false
    
    var body: some View {
        HStack {
            ForEach(Array(verifiedBadges.prefix(3))) { profileBadge in
                BadgeIcon(badge: profileBadge.badge)
                    .onTapGesture { badgeInfoIsShown = true }
            }
        }
        .sheet(isPresented: $badgeInfoIsShown) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(verifiedBadges) { profileBadge in
                            BadgeRow(badge: profileBadge.badge)
                        }
                        Spacer()
                    }
                }
                .padding(20)
                .presentationDetents([.height(250), .medium])
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(role: .cancel) {
                            badgeInfoIsShown = false
                        } label: {
                            Text("Close")
                        }

                    }
                }
            }
        }
    }
}

struct BadgeIcon: View {
    var badge:Event
    var nBadge:NEvent { badge.toNEvent() }

    var body: some View {
        if let pictureUrl = nBadge.badgeImage?.otherInformation[safe: 0] {
            if (pictureUrl.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                LazyImage(url: URL(string: pictureUrl)) { state in
                    if let container = state.imageContainer {
                        if container.type == .gif, let gifData = container.data {
                            AnimatedGifView(gifData: gifData, width: 32, height: 32)
                                .frame(width: 32, height: 32)
                                .clipped()
                        }
                        else if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 32, height: 32)
                                .clipped()
                        }
                        else {
                            ProgressView()
                        }
                    }
                    else {
                        ProgressView()
                    }
                }
                .pipeline(ImageProcessing.shared.badges) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                .priority(.low)
            }
            else {
                LazyImage(url: URL(string: pictureUrl)) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipped()
                    }
                    else {
                        CenteredProgressView()
                    }
                }
                .processors([.resize(width: 32)])
                .pipeline(ImageProcessing.shared.badges)
//                    .priority(.low)
            }
        }
    }
}

struct ProfileBadgesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
//            let p = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
            let pb = "5273115b3fad8a2d102e3335c0755083ed0baba48bd92c0c149a610212ccc3eb" // kind 30008
            
            let profileBadgesEvent = PreviewFetcher.fetchEvent(pb)
            if (profileBadgesEvent != nil) {
//                ProfileBadgesView(pubkey:p, profileBadges: profileBadgesEvent!)
                ProfileBadgesView(verifiedBadges: profileBadgesEvent?.verifiedBadges ?? [])
                    .withPreviewEnvironment()
            }
        }
    }
}
