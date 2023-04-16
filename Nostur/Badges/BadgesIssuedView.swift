//
//  BadgesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI
import Nuke
import NukeUI

struct Badge: Hashable {
    var badge:Event
    init(_ badge: Event) {
        self.badge = badge
    }
}

struct BadgesIssuedContainer:View {
    @EnvironmentObject var ns:NosturState
    var body: some View {
        if (ns.account != nil) {
            BadgesIssuedView(pubkey: ns.account!.publicKey)
        }
        else { Text("No account selected ")}
    }
}

struct BadgesIssuedView: View {
    @State var createNewBadgeSheetShown = false
    @FetchRequest
    var badges:FetchedResults<Event>
    var pubkey:String
    
    init(pubkey:String) {
        self.pubkey = pubkey
        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format: "kind == 30009 AND pubkey == %@", pubkey)
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _badges = FetchRequest(fetchRequest: r)
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
//            Button { createNewBadgeSheetShown = true } label: { Text("Create new badge") }
//            NavigationStack {
                List(badges) { badge in
                    NavigationLink(value: Badge(badge)) {
                        BadgeRow(badge: badge)
                    }
                }
//            }
        }
        .onAppear {
            // fetch missing batch definitions:
            // or just all...
            let req = RequestMessage.getBadgesCreatedAndAwarded(pubkey: pubkey)
            let message = ClientMessage(type: .REQ, message: req)
            SocketPool.shared.sendMessage(message)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    createNewBadgeSheetShown = true
                }, label: {
                    Text("Create new badge")
                })
            }
        }
        .navigationTitle("Badges")
        .sheet(isPresented: $createNewBadgeSheetShown) {
            NavigationStack {
                CreateNewBadgeSheet()
            }
        }
    }
}

struct BadgeRow: View {
    var badge:Event
    var nBadge:NEvent { badge.toNEvent() }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .center) {
                if let pictureUrl = nBadge.badgeImage?.otherInformation[safe: 0] {
                    if (pictureUrl.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                        LazyImage(url: URL(string: pictureUrl)) { state in
                            if let container = state.imageContainer {
                                if container.type == .gif, let gifData = container.data {
                                    AnimatedGifView(gifData: gifData, width: 50, height: 50)
                                        .scaledToFit()
                                        .frame(width: 50, height: 50)
                                        .clipped()
                                        .padding(10)
                                }
                                else if let image = state.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
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
                                    userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 50, height: 50)
                                    .clipped()
                                    .padding(10)
                            }
                            else {
                                CenteredProgressView()
                            }
                        }
//                        .processors([.resize(width: 50)])
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
        .navigationTitle("")
    }
    
}

struct BadgesIssuedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BadgesIssuedContainer()
                .withPreviewEnvironment()
        }
    }
}
