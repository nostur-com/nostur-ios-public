//
//  BadgeDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
import NavigationBackport

struct BadgeDetailView: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var la: LoggedInAccount
    
    @State var awardToPeopleIsShown = false
    
    var badge:Event
    var nBadge: NEvent { badge.toNEvent() }
    
    @FetchRequest
    var badgeAwards: FetchedResults<Event>
    //    var nBadgeAwards:[NEvent] { badgeAwards.map { $0.toNEvent() }.filter { $0.badgeDescription != nil && $0.badgeDefinition!.value == nBadge.badgeDefinition!.value } }
    
    init(badge: Event) {
        self.badge = badge
        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format: "kind == 8 AND tagsSerialized CONTAINS %@", "[\"a\",\"\(badge.toNEvent().badgeCode!.value)") // OPTIMISATION HACK
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _badgeAwards = FetchRequest(fetchRequest: r)
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        ScrollView {
            HStack(alignment: .top) {
                VStack(alignment: .center) {
                    if let pictureUrl = nBadge.badgeImage?.tag[safe: 1] {
                        if (pictureUrl.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                            LazyImage(url: URL(string: pictureUrl)) { state in
                                if let container = state.imageContainer {
                                    if container.type == .gif, let gifData = container.data {
                                        GIFImage(data: gifData, isPlaying: .constant(true))
//                                            .aspectRatio(contentMode: .fit)
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
                                    //                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 50, height: 50)
                                        .clipped()
                                        .padding(10)
                                }
                                else {
                                    CenteredProgressView()
                                }
                            }
                            //                            .processors([.resize(width: 50)])
                                                            .pipeline(ImageProcessing.shared.badges)
                            //                    .priority(.low)
                        }
                    }
                }
                .frame(width: 60)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(nBadge.badgeName?.value ?? "No name")
                        .font(.subheadline)
                    Text(nBadge.badgeDescription?.value ?? "No description").font(.caption2)
                    Text("Awarded to \(badge.awardedTo.count) people").font(.caption)
                }.padding(10)
            }
            Spacer()
            
            
            Button { awardToPeopleIsShown = true } label: { Text("Award to people", comment: "Button to award a badge to people") }
                .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
            // award to people
            
            // lazy vstack foreach award p
            ForEach(badge.badgeAwards) { award in
                Text("Awarded to \(award.toNEvent().pTags().count) people on \(Date(timeIntervalSince1970: Double(award.created_at)).formatted())", comment: "Showing how many people received this badge on which date")
            }
        }
        .sheet(isPresented: $awardToPeopleIsShown) {
            NBNavigationStack {
                ContactsSearch(followingPubkeys: follows(), prompt: "Search contacts", onSelectContacts: { selectedContacts in
                    awardToPeopleIsShown = false
                    guard !selectedContacts.isEmpty else { return }
                    let newBadgeAwards = createBadgeAward(la.account.publicKey,
                                                          badgeCode: nBadge.badgeCode!.definition,
                                                          pubkeys: selectedContacts.map { $0.pubkey })
                    do {
                        guard let newBadgeAwardsSigned = try? la.account.signEvent(newBadgeAwards) else { throw "could not create newBadgeAwardsSigned " }
                        bg().perform {
                            _ = Event.saveEvent(event: newBadgeAwardsSigned)
                            DataProvider.shared().bgSave()
                        }
                        Unpublisher.shared.publishNow(newBadgeAwardsSigned)
                    }
                    catch {
                        L.og.error("🔴🔴 could not create badge \(error)")
                    }
                })
                .navigationTitle(String(localized:"Award to", comment: "Navigation title of screen where you choose who to award badge to"))
                .navigationBarTitleDisplayMode(.inline)
                .environmentObject(themes)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
    }
}

struct BadgeDetailView_Previews: PreviewProvider {
    static var previews: some View {
        
        let id = "6215b9fee3834ff25da4962dfb0d72e3dd648a454491dc213da5bdf735d7ddd9"
        
        PreviewContainer({ pe in pe.loadBadges() }) {
            NBNavigationStack {
                if let badge = PreviewFetcher.fetchEvent(id) {
                    BadgeDetailView(badge: badge)
                }
            }
        }
        
    }
}
