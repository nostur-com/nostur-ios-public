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
    let nav:NavigationModel = .shared
    @State var createNewBadgeSheetShown = false
    @FetchRequest
    var badges:FetchedResults<Event>
    
    init(pubkey:String) {
        print("🧨🧨🧨🧨🧨 BadgesView 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format: "kind == 30009 AND pubkey == %@", pubkey)
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _badges = FetchRequest(fetchRequest: r)
    }
    
    var body: some View {
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
                if nBadge.badgeImage?.otherInformation[safe: 0] != nil {
                    LazyImage(url: URL(string: nBadge.badgeImage!.otherInformation[safe: 0]!)) { state in
                        if let image = state.image {
                            image.frame(width: 50, height: 50)
                        }
                        else {
                            ProgressView()
                        }
                    }
                    .processors([ImageProcessors.Resize(width: 50)])
                    .animation(nil)
                    .pipeline(ImageProcessing.shared.pipeline)
                    .padding(10)
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
