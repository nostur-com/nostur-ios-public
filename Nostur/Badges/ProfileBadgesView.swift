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
            ProfileBadgesView(profileBadges:profileBadgesSorted.first!)
                .task {
                    print("FAKEREQ.. profileBadges is no longer nil")
                    // 30008 is already fetched when profile loads
                    // here we fetch any related 30009 + 8
                    if (profileBadgesSorted.first != nil) {
                        print("WTF \(profileBadges.count)")
                        print("WTF \(profileBadgesSorted.count)")
                        print("WTF \(profileBadgesSorted.first!.tags())")
                        print("WTF \(profileBadgesSorted.first!.tags())")
                        print("WTF \(profileBadgesSorted.first!.tagsSerialized)")
                        print("WTF \(profileBadgesSorted.first!.id)")

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
                        
                        print("🚺🚺🚺🚺🚺 \(allEs.count)")
                        if (allEs.count > 0) {
                            let reqE = RequestMessage.getEvents(ids: allEs)
                            let messageE = ClientMessage(type: .REQ, message: reqE)
                            SocketPool.shared.sendMessage(messageE) // Get badge awards (kind .8)
                        }
                        
                        if (filters.count > 0) {
                            let reqD = RequestMessage.getBageDefinitions(filters: filters)
                            let messageD = ClientMessage(type: .REQ, message: reqD)
                            SocketPool.shared.sendMessage(messageD) // Get badge definitions (kind 30009)
                        }
                    }
                }
                .onReceive(receiveNotification(.profileBadgesFetched), perform: { _ in
//                    refreshHack.toggle()
//                    profileBadges.objectWillChange.send()
                    
//                    // 30008 is already fetched when profile loads
//                    // here we fetch any related 30009 + 8
//                    if (profileBadges.first != nil) {
//                        let allEs = profileBadges.first!.tags()
//                            .filter { $0.type == "e" }
//                            .map { $0.id }
//
//                        var filters: [(Int64, String, String)] = []
//                        profileBadges.first!.tags()
//                            .filter { $0.type == "a" }
//                            .forEach {
//                                let a = BadgeATag($0)
//                                let filter = (a.kind, a.badgeCode, a.pubkey)
//                                filters.append(filter)
//                            }
//
//                        let reqE = RequestMessage.getEvents(ids: allEs)
//                        let messageE = ClientMessage(type: .REQ, message: reqE)
//                        SocketPool.shared.sendMessage(messageE) // Get badge awards (kind .8)
//
//                        if (filters.count > 0) {
//                            let reqD = RequestMessage.getBageDefinitions(filters: filters)
//                            let messageD = ClientMessage(type: .REQ, message: reqD)
//                            SocketPool.shared.sendMessage(messageD) // Get badge definitions (kind 30009)
//                        }
//                    }
                })
                .onReceive(receiveNotification(.badgeAwardFetched), perform: { _ in
                    refreshHack.toggle()
//                    profileBadges.objectWillChange.send()
                    // 30008 is already fetched when profile loads
                    // here we fetch any related 30009 + 8
//                    if (profileBadges.first != nil) {
//                        let allEs = profileBadges.first!.tags()
//                            .filter { $0.type == "e" }
//                            .map { $0.id }
//
//                        var filters: [(Int64, String, String)] = []
//                        profileBadges.first!.tags()
//                            .filter { $0.type == "a" }
//                            .forEach {
//                                let a = BadgeATag($0)
//                                let filter = (a.kind, a.badgeCode, a.pubkey)
//                                filters.append(filter)
//                            }
//
//                        let reqE = RequestMessage.getEvents(ids: allEs)
//                        let messageE = ClientMessage(type: .REQ, message: reqE)
//                        SocketPool.shared.sendMessage(messageE) // Get badge awards (kind .8)
//
//                        if (filters.count > 0) {
//                            let reqD = RequestMessage.getBageDefinitions(filters: filters)
//                            let messageD = ClientMessage(type: .REQ, message: reqD)
//                            SocketPool.shared.sendMessage(messageD) // Get badge definitions (kind 30009)
//                        }
//                    }
                })
                .onReceive(receiveNotification(.badgeDefinitionFetched), perform: { _ in
                    refreshHack.toggle()
//                    profileBadges.objectWillChange.send()
                })
        }
        else {
            EmptyView()
        }
        
    }
}

struct ProfileBadgesView: View {
    @ObservedObject var profileBadges:Event
    @Environment(\.dismiss) private var dismiss
    @State var selectedBadge:Event? = nil
    @State var badgeInfoIsShown = false
    @State var refreshHack = false
    
    var body: some View {
        HStack {
            ForEach(Array(profileBadges.verifiedBadges.prefix(3))) { profileBadge in
                BadgeIcon(badge: profileBadge.badge)
                    .onTapGesture {
                        badgeInfoIsShown = true
                    }
//                    .help("\(profileBadge.badge.toNEvent().tagNamed("name") ?? "Badge"): \(profileBadge.badge.toNEvent().tagNamed("description") ?? "No description")")
            }
        }
        .onAppear {
//            print(profileBadges.verifiedBadges)
        }
        .onReceive(receiveNotification(.profileBadgesFetched), perform: { _ in
//            profileBadges.objectWillChange.send()
            refreshHack.toggle()
        })
        .onReceive(receiveNotification(.badgeAwardFetched), perform: { _ in
//            profileBadges.objectWillChange.send()
            refreshHack.toggle()
        })
        .onReceive(receiveNotification(.badgeDefinitionFetched), perform: { _ in
//            profileBadges.objectWillChange.send()
            refreshHack.toggle()
        })
        .sheet(isPresented: $badgeInfoIsShown) {
            VStack(alignment: .leading) {
                if IS_IPAD {
                    HStack {
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .padding(30)
                            .onTapGesture {
                                badgeInfoIsShown = false
                            }
                    }
                }
                ForEach(profileBadges.verifiedBadges) { profileBadge in
                    BadgeRow(badge: profileBadge.badge)
                }
                Spacer()
            }
            .padding(20)
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
