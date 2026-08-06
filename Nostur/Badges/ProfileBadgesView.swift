//
//  ProfileBadgesView.swift
//  Nostur
//

import SwiftUI
import CoreData
import Nuke
import NukeUI
import NavigationBackport

struct ProfileBadgesContainer: View {
    let pubkey: String

    @FetchRequest private var profileEvents: FetchedResults<Event>

    init(pubkey: String) {
        self.pubkey = pubkey
        let request = Event.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pubkey == %@ AND mostRecentId == nil", pubkey),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "kind == %d", BadgeKinds.profile),
                NSPredicate(
                    format: "kind == %d AND dTag == %@",
                    BadgeKinds.legacyProfile,
                    BadgeKinds.legacyProfileIdentifier
                )
            ])
        ])
        _profileEvents = FetchRequest(fetchRequest: request)
    }

    private var preferredProfile: Event? {
        profileEvents.first(where: { $0.kind == Int64(BadgeKinds.profile) }) ?? profileEvents.first
    }

    var body: some View {
        Group {
            if let preferredProfile {
                ResolvedProfileBadgesView(profile: preferredProfile)
                    .id(preferredProfile.id)
            }
        }
        .task(id: pubkey, priority: .background) {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            await BadgeRefreshCoordinator.shared.refreshProfile(pubkey: pubkey)
        }
    }
}

private struct ResolvedProfileBadgesView: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme

    let profile: Event
    private let references: [BadgeReference]
    private let dependencyKey: String

    @FetchRequest private var awards: FetchedResults<Event>
    @FetchRequest private var definitions: FetchedResults<Event>
    @State private var isShowingAll = false

    init(profile: Event) {
        self.profile = profile
        let references = badgeReferences(from: profile.toNEvent())
        self.references = references
        dependencyKey = references.map(\.id).joined(separator: ",")

        let awardRequest = Event.fetchRequest()
        awardRequest.sortDescriptors = []
        let awardIds = references.map(\.awardEventId)
        awardRequest.predicate = awardIds.isEmpty
            ? NSPredicate(value: false)
            : NSPredicate(format: "kind == %d AND id IN %@", BadgeKinds.award, awardIds)
        _awards = FetchRequest(fetchRequest: awardRequest)

        let definitionRequest = Event.fetchRequest()
        definitionRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let addressPredicates = references.map {
            NSPredicate(
                format: "kind == %d AND pubkey == %@ AND dTag == %@ AND mostRecentId == nil",
                BadgeKinds.definition,
                $0.address.issuerPubkey,
                $0.address.identifier
            )
        }
        definitionRequest.predicate = addressPredicates.isEmpty
            ? NSPredicate(value: false)
            : NSCompoundPredicate(orPredicateWithSubpredicates: addressPredicates)
        _definitions = FetchRequest(fetchRequest: definitionRequest)
    }

    private var resolvedBadges: [ProfileBadge] {
        let awardsById = Dictionary(uniqueKeysWithValues: awards.map { ($0.id, $0) })
        let definitionsByAddress = Dictionary(
            definitions.compactMap { definition in
                definition.badgeAddress.map { ($0, definition) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return references.compactMap { reference in
            guard let award = awardsById[reference.awardEventId],
                  let definition = definitionsByAddress[reference.address],
                  isValidBadge(
                    reference: reference,
                    profilePubkey: profile.pubkey,
                    award: award.toNEvent(),
                    definition: definition.toNEvent()
                  ) else { return nil }
            return ProfileBadge(reference: reference, badge: definition, badgeAward: award)
        }
    }

    var body: some View {
        HStack {
            ForEach(resolvedBadges.prefix(3)) { profileBadge in
                BadgeIcon(badge: profileBadge.badge)
                    .frame(width: 32, height: 32)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { isShowingAll = !resolvedBadges.isEmpty }
        .sheet(isPresented: $isShowingAll) {
            NBNavigationStack {
                List(resolvedBadges) { profileBadge in
                    BadgeIssuedRow(badge: profileBadge.badge)
                }
                .listStyle(.plain)
                .navigationTitle(String(localized: "Badges"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { isShowingAll = false }
                    }
                }
                .environment(\.theme, theme)
                .environmentObject(la)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .task(id: dependencyKey, priority: .background) {
            do {
                try await Task.sleep(nanoseconds: 2_300_000_000)
            } catch {
                return
            }
            await BadgeRelayLoader.fetchDependencies(for: references)
        }
    }
}

func badgeArtworkURL(for badge: NEvent, targetWidth: Int) -> URL? {
    let candidates: [(url: String, width: Int?)] = badge.badgeThumbs.compactMap { tag in
        guard let url = tag.tag[safe: 1], !url.isEmpty else { return nil }
        let width = tag.tag[safe: 2]
            .flatMap { $0.split(separator: "x").first }
            .flatMap { Int($0) }
        return (url, width)
    }
    let best = candidates.min {
        abs(($0.width ?? targetWidth) - targetWidth) < abs(($1.width ?? targetWidth) - targetWidth)
    }?.url ?? badge.badgeImage?.tag[safe: 1]
    return best.flatMap(URL.init(string:))
}

struct BadgeIcon: View {
    let badge: Event
    var size: CGFloat = 32

    var body: some View {
        BadgeArtwork(nBadge: badge.toNEvent(), size: size)
    }
}

struct BadgeArtwork: View {
    let nBadge: NEvent
    let size: CGFloat

    var body: some View {
        if let url = badgeArtworkURL(for: nBadge, targetWidth: Int(size)) {
            LazyImage(
                request: ImageRequest(
                    url: url,
                    processors: [.resize(width: size)],
                    options: SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : [],
                    userInfo: [.scaleKey: UIScreen.main.scale]
                )
            ) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else if state.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "seal")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.secondary)
                }
            }
            .pipeline(ImageProcessing.shared.badges)
            .frame(width: size, height: size)
            .clipped()
            .accessibilityHidden(true)
        } else {
            Image(systemName: "seal")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
