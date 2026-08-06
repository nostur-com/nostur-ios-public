//
//  BadgesReceivedView.swift
//  Nostur
//

import SwiftUI
import CoreData
import NavigationBackport

struct BadgesReceivedContainer: View {
    @EnvironmentObject private var la: LoggedInAccount
    var body: some View { BadgesReceivedView(pubkey: la.account.publicKey) }
}

struct BadgesReceivedView: View {
    let pubkey: String

    @FetchRequest private var awards: FetchedResults<Event>
    @FetchRequest private var profileEvents: FetchedResults<Event>

    init(pubkey: String) {
        self.pubkey = pubkey

        let awardRequest = Event.fetchRequest()
        awardRequest.predicate = NSPredicate(
            format: "kind == %d AND tagsSerialized CONTAINS %@",
            BadgeKinds.award,
            serializedP(pubkey)
        )
        awardRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        awardRequest.fetchLimit = 500
        awardRequest.fetchBatchSize = 50
        _awards = FetchRequest(fetchRequest: awardRequest)

        let profileRequest = Event.fetchRequest()
        profileRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        profileRequest.fetchLimit = 2
        profileRequest.fetchBatchSize = 2
        profileRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
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
        _profileEvents = FetchRequest(fetchRequest: profileRequest)
    }

    private var preferredProfile: Event? {
        profileEvents.first(where: { $0.kind == Int64(BadgeKinds.profile) }) ?? profileEvents.first
    }

    var body: some View {
        BadgeSelectionView(
            pubkey: pubkey,
            awards: Array(awards),
            profile: preferredProfile
        )
        .task(id: pubkey) {
            async let profile: Void = BadgeRefreshCoordinator.shared.refreshProfile(pubkey: pubkey)
            async let received: Void = BadgeRefreshCoordinator.shared.refreshReceived(pubkey: pubkey, force: true)
            _ = await (profile, received)
        }
        .navigationTitle(String(localized: "Badges received"))
    }
}

@MainActor
private final class BadgeSelectionModel: ObservableObject {
    @Published private(set) var selected: [BadgeReference]
    private var baseline: [BadgeReference]
    private var profileEventId: String?

    init(profile: Event?) {
        let references = profile.map { badgeReferences(from: $0.toNEvent()) } ?? []
        selected = references
        baseline = references
        profileEventId = profile?.id
    }

    var hasChanges: Bool { selected != baseline }

    func load(profile: Event?) {
        guard profile?.id != profileEventId else { return }
        let references = profile.map { badgeReferences(from: $0.toNEvent()) } ?? []
        selected = references
        baseline = references
        profileEventId = profile?.id
    }

    func add(_ reference: BadgeReference) {
        selected.removeAll { $0.address == reference.address }
        selected.append(reference)
    }

    func remove(_ reference: BadgeReference) {
        selected.removeAll { $0.address == reference.address }
    }

    func remove(at offsets: IndexSet) {
        selected.remove(atOffsets: offsets)
    }

    func move(from source: IndexSet, to destination: Int) {
        selected.move(fromOffsets: source, toOffset: destination)
    }

    func markPublished(eventId: String) {
        baseline = selected
        profileEventId = eventId
    }
}

private struct BadgeCandidate: Identifiable {
    let reference: BadgeReference
    let badge: Event
    let award: Event
    var id: String { reference.id }
}

private struct BadgeWearerSelection: Identifiable {
    let address: BadgeAddress
    let badgeName: String
    let pubkeys: [String]
    var id: String { address.value }
}

