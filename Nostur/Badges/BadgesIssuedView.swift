//
//  BadgesIssuedView.swift
//  Nostur
//

import SwiftUI
import NavigationBackport

struct Badge: Hashable, IdentifiableDestination {
    let badge: Event
    var id: String { badge.id }
    init(_ badge: Event) { self.badge = badge }
}

struct BadgesIssuedContainer: View {
    @EnvironmentObject private var la: LoggedInAccount
    var body: some View { BadgesIssuedView(pubkey: la.account.publicKey) }
}

struct BadgesIssuedView: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
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

    private func awards(for badge: Event) -> [Event] {
        guard let address = badge.badgeAddress else { return [] }
        return awards.filter { $0.isBadgeAward(for: address) }
    }

    private func recipientCount(for badgeAwards: [Event]) -> Int {
        Set(badgeAwards.flatMap { $0.pTags() }).count
    }

    var body: some View {
        List(badges) { badge in
            let badgeAwards = awards(for: badge)
            BadgeIssuedRow(
                badge: badge,
                recipientCount: recipientCount(for: badgeAwards),
                lastAwardedAt: badgeAwards.map(\.created_at).max()
            )
            .contentShape(Rectangle())
            .onTapGesture {
                navigateTo(Badge(badge), context: containerID)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                navigateTo(Badge(badge), context: containerID)
            }
            .listRowBackground(theme.background)
            .listRowSeparator(.hidden)
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        .overlay {
            if badges.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "seal").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No badges created").font(.headline)
                    Text("Create a badge, then award it from its detail screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Create badge", systemImage: "plus") {
                        guard isFullAccount() else { showReadOnlyMessage(); return }
                        isCreatingBadge = true
                    }
                    .buttonStyle(NRButtonStyle(style: .borderedProminent))
                    .padding(.top, 6)
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
    var lastAwardedAt: Int64? = nil

    private var nBadge: NEvent { badge.toNEvent() }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BadgeIcon(badge: badge, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if let description = nBadge.badgeDescription?.value, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                if let recipientCount {
                    VStack(alignment: .leading, spacing: 3) {
                        metadataRow(systemImage: "person.2") {
                            Text(recipientText(recipientCount))
                        }
                        if let lastAwardedAt, recipientCount > 0 {
                            metadataRow(systemImage: "clock") {
                                Text("Last awarded")
                                BadgeRelativeTime(lastAwardedAt)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(minHeight: 56)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func recipientText(_ count: Int) -> String {
        if count == 1 { return String(localized: "1 recipient") }
        return String(localized: "\(count) recipients")
    }

    private func metadataRow<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .frame(width: 16, alignment: .center)
            HStack(spacing: 3) {
                content()
            }
        }
    }
}
