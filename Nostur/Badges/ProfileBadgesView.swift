//
//  ProfileBadgesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
import CoreData
import NavigationBackport

struct ProfileBadgesContainer: View {
    let pubkey:String
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false))
    var profileBadges:FetchedResults<Event>
    
    var profileBadgesSorted:[Event] {
        profileBadges.sorted(by: { $0.created_at > $1.created_at})
    }
    
    @State var refreshHack = false
    
    init(pubkey:String) {
        self.pubkey = pubkey
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 30008 AND pubkey == %@ AND mostRecentId == nil", pubkey)
        
        _profileBadges = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        if let first = profileBadgesSorted.first  {
            ProfileBadgesView(verifiedBadges:first.verifiedBadges)
                .task {
                    // 30008 is already fetched when profile loads
                    // here we fetch any related 30009 + 8
                    let allEs = first.tags()
                        .filter { $0.type == "e" }
                        .map { $0.id }
                    
                    var filters: [(Int64, String, String)] = []
                    first.tags()
                        .filter { $0.type == "a" }
                        .forEach {
                            let a = BadgeATag($0)
                            let filter = (a.kind, a.badgeCode, a.pubkey)
                            if a.pubkey == "NONE" { return }
                            filters.append(filter)
                        }
                    
                    L.og.debug("🚺🚺 \(allEs.count)")
                    if (!allEs.isEmpty) {
                        // Get badge awards (kind .8)
                        req(RM.getEvents(ids: allEs))
                    }
                    
                    if (!filters.isEmpty) {
                        // Get badge definitions (kind 30009)
                        req(RM.getBadgeDefinitions(filters: Array(filters.prefix(10))))
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
                        
                        L.og.debug("🚺🚺🚺🚺🚺 \(allEs.count)")
                        if (!allEs.isEmpty) {
                            // Get badge awards (kind .8)
                            req(RM.getEvents(ids: allEs))
                        }
                        
                        if (!filters.isEmpty) {
                            // Get badge definitions (kind 30009)
                            req(RM.getBadgeDefinitions(filters: filters))
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
    @EnvironmentObject private var themes: Themes
    var verifiedBadges: [ProfileBadge]
    @State var selectedBadge: Event? = nil
    @State var badgeInfoIsShown = false
    @State var refreshHack = false
    
    var body: some View {
//        let _ = Self._printChanges()
        HStack {
            ForEach(Array(verifiedBadges.prefix(3))) { profileBadge in
                BadgeIcon(badge: profileBadge.badge)
                    .frame(width: 32, height: 32)
                    .onTapGesture { badgeInfoIsShown = true }
            }
            Spacer()
        }
        .sheet(isPresented: $badgeInfoIsShown) {
            NBNavigationStack {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(verifiedBadges) { profileBadge in
                            BadgeIssuedRow(badge: profileBadge.badge)
                        }
                        Spacer()
                    }
                }
                .padding(20)
                .presentationDetents250medium()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(role: .cancel) {
                            badgeInfoIsShown = false
                        } label: {
                            Text("Close")
                        }
                        
                    }
                }
                .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
    }
}

struct BadgeIcon: View {
    var badge:Event
    var nBadge:NEvent { badge.toNEvent() }
    
    var body: some View {
        if let pictureUrl = nBadge.badgeThumb?.tag[safe: 1] {
            if (pictureUrl.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                LazyImage(url: URL(string: pictureUrl)) { state in
                    if let container = state.imageContainer {
                        if container.type == .gif, let gifData = container.data {
                            GIFImage(data: gifData, isPlaying: .constant(true))
//                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipped()
                        }
                        else if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipped()
                        }
                        else if state.isLoading {
                            ProgressView()
                        }
                        else {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                    }
                    else {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                }
                .pipeline(ImageProcessing.shared.badges) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                .priority(.low)
            }
            else {
                LazyImage(request: ImageRequest(url: URL(string:pictureUrl),
                                                processors: [.resize(width: 32)],
                                                options: SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : [],
                                                userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .clipped()
                    }
                    else if state.isLoading {
                        CenteredProgressView()
                    }
                    else {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                }
                                                .pipeline(ImageProcessing.shared.badges)
            }
        }
    }
}

struct ProfileBadgesView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadBadges() }) {
            NBNavigationStack {
                let pb = "d7df976260e394f6708d4071ef1baa450e7390967c5dab640d528dd8a7d72894" // kind 30008
                if let profileBadgesEvent = PreviewFetcher.fetchEvent(pb) {
                    ProfileBadgesView(verifiedBadges: profileBadgesEvent.verifiedBadges)
                    
                }
            }
        }
    }
    
}
