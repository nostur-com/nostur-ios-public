//
//  BadgesReceivedView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//
import SwiftUI
import Nuke
import NukeUI

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
    let nav:NavigationModel = .shared
    @State var createNewBadgeSheetShown = false
    var pubkey:String
    @FetchRequest
    var badgeAwards:FetchedResults<Event>
    @State var selection = Set<Event>()
    
    var badgeAwardsToMe:[Event] { // ANY P's of KIND:8 == PUBKEY
        badgeAwards
            .filter { $0.pTags().firstIndex(of: pubkey) != nil }
    }
    
    var badgesToMeIds:[String] {
        badgeAwardsToMe.compactMap { $0.toNEvent().badgeAtag?.value }
    }
    
    init(pubkey:String) {
        self.pubkey = pubkey
        print("🧨🧨🧨🧨🧨 BadgesReceived🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format: "kind == 8 AND tagsSerialized CONTAINS %@", serializedP(pubkey)) // optimization hack
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _badgeAwards = FetchRequest(fetchRequest: r)
    }
    
    var body: some View {
        VStack {
            List(Array(Set(badgeAwardsToMe.compactMap { $0.badgeDefinition }).sorted(by: { $0.created_at > $1.created_at })), id:\.self, selection: $selection) { badge in
                    BadgeRow(badge: badge)
                    .id(badge.id)
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
            guard let newProfileBadgesSigned = try? ns.signEvent(newProfileBadges) else { throw "could not create newProfileBadgesSigned " }
            _ = Event.saveEvent(event: newProfileBadgesSigned, context: viewContext)
            try viewContext.save()
//            print(newProfileBadgesSigned.wrappedEventJson())
            up.publishNow(newProfileBadgesSigned)
            self.selection.removeAll()
        }
        catch {
            print("🔴🔴 could not create badge")
            print(error)
        }
    }
}

struct BadgesReceivedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BadgesReceivedContainer()
                .withPreviewEnvironment()
        }
    }
}
