//
//  BadgesIssuedView.swift
//  Nostur
//

import SwiftUI
import NavigationBackport

struct Badge: Hashable {
    let badge: Event
    init(_ badge: Event) { self.badge = badge }
}

struct BadgesIssuedContainer: View {
    @EnvironmentObject private var la: LoggedInAccount
    var body: some View { BadgesIssuedView(pubkey: la.account.publicKey) }
}

struct BadgesIssuedView: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @State private var isCreatingBadge = false

    let pubkey: String
    @FetchRequest private var badges: FetchedResults<Event>
    @FetchRequest private var awards: FetchedResults<Event>

    init(pubkey: String) {
        self.pubkey = pubkey

        let badgeRequest = Event.fetchRequest()
        badgeRequest.predicate = NSPredicate(
            format: "kind == %d AND pubkey == %@ AND mostRecentId == nil",
            BadgeKinds.definition,
            pubkey
        )
        badgeRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        _badges = FetchRequest(fetchRequest: badgeRequest)

        let awardRequest = Event.fetchRequest()
        awardRequest.predicate = NSPredicate(
            format: "kind == %d AND pubkey == %@",
            BadgeKinds.award,
            pubkey
        )
        awardRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        _awards = FetchRequest(fetchRequest: awardRequest)
    }

    private func recipientCount(for badge: Event) -> Int {
        guard let address = badge.badgeAddress else { return 0 }
        return Set(
            awards
                .filter { $0.isBadgeAward(for: address) }
                .flatMap { $0.pTags() }
        ).count
    }

    var body: some View {
        List(badges) { badge in
            NBNavigationLink(value: Badge(badge)) {
                BadgeIssuedRow(badge: badge, recipientCount: recipientCount(for: badge))
            }
            .listRowBackground(theme.background)
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        .overlay {
            if badges.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "seal").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No badges issued").font(.headline)
                    Text("Create a badge, then award it from its detail screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .task(id: pubkey) { await BadgeRelayLoader.fetchIssued(pubkey: pubkey) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Create new badge", systemImage: "plus") {
                    guard isFullAccount() else { showReadOnlyMessage(); return }
                    isCreatingBadge = true
                }
            }
        }
        .navigationTitle(String(localized: "Badges"))
        .sheet(isPresented: $isCreatingBadge) {
            NBNavigationStack {
                CreateNewBadgeSheet()
                    .environmentObject(la)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
}

struct BadgeIssuedRow: View {
    let badge: Event
    var recipientCount: Int? = nil

    private var nBadge: NEvent { badge.toNEvent() }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BadgeIcon(badge: badge, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge"))
                    .font(.headline)
                if let description = nBadge.badgeDescription?.value, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
                if let recipientCount {
                    Text("Awarded to \(recipientCount) people", comment: "Text showing how many badges have been awarded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
