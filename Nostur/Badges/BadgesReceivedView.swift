//
//  BadgesReceivedView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
import NavigationBackport

struct BadgesReceivedContainer:View {
    @EnvironmentObject var la: LoggedInAccount
    var body: some View {
        BadgesReceivedView(pubkey: la.account.publicKey)
    }
}

struct BadgesReceivedView: View {
    @Environment(\.theme) private var theme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var la: LoggedInAccount

    @State private var createNewBadgeSheetShown = false
    private var pubkey: String
    
    @FetchRequest
    private var badgeAwards: FetchedResults<Event>
    @State private var selection = Set<Event>()
    
    private var badgeAwardsToMe: [Event] { // ANY P's of KIND:8 == PUBKEY
        badgeAwards
//            .filter { $0.pTags().firstIndex(of: pubkey) != nil }
            .filter { ($0.tagsSerialized ?? "").contains(serializedP(pubkey)) } // optimization hack
    }
    
    private var badgesToMeIds: [String] {
        badgeAwardsToMe.compactMap { $0.toNEvent().badgeAtag?.value }
    }
    
    init(pubkey: String) {
        self.pubkey = pubkey
        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format: "kind == 8 AND tagsSerialized CONTAINS %@", serializedP(pubkey)) // optimization hack
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _badgeAwards = FetchRequest(fetchRequest: r)
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack {
            List(Array(Set(badgeAwardsToMe.compactMap { $0.badgeDefinition }).sorted(by: { $0.created_at > $1.created_at })), id:\.self) { badge in
                BadgeReceivedRow(badge: badge, selectedBadges: $selection)
                    .id(badge.id)
                    .listRowBackground(theme.background)
//                    .background(theme.background)
            }
            .scrollContentBackgroundCompat(.hidden)
            .listStyle(.plain)
            .background(theme.listBackground)
            
            Button {
                guard isFullAccount() else { showReadOnlyMessage(); return }
                publishSelection(Array(selection))
            } label: { Text("Publish selected badges on profile") }
                .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))
                .disabled(selection.isEmpty)
            
            Spacer()
        }
        .background(theme.listBackground)
        .navigationTitle("")
        .onAppear {
            // fetch missing badge definitions:
            // or just all...
            req(RequestMessage.getEvents(ids: badgeAwardsToMe.map { $0.id }))
            
            // Fetch other badges received
            req(RequestMessage.getBadgesReceived(pubkey))
        }
        .navigationTitle("Badges received")
    }
    func publishSelection(_ selection:[Event]) {
        // argument is badge definition. (KIND:30009)
        // we need the badge award
        let selectedAwarded = badgeAwardsToMe // [KIND:8]
                    .filter {
                        selection // [KIND:30009]
                            .map { $0.badgeA } // [["a","30009:alice:bravery"]]
                            .firstIndex(of: $0.firstA() ) != nil
                    }
                    .map { $0.toNEvent() }
        
        let newProfileBadges = createProfileBadges(awards: selectedAwarded)

        do {
            guard let newProfileBadgesSigned = try? la.account.signEvent(newProfileBadges) else { throw "could not create newProfileBadgesSigned " }
            let bgContext = bg()
            bgContext.perform {
                _ = Event.saveEvent(event: newProfileBadgesSigned, context: bgContext)
                DataProvider.shared().saveToDiskNow(.bgContext)
            }
            Unpublisher.shared.publishNow(newProfileBadgesSigned)
            self.selection.removeAll()
        }
        catch {
            L.og.error("🔴🔴 could not create badge \(error)")
        }
    }
}

// Same as BadgeIssuedRow, only added Button.
struct BadgeReceivedRow: View {
    var badge:Event
    @Binding var selectedBadges:Set<Event>
    var nBadge:NEvent { badge.toNEvent() }
    
    var body: some View {
        HStack(alignment: .center) {
            
            Button {
                if selectedBadges.contains(badge) {
                    selectedBadges.remove(badge)
                }
                else {
                    selectedBadges.insert(badge)
                }
            } label: {
                if selectedBadges.contains(badge) {
                    Image(systemName:  "checkmark.circle.fill")
                }
                else {
                    Image(systemName:  "circle")
                        .foregroundColor(Color.secondary)
                }
            }
            
            VStack(alignment: .center) {
                if let pictureUrl = nBadge.badgeImage?.tag[safe: 1] {
                    if (pictureUrl.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                        LazyImage(url: URL(string: pictureUrl)) { state in
                            if let container = state.imageContainer {
                                if container.type == .gif, let gifData = container.data {
                                    GIFImage(data: gifData, isPlaying: .constant(true))
//                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 50, height: 50)
                                        .clipped()
                                        .padding(10)
                                }
                                else if let image = state.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 50, height: 50)
                                        .clipped()
                                        .padding(10)
                                }
                                else {
                                    CenteredProgressView()
                                }
                            }
                            else {
                                CenteredProgressView()
                            }
                        }
                        .pipeline(ImageProcessing.shared.badges) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                    }
                    else {
                        LazyImage(request: ImageRequest(url: URL(string:pictureUrl),
                                    processors: [.resize(width: 50)],
                                    options: SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : [],
                                    userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 50)
                                    .clipped()
                                    .padding(10)
                            }
                            else {
                                CenteredProgressView()
                            }
                        }
                        .pipeline(ImageProcessing.shared.badges)
                    }
                }
            }
            .frame(width: 60)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(nBadge.badgeName?.value ?? "No name")
                    .font(.subheadline)
                Text(nBadge.badgeDescription?.value ?? "No description").font(.caption2)
                Text("Awarded to \(badge.awardedTo.count) people", comment: "Text showing how many badges have been awarded").font(.caption)
            }.padding(10)
        }
        .navigationTitle("")
    }
    
}

struct BadgesReceivedView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadBadges() }) {
            NBNavigationStack {
                BadgesReceivedContainer()
            }
        }
    }
}
