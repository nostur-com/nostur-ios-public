//
//  BadgeDetailView.swift
//  Nostur
//

import SwiftUI
import NavigationBackport
import CoreData

struct BadgeDetailView: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.colorScheme) private var colorScheme

    let badge: Event
    @FetchRequest private var awards: FetchedResults<Event>
    @State private var isChoosingRecipients = false
    @State private var isAwarding = false
    @State private var isEditingBadge = false
    @State private var selectedAward: Event?
    @State private var newlyCreatedAwards: [Event] = []
    @State private var errorMessage: String?
    @State private var isShowingShareOptions = false
    @State private var isPreparingShareImage = false
    @State private var shareableImage: ShareablePostImage?
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
        var seen = Set<String>()
        return (newlyCreatedAwards + Array(awards))
            .filter { $0.isBadgeAward(for: address) && seen.insert($0.id).inserted }
            .sorted { $0.created_at > $1.created_at }
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
                badgeHeader
            }
            .listRowBackground(theme.background)

            Section {
                issuerRow

                if badge.pubkey == la.account.publicKey {
                    if isAwarding {
                        HStack(spacing: 12) {
                            Label("Awarding…", systemImage: "person.badge.plus")
                            Spacer()
                            ProgressView()
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Button {
                            guard isFullAccount() else { showReadOnlyMessage(); return }
                            isChoosingRecipients = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.badge.plus")
                                    .frame(width: 24)
                                Text("Award to people")
                                    .font(.body.weight(.semibold))
                                Spacer()
                            }
                            .foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(badge.badgeA == nil)
                    }
                }
            }
            .listRowBackground(theme.background)

            if !recipients.isEmpty {
                Section("Recipients") {
                    ForEach(recipients) { recipient in
                        HStack(spacing: 10) {
                            ObservedPFP(pubkey: recipient.pubkey, size: 32)
                            ContactName(pubkey: recipient.pubkey)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            BadgeRelativeTime(recipient.awardedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(ContactPath(key: recipient.pubkey), context: containerID)
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            navigateTo(ContactPath(key: recipient.pubkey), context: containerID)
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
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Share badge", systemImage: "square.and.arrow.up") {
                    isShowingShareOptions = true
                }
                .disabled(isPreparingShareImage)

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
                    doneButtonText: "Award",
                    compactRows: true,
                    onSelectContacts: award(to:)
                )
                .background(theme.listBackground)
                .navigationTitle(String(localized: "Award badge"))
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
                BadgeAwardRecipientsView(badge: badge, award: award)
                    .environment(\.theme, theme)
                    .environmentObject(la)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(item: $shareableImage) { image in
            ActivityView(activityItems: [image])
        }
        .confirmationDialog("Share badge", isPresented: $isShowingShareOptions, titleVisibility: .visible) {
            Button("Share badge in a post", systemImage: "square.and.pencil") {
                shareBadgeInPost()
            }
            if #available(iOS 16.0, *) {
                Button("Share badge as image", systemImage: "photo") {
                    Task { await shareBadgeAsImage() }
                }
            }
            Button("Cancel", role: .cancel) { }
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

    private var badgeHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            BadgeIcon(badge: badge, size: 88)

            VStack(alignment: .leading, spacing: 6) {
                Text(nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge"))
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let description = nBadge.badgeDescription?.value, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .frame(width: 18)
                    Text(recipientCountText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var issuerRow: some View {
        Button {
            navigateToContact(
                pubkey: badge.pubkey,
                nrContact: issuerContact,
                context: containerID
            )
        } label: {
            HStack(spacing: 12) {
                ObservedPFP(nrContact: issuerContact, size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Issued by")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(issuerContact.anyName)
                        .animation(.easeIn, value: issuerContact.anyName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                HStack(spacing: 3) {
                    Text("Published")
                    BadgeRelativeTime(badge.created_at)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recipientCountText: String {
        recipients.count == 1
            ? String(localized: "1 recipient")
            : String(localized: "\(recipients.count) recipients")
    }

    private func shareBadgeInPost() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let address = badge.badgeAddress,
              let identifier = try? ShareableIdentifier(
                prefix: "naddr",
                kind: Int64(BadgeKinds.definition),
                pubkey: address.issuerPubkey,
                dTag: address.identifier,
                relays: Array(resolveRelayHint(forPubkey: badge.pubkey, receivedFromRelays: badge.relays_))
              ) else { return }

        let name = nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge")
        let introduction = badge.pubkey == la.account.publicKey
            ? String(localized: "I created the “\(name)” badge.")
            : String(localized: "Check out the “\(name)” badge.")
        let text = introduction + "\n\nnostr:\(identifier.bech32string)"

        guard #available(iOS 16.0, *) else {
            AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .textNote, initialText: text)
            return
        }

        Task { @MainActor in
            guard !isPreparingShareImage else { return }
            isPreparingShareImage = true
            defer { isPreparingShareImage = false }

            let image = await renderBadgeImage()
            let issuerName = NRContact.instance(of: badge.pubkey).anyName
            let altText = String(localized: "\(name) badge issued by \(issuerName).")
            let initialImages = image.flatMap { shareCardComposerImage($0, altText: altText) }.map { [$0] } ?? []
            AppSheetsModel.shared.newPostInfo = NewPostInfo(
                kind: .textNote,
                initialText: text,
                initialImages: initialImages
            )
        }
    }

    @available(iOS 16.0, *)
    @MainActor
    private func shareBadgeAsImage() async {
        guard !isPreparingShareImage else { return }
        isPreparingShareImage = true
        defer { isPreparingShareImage = false }

        guard let image = await renderBadgeImage() else { return }
        let name = nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Badge")
        shareableImage = ShareablePostImage(
            image: image,
            title: name,
            subtitle: String(localized: "Badge")
        )
    }

    @available(iOS 16.0, *)
    @MainActor
    private func renderBadgeImage() async -> UIImage? {
        let card = ShareCardCanvas {
            BadgeDefinitionShareCard(
                badge: badge,
                recipientCountText: recipientCountText
            )
        }
        .environment(\.colorScheme, colorScheme)
        .environment(\.theme, theme)
        .environment(\.managedObjectContext, DataProvider.shared().viewContext)
        return await ShareCardRenderer.render(card)
    }

    private func awardHistoryRow(_ award: Event) -> some View {
        let count = Set(award.pTags()).count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? String(localized: "1 recipient") : String(localized: "\(count) recipients"))
                    .foregroundStyle(count == 0 ? Color.red : Color.primary)
                Text(Date(timeIntervalSince1970: Double(award.created_at)).formatted(date: .abbreviated, time: .shortened))
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
        guard !contacts.isEmpty, !isAwarding else { return }
        Task { @MainActor in
            guard let address = badge.badgeA,
                  let award = createBadgeAward(
                    definitionAddress: address,
                    pubkeys: contacts.map(\.pubkey)
                  ) else {
                errorMessage = String(localized: "This badge or its recipients are invalid.")
                return
            }

            isAwarding = true
            isChoosingRecipients = false
            defer { isAwarding = false }

            do {
                let signedAward = try la.account.signEvent(award)
                let backgroundContext = bg()
                let objectID: NSManagedObjectID = try await backgroundContext.perform {
                    let savedAward = Event.saveEvent(event: signedAward, context: backgroundContext)
                    try backgroundContext.save()
                    return savedAward.objectID
                }

                let viewContext = DataProvider.shared().viewContext
                let mainAward: Event? = await viewContext.perform {
                    try? viewContext.existingObject(with: objectID) as? Event
                }
                if let mainAward {
                    newlyCreatedAwards.removeAll { $0.id == mainAward.id }
                    newlyCreatedAwards.insert(mainAward, at: 0)
                }

                Unpublisher.shared.publishNow(signedAward)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct BadgeDefinitionShareCard: View {
    @Environment(\.theme) private var theme

    let badge: Event
    let recipientCountText: String

    private var nBadge: NEvent { badge.toNEvent() }
    private var name: String {
        nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Label("Nostr badge", systemImage: "seal.fill")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.accent)
                Spacer()
                Text(Date(timeIntervalSince1970: TimeInterval(badge.created_at)), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                BadgeIcon(badge: badge, size: 104)
                VStack(alignment: .leading, spacing: 7) {
                    Text(name)
                        .font(.title2.bold())
                        .lineLimit(3)
                    if let description = nBadge.badgeDescription?.value, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                    Label(recipientCountText, systemImage: "person.2.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Text("Issued by")
                ObservedPFP(pubkey: badge.pubkey, size: 18, forceFlat: true)
                ContactName(pubkey: badge.pubkey)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Badge dates can be years old, where a raw day count is hard to scan.
/// Keep the app's live relative timer for recent events and use calendar units for older ones.
struct BadgeRelativeTime: View {
    let timestamp: Int64

    init(_ timestamp: Int64) {
        self.timestamp = timestamp
    }

    var body: some View {
        if let calendarAge {
            Text(verbatim: calendarAge)
        } else {
            Ago(timestamp)
        }
    }

    private var calendarAge: String? {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        guard date <= Date.now else { return nil }
        let components = Calendar.current.dateComponents([.year, .month], from: date, to: Date.now)
        if let years = components.year, years > 0 {
            return "\(years)y"
        }
        if let months = components.month, months > 0 {
            return "\(months)mo"
        }
        return nil
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
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var la: LoggedInAccount
    @State private var copiedValue: String?
    @State private var isShowingShareOptions = false
    @State private var isPreparingShareImage = false
    @State private var shareableImage: ShareablePostImage?
    @State private var showsTechnicalDetails = false

    let badge: Event
    let award: Event

    private var recipientPubkeys: [String] {
        Array(Set(award.pTags().filter { $0.count == 64 })).sorted()
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    BadgeIcon(badge: badge, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(badgeName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(Date(timeIntervalSince1970: Double(award.created_at)).formatted(date: .long, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: "person.2")
                                .frame(width: 16)
                            Text(recipientCountText)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(theme.background)

            if recipientPubkeys.isEmpty {
                Section {
                    Label("This award event has no valid recipients.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(theme.background)
            } else {
                Section("Awarded to") {
                    ForEach(recipientPubkeys, id: \.self) { pubkey in
                        HStack(spacing: 10) {
                            ObservedPFP(pubkey: pubkey, size: 32)
                            ContactName(pubkey: pubkey)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(theme.background)
            }

            Section {
                DisclosureGroup("Technical details", isExpanded: $showsTechnicalDetails) {
                    copyRow(title: String(localized: "Event ID"), value: award.id)
                    if let address = award.firstA() {
                        copyRow(title: String(localized: "Badge address"), value: address)
                    }
                }
            }
            .listRowBackground(theme.background)
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(theme.listBackground)
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Award details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Share award", systemImage: "square.and.arrow.up") {
                    isShowingShareOptions = true
                }
                .disabled(isPreparingShareImage)
            }
        }
        .confirmationDialog("Share award", isPresented: $isShowingShareOptions, titleVisibility: .visible) {
            Button("Share award in a post", systemImage: "square.and.pencil") {
                shareAwardInPost()
            }
            if #available(iOS 16.0, *) {
                Button("Share award as image", systemImage: "photo") {
                    Task { await shareAwardAsImage() }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(item: $shareableImage) { image in
            ActivityView(activityItems: [image])
        }
    }

    private var badgeName: String {
        let nBadge = badge.toNEvent()
        return nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge")
    }

    private var recipientCountText: String {
        recipientPubkeys.count == 1
            ? String(localized: "1 recipient")
            : String(localized: "\(recipientPubkeys.count) recipients")
    }

    private func shareAwardInPost() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let identifier = try? ShareableIdentifier(
            prefix: "nevent",
            kind: Int64(BadgeKinds.award),
            pubkey: award.pubkey,
            eventId: award.id,
            relays: Array(resolveRelayHint(forPubkey: award.pubkey, receivedFromRelays: award.relays_))
        ) else { return }

        let count = recipientPubkeys.count
        let introduction: String
        if award.pubkey == la.account.publicKey {
            introduction = count == 1
                ? String(localized: "I awarded the “\(badgeName)” badge.")
                : String(localized: "I awarded the “\(badgeName)” badge to \(count) people.")
        } else {
            introduction = count == 1
                ? String(localized: "The “\(badgeName)” badge was awarded.")
                : String(localized: "The “\(badgeName)” badge was awarded to \(count) people.")
        }
        let text = introduction + "\n\nnostr:\(identifier.bech32string)"

        guard #available(iOS 16.0, *) else {
            AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .textNote, initialText: text)
            return
        }

        Task { @MainActor in
            guard !isPreparingShareImage else { return }
            isPreparingShareImage = true
            defer { isPreparingShareImage = false }

            let image = await renderAwardImage()
            let issuerName = NRContact.instance(of: award.pubkey).anyName
            let altText = String(localized: "\(badgeName) badge awarded by \(issuerName) to \(count) recipients.")
            let initialImages = image.flatMap { shareCardComposerImage($0, altText: altText) }.map { [$0] } ?? []
            AppSheetsModel.shared.newPostInfo = NewPostInfo(
                kind: .textNote,
                initialText: text,
                initialImages: initialImages
            )
        }
    }

    @available(iOS 16.0, *)
    @MainActor
    private func shareAwardAsImage() async {
        guard !isPreparingShareImage else { return }
        isPreparingShareImage = true
        defer { isPreparingShareImage = false }
        guard let image = await renderAwardImage() else { return }
        shareableImage = ShareablePostImage(
            image: image,
            title: badgeName,
            subtitle: String(localized: "Badge award")
        )
    }

    @available(iOS 16.0, *)
    @MainActor
    private func renderAwardImage() async -> UIImage? {
        let card = ShareCardCanvas {
            BadgeAwardShareCard(
                badge: badge,
                award: award,
                recipientPubkeys: recipientPubkeys
            )
        }
        .environment(\.colorScheme, colorScheme)
        .environment(\.theme, theme)
        .environment(\.managedObjectContext, DataProvider.shared().viewContext)
        return await ShareCardRenderer.render(card)
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
                    .foregroundStyle(copiedValue == value ? Color.green : theme.accent)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(title)")
    }
}

private struct BadgeAwardShareCard: View {
    @Environment(\.theme) private var theme

    let badge: Event
    let award: Event
    let recipientPubkeys: [String]

    private var nBadge: NEvent { badge.toNEvent() }
    private var badgeName: String {
        nBadge.badgeName?.value ?? nBadge.badgeCode?.value ?? String(localized: "Unnamed badge")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Label("Badge awarded", systemImage: "seal.fill")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.accent)
                Spacer()
                Text(Date(timeIntervalSince1970: TimeInterval(award.created_at)), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                BadgeIcon(badge: badge, size: 96)
                VStack(alignment: .leading, spacing: 7) {
                    Text(badgeName)
                        .font(.title2.bold())
                        .lineLimit(3)
                    if let description = nBadge.badgeDescription?.value, !description.isEmpty {
                        Text(description)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            recipientSummary

            HStack(spacing: 8) {
                Text("From")
                ObservedPFP(pubkey: award.pubkey, size: 18, forceFlat: true)
                ContactName(pubkey: award.pubkey)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recipientSummary: some View {
        HStack(spacing: 10) {
            if recipientPubkeys.count == 1, let pubkey = recipientPubkeys.first {
                ObservedPFP(pubkey: pubkey, size: 42, forceFlat: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Awarded to")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ContactName(pubkey: pubkey)
                        .font(.headline)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: -8) {
                    ForEach(recipientPubkeys.prefix(5), id: \.self) { pubkey in
                        ObservedPFP(pubkey: pubkey, size: 36, forceFlat: true)
                    }
                }
                Text("\(recipientPubkeys.count) recipients")
                    .font(.headline)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(theme.accent)
        }
        .padding(12)
        .background(theme.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
