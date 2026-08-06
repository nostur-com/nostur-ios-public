//
//  BadgesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI
import CoreData

struct BadgesView: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @State private var tab = "Issued"
    
    var body: some View {
        BadgeUnreadReader(pubkey: la.account.publicKey) { unread, markSeen in
            badgesContent(unread: unread, markSeen: markSeen)
                .onChange(of: unread) { newValue in
                    if tab == "Received", newValue > 0 { markSeen() }
                }
        }
        .id(la.account.publicKey)
    }

    private func badgesContent(unread: Int, markSeen: @escaping () -> Void) -> some View {
        VStack {
            HStack {
                TabButton(action: {
                    tab = "Issued"
                }, title: String(localized:"Issued", comment: "Tab title of Issues badges"), selected: tab == "Issued")
                
                TabButton(action: {
                    tab = "Received"
                    markSeen()
                }, title: String(localized: "Received", comment: "Tab title of Received badges"), selected: tab == "Received", unread: unread)
            }
            switch tab {
            case "Issued":
                BadgesIssuedContainer()
                    .background(theme.listBackground)
            case "Received":
                BadgesReceivedContainer()
                    .background(theme.listBackground)
            default:
                BadgesReceivedContainer()
                    .background(theme.listBackground)
            }
            Spacer()
        }
        .background(theme.listBackground)
        .nosturNavBgCompat(theme: theme)
    }
}

struct BadgeUnreadReader<Content: View>: View {
    private let pubkey: String
    private let markerKey: String
    private let content: (Int, @escaping () -> Void) -> Content

    @FetchRequest private var awards: FetchedResults<Event>
    @AppStorage private var lastSeenAt: Double

    init(
        pubkey: String,
        @ViewBuilder content: @escaping (Int, @escaping () -> Void) -> Content
    ) {
        self.pubkey = pubkey
        markerKey = accountSpecificKey(pubkey, forKey: "last_seen_badge_award_inserted_at")
        self.content = content

        let request = Event.fetchRequest()
        request.predicate = NSPredicate(
            format: "kind == %d AND tagsSerialized CONTAINS %@",
            BadgeKinds.award,
            serializedP(pubkey)
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.insertedAt, ascending: false)]
        request.fetchLimit = 100
        request.fetchBatchSize = 50
        _awards = FetchRequest(fetchRequest: request)
        _lastSeenAt = AppStorage(wrappedValue: 0, markerKey)
    }

    private var unreadCount: Int {
        guard UserDefaults.standard.object(forKey: markerKey) != nil else { return 0 }
        let lastSeenDate = Date(timeIntervalSince1970: lastSeenAt)
        let unreadEvents = awards.filter { $0.insertedAt > lastSeenDate }
        return receivedBadgeAddresses(
            from: unreadEvents.map { $0.toNEvent() },
            recipientPubkey: pubkey
        ).count
    }

    var body: some View {
        content(unreadCount, markSeen)
            .onAppear(perform: initializeMarkerIfNeeded)
    }

    private func initializeMarkerIfNeeded() {
        guard UserDefaults.standard.object(forKey: markerKey) == nil else { return }
        lastSeenAt = Date.now.timeIntervalSince1970
    }

    private func markSeen() {
        lastSeenAt = Date.now.timeIntervalSince1970
    }
}

struct BadgesView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadBadges() }) {
            BadgesView()
        }
    }
}
