//
//  BadgeDetailView.swift
//  Nostur
//

import SwiftUI
import NavigationBackport

struct BadgeDetailView: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID

    let badge: Event
    @FetchRequest private var awards: FetchedResults<Event>
    @State private var isChoosingRecipients = false
    @State private var isEditingBadge = false
    @State private var selectedAward: Event?
    @State private var errorMessage: String?
    @ObservedObject private var issuerContact: NRContact

    private var nBadge: NEvent { badge.toNEvent() }

    init(badge: Event) {
        self.badge = badge
        self._issuerContact = ObservedObject(wrappedValue: NRContact.instance(of: badge.pubkey))
        let request = Event.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        if badge.badgeAddress != nil {
            request.predicate = NSPredicate(
                format: "kind == %d AND pubkey == %@",
                BadgeKinds.award,
                badge.pubkey
            )
        } else {
            request.predicate = NSPredicate(value: false)
        }
        _awards = FetchRequest(fetchRequest: request)
    }

    private var matchingAwards: [Event] {
        guard let address = badge.badgeAddress else { return [] }
        return awards.filter { $0.isBadgeAward(for: address) }
    }

    private var recipients: [BadgeRecipient] {
        var latestAwardByPubkey: [String: Int64] = [:]
        for award in matchingAwards {
            for pubkey in Set(award.pTags()) {
                latestAwardByPubkey[pubkey] = max(latestAwardByPubkey[pubkey] ?? 0, award.created_at)
            }
        }
        return latestAwardByPubkey
            .map { BadgeRecipient(pubkey: $0.key, awardedAt: $0.value) }
            .sorted { $0.awardedAt > $1.awardedAt }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {
                        BadgeIcon(badge: badge, size: 80)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge"))
                                .font(.title3.bold())
                            if let description = nBadge.badgeDescription?.value, !description.isEmpty {
                                Text(description).foregroundStyle(.secondary)
                            }
                            Text("Awarded to \(recipients.count) people")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Match embedded badge card: [pfp + name + · + ago] trailing
                    HStack(spacing: 5) {
                        Spacer()
                        ObservedPFP(nrContact: issuerContact, size: 20)
                            .onTapGesture {
                                navigateToContact(
                                    pubkey: badge.pubkey,
                                    nrContact: issuerContact,
                                    context: containerID
                                )
                            }
                        Text(issuerContact.anyName)
                            .animation(.easeIn, value: issuerContact.anyName)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fontWeightBold()
                            .lineLimit(1)
                            .onTapGesture {
                                navigateToContact(
                                    pubkey: badge.pubkey,
                                    nrContact: issuerContact,
                                    context: containerID
                                )
                            }
                        Group {
                            Text(verbatim: "·")
                            Ago(badge.created_at)
                                .equatable()
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                    .padding(.top, 8)

                    if badge.pubkey == la.account.publicKey {
                        Button("Award to people", systemImage: "person.badge.plus") {
                            guard isFullAccount() else { showReadOnlyMessage(); return }
                            isChoosingRecipients = true
                        }
                        .disabled(badge.badgeA == nil)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(theme.background)
            .listRowSeparator(.hidden)

            if !recipients.isEmpty {
                Section("Recipients") {
                    ForEach(recipients) { recipient in
                        NBNavigationLink(value: ContactPath(key: recipient.pubkey)) {
                            HStack(spacing: 8) {
                                PFPandName(pubkey: recipient.pubkey)
                                Ago(recipient.awardedAt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listRowBackground(theme.background)
            }

            if !matchingAwards.isEmpty {
                Section("Award history") {
                    ForEach(matchingAwards) { award in
                        Button {
                            selectedAward = award
                        } label: {
                            awardHistoryRow(award)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(theme.background)
            }
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(theme.listBackground)
        .listStyle(.insetGrouped)
        .navigationTitle(nBadge.badgeName?.value ?? String(localized: "Badge"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if badge.pubkey == la.account.publicKey {
                    Button("Edit badge", systemImage: "pencil") {
                        guard isFullAccount() else { showReadOnlyMessage(); return }
                        isEditingBadge = true
                    }
                }
            }
        }
        .task(id: badge.badgeA) {
            QueuedFetcher.shared.enqueue(pTag: badge.pubkey)
            guard let address = badge.badgeAddress else { return }
            await BadgeRelayLoader.fetchAwards(for: address, accountPubkey: la.account.publicKey)
        }
        .onDisappear {
            QueuedFetcher.shared.dequeue(pTag: badge.pubkey)
        }
        .sheet(isPresented: $isChoosingRecipients) {
            NBNavigationStack {
                ContactsSearch(
                    followingPubkeys: follows(),
                    prompt: "Search contacts",
                    doneButtonText: "Done",
                    onSelectContacts: award(to:)
                )
                .background(theme.listBackground)
                .navigationTitle(String(localized: "Award to"))
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.theme, theme)
                .environmentObject(la)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { isChoosingRecipients = false }
                    }
                }
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(isPresented: $isEditingBadge) {
            NBNavigationStack {
                CreateNewBadgeSheet(badge: badge)
                    .environmentObject(la)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(item: $selectedAward) { award in
            NBNavigationStack {
                BadgeAwardRecipientsView(award: award)
                    .environment(\.theme, theme)
                    .environmentObject(la)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .alert("Could not award badge", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func awardHistoryRow(_ award: Event) -> some View {
        let count = Set(award.pTags()).count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(count) recipients")
                    .foregroundStyle(count == 0 ? Color.red : Color.primary)
                Text(Date(timeIntervalSince1970: Double(award.created_at)).formatted())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func award(to contacts: Set<Contact>) {
        guard !contacts.isEmpty else { return }
        guard let address = badge.badgeA,
              let award = createBadgeAward(
                definitionAddress: address,
                pubkeys: contacts.map(\.pubkey)
              ) else {
            errorMessage = String(localized: "This badge or its recipients are invalid.")
            return
        }

        do {
            let signedAward = try la.account.signEvent(award)
            let context = bg()
            context.perform {
                _ = Event.saveEvent(event: signedAward, context: context)
                DataProvider.shared().saveToDiskNow(.bgContext)
            }
            Unpublisher.shared.publishNow(signedAward)
            isChoosingRecipients = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BadgeRecipient: Identifiable {
    let pubkey: String
    let awardedAt: Int64
    var id: String { pubkey }
}

private struct BadgeAwardRecipientsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var copiedValue: String?

    let award: Event

    private var recipientPubkeys: [String] {
        Array(Set(award.pTags().filter { $0.count == 64 })).sorted()
    }

    var body: some View {
        List {
            if recipientPubkeys.isEmpty {
                Section {
                    Label("This award event has no valid recipients.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(theme.background)
            } else {
                Section("Awarded to") {
                    ForEach(recipientPubkeys, id: \.self) { pubkey in
                        PFPandName(pubkey: pubkey)
                    }
                }
                .listRowBackground(theme.background)
            }

            Section("Event details") {
                copyRow(title: String(localized: "Event ID"), value: award.id)
                if let address = award.firstA() {
                    copyRow(title: String(localized: "Badge address"), value: address)
                }
            }
            .listRowBackground(theme.background)
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(theme.listBackground)
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Award recipients"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
        }
    }

    private func copyRow(title: String, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copiedValue = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedValue == value { copiedValue = nil }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: value)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: copiedValue == value ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copiedValue == value ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(title)")
    }
}