private struct BadgeSelectionView: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme

    let pubkey: String
    let awards: [Event]
    let profile: Event?
    private let addresses: [BadgeAddress]
    private let dependencyKey: String

    @FetchRequest private var definitions: FetchedResults<Event>
    @FetchRequest private var profileBadges: FetchedResults<Event>
    @FetchRequest private var wearerAwards: FetchedResults<Event>
    @StateObject private var model: BadgeSelectionModel
    @State private var errorMessage: String?
    @State private var selectedWearers: BadgeWearerSelection?

    init(pubkey: String, awards: [Event], profile: Event?) {
        self.pubkey = pubkey
        self.awards = awards
        self.profile = profile
        _model = StateObject(wrappedValue: BadgeSelectionModel(profile: profile))

        let addresses = Set(awards.compactMap { award -> BadgeAddress? in
            let nAward = award.toNEvent()
            let aTags = nAward.tags.filter { $0.type == "a" }
            guard aTags.count == 1,
                  nAward.kind.id == BadgeKinds.award,
                  nAward.tags.contains(where: { $0.type == "p" && $0.value == pubkey }),
                  let address = BadgeAddress(value: aTags[0].value),
                  nAward.publicKey == address.issuerPubkey else { return nil }
            return address
        }).union(profile.map { Set(badgeReferences(from: $0.toNEvent()).map(\.address)) } ?? [])
        self.addresses = Array(addresses)
        dependencyKey = addresses.map(\.value).sorted().joined(separator: ",")

        let request = Event.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let predicates = addresses.map {
            NSPredicate(
                format: "kind == %d AND pubkey == %@ AND dTag == %@ AND mostRecentId == nil",
                BadgeKinds.definition,
                $0.issuerPubkey,
                $0.identifier
            )
        }
        request.predicate = predicates.isEmpty
            ? NSPredicate(value: false)
            : NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        _definitions = FetchRequest(fetchRequest: request)

        let profileRequest = Event.fetchRequest()
        profileRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        profileRequest.fetchLimit = 500
        profileRequest.fetchBatchSize = 100
        let addressPredicates = addresses.map {
            NSPredicate(format: "tagsSerialized CONTAINS %@", "[\"a\",\"\($0.value)")
        }
        profileRequest.predicate = addressPredicates.isEmpty
            ? NSPredicate(value: false)
            : NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "kind IN {%d,%d} AND mostRecentId == nil", BadgeKinds.profile, BadgeKinds.legacyProfile),
                NSCompoundPredicate(orPredicateWithSubpredicates: addressPredicates)
            ])
        _profileBadges = FetchRequest(fetchRequest: profileRequest)

        let wearerAwardRequest = Event.fetchRequest()
        wearerAwardRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        wearerAwardRequest.fetchLimit = 500
        wearerAwardRequest.fetchBatchSize = 100
        let issuers = Set(addresses.map(\.issuerPubkey))
        wearerAwardRequest.predicate = issuers.isEmpty
            ? NSPredicate(value: false)
            : NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "kind == %d AND pubkey IN %@", BadgeKinds.award, issuers),
                NSCompoundPredicate(orPredicateWithSubpredicates: addressPredicates)
            ])
        _wearerAwards = FetchRequest(fetchRequest: wearerAwardRequest)
    }

    private var definitionsByAddress: [BadgeAddress: Event] {
        Dictionary(
            definitions.compactMap { definition in
                definition.badgeAddress.map { ($0, definition) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var candidates: [BadgeCandidate] {
        var seen = Set<BadgeAddress>()
        return awards.compactMap { award in
            let nAward = award.toNEvent()
            guard let addressValue = nAward.tags.single(where: { $0.type == "a" })?.value,
                  let address = BadgeAddress(value: addressValue),
                  seen.insert(address).inserted,
                  let definition = definitionsByAddress[address] else { return nil }
            let reference = BadgeReference(
                address: address,
                awardEventId: award.id,
                definitionRelay: definition.relays_.first,
                awardRelay: award.relays_.first
            )
            guard isValidBadge(
                reference: reference,
                profilePubkey: pubkey,
                award: nAward,
                definition: definition.toNEvent()
            ) else { return nil }
            return BadgeCandidate(reference: reference, badge: definition, award: award)
        }
    }

    private var wearerReferences: [BadgeReference] {
        profileBadges.flatMap { badgeReferences(from: $0.toNEvent()) }
            .filter { addresses.contains($0.address) }
    }

    private var wearerDependencyKey: String {
        wearerReferences.map(\.awardEventId).sorted().joined(separator: ",")
    }

    private var wearerAwardsById: [String: NEvent] {
        Dictionary(
            wearerAwards.map { ($0.id, $0.toNEvent()) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var selectedSectionTitle: String {
        String(localized: "Shown on your profile") + " · \(model.selected.count)"
    }

    private var wearerPubkeysByAddress: [BadgeAddress: [String]] {
        let pubkeysByAddress = badgeWearersByAddress(
            addresses: Set(addresses),
            profiles: profileBadges.map { $0.toNEvent() },
            awardsById: wearerAwardsById
        )
        return pubkeysByAddress.mapValues { pubkeys in
            pubkeys.sorted { lhs, rhs in
                let lhsIsFollowed = la.viewFollowingPublicKeys.contains(lhs)
                let rhsIsFollowed = la.viewFollowingPublicKeys.contains(rhs)
                if lhsIsFollowed != rhsIsFollowed { return lhsIsFollowed }
                return lhs < rhs
            }
        }
    }

    var body: some View {
        let resolvedCandidates = candidates
        let candidateByReference = Dictionary(
            uniqueKeysWithValues: resolvedCandidates.map { ($0.reference.id, $0) }
        )
        let selectedAddresses = Set(model.selected.map(\.address))
        let availableCandidates = resolvedCandidates.filter {
            !selectedAddresses.contains($0.reference.address)
        }
        let wearerSnapshot = wearerPubkeysByAddress

        List {
            Section {
                if model.selected.isEmpty {
                    Text("No badges selected for your profile")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.selected) { reference in
                        if let candidate = candidateByReference[reference.id]
                            ?? resolvedCandidates.first(where: { $0.reference.address == reference.address }) {
                            let wearerPubkeys = wearerSnapshot[reference.address] ?? []
                            BadgeReceivedRow(
                                badge: candidate.badge,
                                isSelected: true,
                                receivedAt: candidate.award.created_at,
                                wearerPubkeys: wearerPubkeys,
                                onShowWearers: { showWearers(candidate, pubkeys: wearerPubkeys) }
                            )
                            .onTapGesture { model.remove(reference) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { model.remove(reference) }
                            .accessibilityHint("Remove from your profile")
                            .listRowBackground(theme.accent.opacity(0.08))
                        } else {
                            Label(reference.address.identifier, systemImage: "seal")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: model.remove)
                    .onMove(perform: model.move)
                }
            } header: {
                Text(verbatim: selectedSectionTitle)
            } footer: {
                Text("Drag while editing to change their order.")
            }

            Section("Available badges") {
                if availableCandidates.isEmpty {
                    Text("No additional valid badge awards found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableCandidates) { candidate in
                        let wearerPubkeys = wearerSnapshot[candidate.reference.address] ?? []
                        BadgeReceivedRow(
                            badge: candidate.badge,
                            isSelected: false,
                            receivedAt: candidate.award.created_at,
                            wearerPubkeys: wearerPubkeys,
                            onShowWearers: { showWearers(candidate, pubkeys: wearerPubkeys) }
                        )
                        .onTapGesture { model.add(candidate.reference) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.add(candidate.reference) }
                        .accessibilityHint("Show on your profile")
                        .listRowBackground(theme.background)
                    }
                }
            }
        }
        .scrollContentBackgroundCompat(.hidden)
        .listStyle(.insetGrouped)
        .background(theme.listBackground)
        .toolbar {
            if model.selected.count > 1 { EditButton() }
        }
        .safeAreaInset(edge: .bottom) {
            if model.hasChanges {
                Button("Save profile badges", systemImage: "checkmark") { publishSelection() }
                    .buttonStyle(NRButtonStyle(style: .borderedProminent))
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.hasChanges)
        .task(id: dependencyKey, priority: .background) {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            let references = awards.compactMap { award -> BadgeReference? in
                guard let value = award.firstA(), let address = BadgeAddress(value: value) else { return nil }
                return BadgeReference(address: address, awardEventId: award.id, definitionRelay: nil, awardRelay: nil)
            } + (profile.map { badgeReferences(from: $0.toNEvent()) } ?? [])
            async let dependencies: Void = BadgeRelayLoader.fetchDependencies(for: references, accountPubkey: pubkey)
            async let wearers: Void = BadgeRelayLoader.fetchWearers(for: Set(addresses), accountPubkey: pubkey)
            _ = await (dependencies, wearers)
        }
        .task(id: wearerDependencyKey, priority: .background) {
            do {
                try await Task.sleep(nanoseconds: 600_000_000)
            } catch {
                return
            }
            await BadgeRelayLoader.fetchDependencies(for: wearerReferences, accountPubkey: pubkey)
        }
        .onChange(of: profile?.id) { _ in model.load(profile: profile) }
        .sheet(item: $selectedWearers) { selection in
            NBNavigationStack {
                BadgeWearersView(selection: selection)
                    .environment(\.theme, theme)
                    .environmentObject(la)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .alert("Could not publish badges", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func publishSelection() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        do {
            let signedProfile = try la.account.signEvent(createProfileBadges(references: model.selected))
            let context = bg()
            context.perform {
                _ = Event.saveEvent(event: signedProfile, context: context)
                DataProvider.shared().saveToDiskNow(.bgContext)
            }
            Unpublisher.shared.publishNow(signedProfile)
            model.markPublished(eventId: signedProfile.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showWearers(_ candidate: BadgeCandidate, pubkeys: [String]) {
        let nBadge = candidate.badge.toNEvent()
        selectedWearers = BadgeWearerSelection(
            address: candidate.reference.address,
            badgeName: nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge"),
            pubkeys: pubkeys
        )
    }
}

struct BadgeReceivedRow: View {
    @Environment(\.containerID) private var containerID

    let badge: Event
    let isSelected: Bool
    let receivedAt: Int64
    let wearerPubkeys: [String]
    let onShowWearers: () -> Void

    private var nBadge: NEvent { badge.toNEvent() }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BadgeIcon(badge: badge, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .padding(.trailing, 28)
                HStack(spacing: 3) {
                    Text("Awarded by")
                    ObservedPFP(pubkey: badge.pubkey, size: 20, forceFlat: true)
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                navigateTo(ContactPath(key: badge.pubkey), context: containerID)
                            }
                        )
                    Ago(receivedAt)
                    Text("ago")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let description = nBadge.badgeDescription?.value, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                BadgeWornBy(pubkeys: wearerPubkeys, onShowAll: onShowWearers)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .task(id: badge.pubkey) {
            QueuedFetcher.shared.enqueue(pTag: badge.pubkey)
        }
    }
}

private struct BadgeWornBy: View {
    @Environment(\.containerID) private var containerID

    let pubkeys: [String]
    let onShowAll: () -> Void

    private var visiblePubkeys: ArraySlice<String> { pubkeys.prefix(5) }

    var body: some View {
        Button(action: onShowAll) {
            HStack(alignment: .top, spacing: 4) {
                Text("Worn by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .padding(.top, 2)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(Array(visiblePubkeys), id: \.self) { pubkey in
                            ObservedPFP(pubkey: pubkey, size: 20, forceFlat: true)
                                .highPriorityGesture(
                                    TapGesture().onEnded {
                                        navigateTo(ContactPath(key: pubkey), context: containerID)
                                    }
                                )
                        }
                    }
                    if pubkeys.count > visiblePubkeys.count {
                        Text("+\(pubkeys.count - visiblePubkeys.count) others")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .buttonStyle(.plain)
        .task(id: pubkeys.joined(separator: ",")) {
            for pubkey in visiblePubkeys {
                QueuedFetcher.shared.enqueue(pTag: pubkey)
            }
        }
    }
}

private struct BadgeWearersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let selection: BadgeWearerSelection

    var body: some View {
        List {
            Section(selection.badgeName) {
                if selection.pubkeys.isEmpty {
                    Text("No verified wearers found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selection.pubkeys, id: \.self) { pubkey in
                        NBNavigationLink(value: ContactPath(key: pubkey)) {
                            PFPandName(pubkey: pubkey)
                        }
                    }
                }
            }
            .listRowBackground(theme.background)
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(theme.listBackground)
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Worn by"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
        }
    }
}

private extension Collection {
    func single(where predicate: (Element) -> Bool) -> Element? {
        let matches = filter(predicate)
        return matches.count == 1 ? matches.first : nil
    }
}
