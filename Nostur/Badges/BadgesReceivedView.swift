//
//  BadgesReceivedView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//
import SwiftUI
import Nuke
import NukeUI

//struct Badge: Hashable {
//    var badge:Event
//    init(_ badge: Event) {
//        self.badge = badge
//    }
//}

struct BadgesReceivedContainer:View {
    @EnvironmentObject var ns:NosturState
    var body: some View {
        if (ns.account != nil) {
            BadgesReceivedView(pubkey: ns.account!.publicKey)
        }
        else { Text("No account selected ")}
    }
}

struct BadgesReceivedView: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var up:Unpublisher
//    @Environment(\.editMode) private var editMode
    let nav:NavigationModel = .shared
    @State var createNewBadgeSheetShown = false
    var pubkey:String
    @FetchRequest
    var badgeAwards:FetchedResults<Event>
    @State var selection = Set<Event>()
    
    var badgeAwardsToMe:[Event] {
        badgeAwards
            .filter { $0.pTags().firstIndex(of: pubkey) != nil }
    }
    
    var badgesToMeIds:[String] {
        badgeAwardsToMe.compactMap { $0.toNEvent().badgeDefinitionId?.value }
    }
    
    init(pubkey:String) {
        self.pubkey = pubkey
        print("🧨🧨🧨🧨🧨 BadgesView 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format: "kind == 8 AND tagsSerialized CONTAINS %@", serializedP(pubkey)) // optimization hack
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _badgeAwards = FetchRequest(fetchRequest: r)
    }
    
    var body: some View {
        VStack {
            List(badgeAwardsToMe.compactMap { $0.badgeDefinition }, id:\.self, selection: $selection) { badge in
//                NavigationLink(value: Badge(badge)) {
                    BadgeRow(badge: badge)
//                }
            }
            
            Button {
                publishSelection(Array(selection))
            } label: { Text("Publish selected badges on profile") }
                .buttonStyle(.borderedProminent)
                .disabled(selection.count == 0)
            
            Spacer()
        }
        .onAppear {
            // fetch missing batch definitions:
            // or just all...
            let req = RequestMessage.getEvents(ids: badgesToMeIds)
            let message = ClientMessage(type: .REQ, message: req)
            SocketPool.shared.sendMessage(message)
        }
//        .toolbar {
//            ToolbarItem(placement: .primaryAction) {
//                EditButton()
//            }
//        }
        .navigationTitle("Badges received")
//        .sheet(isPresented: $createNewBadgeSheetShown) {
//            NavigationStack {
//                CreateNewBadgeSheet()
//            }
//        }
    }
    func publishSelection(_ selection:[Event]) {
        // argument is badge definition.
        // we need the badge award
        
        let selectedAwarded = badgeAwardsToMe
                    .filter {
                        selection
                            .map { $0.id }
                            .firstIndex(of: $0.badgeDefinition!.id) != nil
                    }
                    .map { $0.toNEvent() }
        
        let newProfileBadges = createProfileBadges(awards: selectedAwarded)

        do {
            guard let newProfileBadgesSigned = try? ns.signEvent(newProfileBadges) else { throw "could not create newProfileBadgesSigned " }
            _ = Event.saveEvent(event: newProfileBadgesSigned, context: viewContext)
            try viewContext.save()
            up.publishNow(newProfileBadgesSigned)
            self.selection.removeAll()
        }
        catch {
            print("🔴🔴 could not create badge")
            print(error)
        }
    }
}

//struct BadgeRow: View {
//    var badge:Event
//    var nBadge:NEvent { badge.toNEvent() }
//
//    var body: some View {
//        HStack(alignment: .top) {
//            VStack(alignment: .center) {
//                if nBadge.badgeImage?.otherInformation[safe: 0] != nil {
//                    LazyImage(url: URL(string: nBadge.badgeImage!.otherInformation[safe: 0]!)) { state in
//                        if let image = state.image {
//                            image.frame(width: 50, height: 50)
//                        }
//                        else {
//                            ProgressView()
//                        }
//                    }
//                    .processors([ImageProcessors.Resize(width: 50)])
//                    .animation(nil)
//                    .pipeline(ImageProcessing.shared.pipeline)
//                    .padding(10)
//                }
//            }
//            .frame(width: 60)
//
//            VStack(alignment: .leading, spacing: 2) {
//                Text(nBadge.badgeName?.value ?? "No name")
//                    .font(.subheadline)
//                Text(nBadge.badgeDescription?.value ?? "No description").font(.caption2)
//                Text("Awarded to \(badge.awardedTo.count) people").font(.caption)
//            }.padding(10)
//        }
//    }
//}

struct BadgesReceivedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BadgesReceivedContainer()
                .withPreviewEnvironment()
        }
    }
}
