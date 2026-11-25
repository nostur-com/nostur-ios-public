import SwiftUI
import Combine

@available(iOS 17.0, *)
@MainActor
struct YearReviewView: View {
    var initialYear: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.containerID) private var containerID
    @EnvironmentObject private var account: LoggedInAccount
    @Environment(\.theme) private var theme
    @State private var model = YearReviewModel.shared
    @State private var openedAccount: String?
    @State private var extraRelay = ""
    @State private var invalidRelay = false
    @State private var showDelete = false
    @State private var showInfo = false
    @State private var showRestrictedInfo = false
    @State private var showProfilePicker = false
    @State private var shareDraft: YearReviewShareDraft?
    @State private var showHistory = false
    @State private var showRefreshSources = false
    @State private var pendingSharePost: NewPostInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let profile = YearReviewProfileHeading(year: model.year,
                    showsYearToDate: model.report?.period.showsYearToDateLabel ?? (model.year == YearReviewPeriod.currentYear),
                    pubkey: model.owner.isEmpty ? account.pubkey : model.owner,
                    name: model.ownerName.isEmpty && model.owner.isEmpty ? account.account.anyName : model.ownerName,
                    picture: model.owner.isEmpty ? account.account.pictureUrl : model.ownerPicture,
                    selectProfile: { showProfilePicker = true })
                if let report = model.report, availableHighlightCount > 0 {
                    profile
                    YearReviewHighlightsView(report: report, voice: model.owner == account.pubkey ? .reader : .neutral(ownerName: model.ownerName), names: model.names, pictures: model.pictures,
                        enabledCards: model.enabledCards, hiddenPeople: model.hiddenPeople, previews: model.postPreviews, openPost: openPost, openProfile: openProfile,
                        history: YearReviewHistorySummary(model: model, openHistory: { showHistory = true }),
                        toggleCard: { card in
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                                if model.enabledCards.contains(card) { model.enabledCards.remove(card) }
                                else { model.enabledCards.insert(card) }
                            }
                        })

                    if availableHighlightCount <= 2, !model.isRunning {
                        Button { findActivity() } label: {
                            Label("Find more activity", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canRequestHistory)
                    }
                } else {
                    YearReviewFirstVisitCover(profile: profile,
                        progress: model.isDownloading ? model.progressLabel : model.savedReportProgressLabel,
                        isLoading: model.isRunning || model.isConfiguring || (openedAccount != account.pubkey && model.errorMessage == nil),
                        isDownloading: model.isDownloading,
                        hasCheckedRelays: model.lastFetchedDate != nil || model.collection != nil,
                        canRequestHistory: canRequestHistory,
                        openHistory: { showHistory = true },
                        findHighlights: findActivity,
                        chooseRelays: { showRefreshSources = true })
                }
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 650, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.listBackground)
        .navigationTitle(model.owner == account.pubkey ? Text("Your year on Nostr") : Text("\(model.ownerName)'s year on Nostr"))
        .nosturNavBgCompat(theme: theme)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showInfo = true } label: {
                    Label("About your year", systemImage: "info.circle").labelStyle(.iconOnly)
                }
                NavigationLink { optionsView } label: {
                    Label("Year settings", systemImage: "gearshape").labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { renderShare() } label: {
                    Label("Share your year", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                }
                .disabled(!hasShareableCard)
            }
        }
        .onAppear {
            YearReviewDiscovery.markOpened(owner: account.pubkey,
                year: initialYear ?? YearReviewPeriod.defaultYear())
        }
        .task(id: account.pubkey) {
            model.refreshHistoryRelayAuth()
            guard openedAccount != account.pubkey || model.viewer != account.pubkey || model.isConfiguring else { return }
            // The report owner may deliberately differ from the signed-in viewer.
            // Reopening must not reconfigure (and cancel) that owner's collection.
            let needsConfiguration = model.isConfiguring || model.viewer != account.pubkey || model.owner.isEmpty
            if needsConfiguration { await model.configure(account: account, loadSaved: false) }
            guard !Task.isCancelled, !model.isConfiguring, model.viewer == account.pubkey else { return }
            if needsConfiguration, !model.isRunning, let initialYear, model.year != initialYear {
                model.year = initialYear
                openedAccount = account.pubkey
                return // The year-change handler loads that year's saved report.
            }
            guard !Task.isCancelled else { return }
            openedAccount = account.pubkey
            model.loadSavedReportIfNeeded()
            YearReviewDiscovery.markOpened(owner: account.pubkey, year: model.year)
        }
        .onChange(of: model.year) { _, _ in
            if model.owner == account.pubkey { YearReviewDiscovery.markOpened(owner: account.pubkey, year: model.year) }
            Task { await model.selectYear() }
        }
        .onReceive(receiveNotification(.blockListUpdated).receive(on: DispatchQueue.main)) { _ in
            model.invalidatePreview()
        }
        .onReceive(ViewUpdates.shared.postDeleted.receive(on: DispatchQueue.main)) { deletion in
            model.recordDeletion(deletion.toDeleteId)
        }
        .confirmationDialog("Delete this account's collected history?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete collected history", role: .destructive) { model.deleteArchive() }
        } message: {
            Text("Your feed database and posts on relays will remain available.")
        }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                YearReviewAboutView(year: model.year, report: model.report, collection: model.reportCollection)
            }
            .presentationBackgroundCompat(theme.background)
        }
        .sheet(isPresented: $showRestrictedInfo) {
            YearReviewRestrictedContentInfoView()
                .environment(\.theme, theme)
        }
        .sheet(isPresented: $showProfilePicker) {
            NavigationStack {
                YearReviewProfilePicker(activeAccount: account.account, selectedPubkey: model.owner,
                    onSelectAccount: { selected in
                        showProfilePicker = false
                        guard selected.publicKey != model.owner else { return }
                        Task { await model.configure(account: account, reportAccount: selected) }
                    }, onSelectContact: { contact in
                        showProfilePicker = false
                        guard contact.pubkey != model.owner else { return }
                        Task { await model.configure(account: account, contact: contact) }
                    }, onDismiss: { showProfilePicker = false })
            }
            .presentationBackgroundCompat(theme.background)
        }
        .sheet(isPresented: $showHistory) {
            YearReviewHistoryView(model: model)
                .environment(\.theme, theme)
                .presentationBackgroundCompat(theme.background)
        }
        .sheet(isPresented: $showRefreshSources) {
            NavigationStack {
                YearReviewSourcesView(model: model, extraRelay: $extraRelay, invalidRelay: $invalidRelay)
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            showRefreshSources = false
                            model.start(download: true, resume: model.canResume)
                        } label: {
                            Label("Fetch from selected relays", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent).padding()
                        .background(theme.listBackground)
                        .disabled(model.selectedHistorySources.isEmpty || !canRequestHistory)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showRefreshSources = false } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss")
                        }
                    }
            }
            .environment(\.theme, theme)
        }
        .sheet(item: $shareDraft, onDismiss: {
            if let post = pendingSharePost {
                pendingSharePost = nil
                AppSheetsModel.shared.newPostInfo = post
            }
        }) { draft in
            YearReviewSharePreview(content: draft.content, colorScheme: colorScheme) { image, people in
                guard let attachment = shareCardComposerImage(image, altText: draft.caption) else { return }
                let text = people.isEmpty ? draft.caption : draft.caption + "\n\n" + String(localized: "With \(people)")
                pendingSharePost = NewPostInfo(kind: .textNote, initialText: text, initialImages: [attachment])
                shareDraft = nil
            }
            .environment(\.theme, theme)
        }
    }

    @ViewBuilder
    private var optionsView: some View {
        @Bindable var model = model
        NXForm {
            Section {
                Picker("Year", selection: $model.year) {
                    ForEach(Array((2020...YearReviewPeriod.currentYear).reversed()), id: \.self) { year in
                        Text(verbatim: String(year)).tag(year)
                    }
                }
                .disabled(model.isRunning || model.isConfiguring)
            }

            Section {
                NavigationLink {
                    YearReviewSourcesView(model: model, extraRelay: $extraRelay, invalidRelay: $invalidRelay)
                } label: {
                    Label("Relays: \(model.selectedRelays.count)", systemImage: "network")
                }
                .disabled(model.isRunning)
            } header: {
                Text("Gather your history")
            }

            Section {
                HStack(spacing: 12) {
                    Toggle("Include relay-restricted content", isOn: $model.includeRestrictedContent)
                        .disabled(model.isRunning || model.isConfiguring || model.isDeleting)
                    Button { showRestrictedInfo = true } label: {
                        Label("About relay-restricted content", systemImage: "info.circle").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Report content")
            }

            Section {
                ForEach(YearReviewCard.allCases) { card in
                    Toggle(card.title(for: model.owner == account.pubkey ? .reader : .neutral(ownerName: model.ownerName)), isOn: Binding(
                        get: { model.enabledCards.contains(card) },
                        set: { if $0 { model.enabledCards.insert(card) } else { model.enabledCards.remove(card) } }
                    ))
                }
                if let report = model.report {
                    NavigationLink {
                        YearReviewPeopleSettingsView(pubkeys: report.people.sorted(), names: model.names, hiddenPeople: $model.hiddenPeople)
                    } label: {
                        Label("People in your report", systemImage: "person.2")
                    }
                }
                if !model.hiddenPeople.isEmpty {
                    Button("Restore hidden people") { model.hiddenPeople = [] }
                }
            } header: {
                Text("Choose what to share")
            } footer: {
                Text("Only the highlights and people you choose appear in the share image.")
            }

            Section {
                Button("Export public history") { model.exportArchive() }
                    .disabled(model.isExporting || model.isRunning || model.isDeleting)
                if let url = model.exportURL {
                    ShareLink(item: url) { Label("Share history archive", systemImage: "square.and.arrow.up") }
                }
                Button("Delete collected history", role: .destructive) { showDelete = true }
                    .disabled(model.isRunning || model.isDeleting || model.isExporting)
            } header: {
                Text("History archive")
            }
        }
        .navigationTitle("Year settings")
        .nosturNavBgCompat(theme: theme)
    }

    private var availableHighlightCount: Int {
        guard let report = model.report else { return 0 }
        return YearReviewCard.allCases.filter { card in
            card.hasHighlight(in: report) || card.people(in: report).contains { !model.hiddenPeople.contains($0.pubkey) }
        }.count
    }

    private var hasShareableCard: Bool { availableHighlightCount > 0 }

    private var canRequestHistory: Bool {
        !model.owner.isEmpty && model.viewer == account.pubkey && !model.isDeleting && !model.isConfiguring && !model.isRunning
    }

    private func findActivity() {
        if model.selectedHistorySources.isEmpty {
            showRefreshSources = true
        } else {
            model.start(download: true, resume: model.canResume)
        }
    }

    private func shareCaption(_ report: YearReviewReport) -> String {
        if model.owner != AccountsState.shared.activeAccountPublicKey {
            return String(localized: "\(model.ownerName)'s nostr in \(String(report.period.year))")
        }
        return String(localized: "My nostr in \(String(report.period.year))")
    }

    private func openProfile(_ pubkey: String) {
        navigateTo(ContactPath(key: pubkey, navigationTitle: model.names[pubkey]), context: containerID)
    }

    private func openPost(_ post: YearReviewPost) {
        Task {
            do {
                let nrPost = try await model.postForNavigation(post)
                if let nrPost { navigateTo(nrPost, context: containerID) }
                else { navigateTo(NotePath(id: post.id), context: containerID) }
                try await model.loadArchivedDetails(for: post, displayedPost: nrPost)
            } catch { model.errorMessage = error.localizedDescription }
        }
    }

    private func renderShare() {
        guard let report = model.report, hasShareableCard else { return }
        let content = YearReviewShareContent(report: report,
            voice: model.owner == AccountsState.shared.activeAccountPublicKey ? .author : .neutral(ownerName: model.ownerName),
            ownerName: model.ownerName, owner: model.owner, ownerPicture: model.ownerPicture,
            names: model.names, pictures: model.pictures, enabledCards: model.enabledCards,
            hiddenPeople: model.hiddenPeople, collection: model.reportCollection, previews: model.postPreviews)
        shareDraft = YearReviewShareDraft(content: content, caption: shareCaption(report))
    }
}

enum YearReviewVoice: Equatable {
    case neutral(ownerName: String)
    case reader, author
}

enum YearReviewCard: String, CaseIterable, Identifiable, Codable {
    case gang, activeDay, polls, conversation, mostReacted, mostZapped, mostZapValue, supporters, mentions
    case mostInteracted, mostTalked, replyGuy, reactedBy, liked, zappedBy, zapped, amplifiedBy
    case returningThread, newConversations
    static let defaultSelection: Set<Self> = Set(allCases)
    var id: String { rawValue }
    static func ordered(_ cards: [Self]) -> [Self] {
        let featured: [Self] = [.activeDay, .returningThread, .newConversations, .gang, .conversation, .mostReacted, .mostZapped]
        let primary = featured.filter { cards.contains($0) }
        return primary + cards.filter { !primary.contains($0) }
    }

    static func openingHighlight(in cards: [Self], report: YearReviewReport) -> Self? {
        if report.longestPostingStreak >= 7, cards.contains(.activeDay) { return .activeDay }
        if cards.contains(.gang) { return .gang }
        if cards.contains(.mostReacted) { return .mostReacted }
        return cards.first
    }

    var title: LocalizedStringKey {
        switch self {
        case .gang: "Nostr Gang"
        case .activeDay: "Posting rhythm"
        case .polls: "Poll highlights"
        case .conversation: "Conversation starter"
        case .mostReacted: "Most-loved post"
        case .mostZapped: "Most-zapped post"
        case .mostZapValue: "Biggest lightning moment"
        case .supporters: "Top supporters"
        case .mentions: "Frequent mentions"
        case .mostInteracted: "Closest connections"
        case .mostTalked: "Public conversations"
        case .replyGuy: "Regular in the replies"
        case .reactedBy: "Biggest fans"
        case .liked: "Favorite posts"
        case .zappedBy: "Top zap senders"
        case .zapped: "Top zap recipients"
        case .amplifiedBy: "Who spread the word?"
        case .returningThread: "Still talking about it"
        case .newConversations: "Beyond the usual crowd"
        }
    }

    func title(for voice: YearReviewVoice) -> LocalizedStringKey {
        switch voice {
        case .neutral(let ownerName):
            if self == .amplifiedBy, !ownerName.isEmpty { return "Who spread \(ownerName)'s words?" }
            return title
        case .reader:
            switch self {
            case .gang: return "Your Nostr Gang"
            case .activeDay: return "Your posting rhythm"
            case .polls: return "You put it to a vote"
            case .conversation: return "You got people talking"
            case .mostReacted: return "Your most-loved post"
            case .mostZapped: return "Your most-zapped post"
            case .mostZapValue: return "Your biggest lightning moment"
            case .supporters: return "Your supporters"
            case .mentions: return "Who can't stop talking about you?"
            case .mostInteracted: return "Your closest connections"
            case .mostTalked: return "Your public conversations"
            case .replyGuy: return "Your regular in the replies"
            case .reactedBy: return "Your biggest fans"
            case .liked: return "You couldn't help reacting"
            case .zappedBy: return "Who sent you the most zaps?"
            case .zapped: return "Who you zapped the most"
            case .amplifiedBy: return "Who spread your words?"
            case .returningThread, .newConversations: return title
            }
        case .author:
            switch self {
            case .gang: return "My Nostr Gang"
            case .activeDay: return "My posting rhythm"
            case .polls: return "I put it to a vote"
            case .conversation: return "I got people talking"
            case .mostReacted: return "My most-loved post"
            case .mostZapped: return "My most-zapped post"
            case .mostZapValue: return "My biggest lightning moment"
            case .supporters: return "My supporters"
            case .mentions: return "Who can't stop talking about me?"
            case .mostInteracted: return "My closest connections"
            case .mostTalked: return "My public conversations"
            case .replyGuy: return "My regular in the replies"
            case .reactedBy: return "My biggest fans"
            case .liked: return "I couldn't help reacting"
            case .zappedBy: return "Who sent me the most zaps?"
            case .zapped: return "Who I zapped the most"
            case .amplifiedBy: return "Who spread my words?"
            case .returningThread, .newConversations: return title
            }
        }
    }

    var icon: String {
        switch self {
        case .gang, .mostInteracted: "person.3.fill"
        case .activeDay: "calendar"
        case .polls: "chart.bar.xaxis"
        case .conversation, .mostTalked, .replyGuy: "bubble.left.and.bubble.right.fill"
        case .mostReacted, .reactedBy, .liked: "heart.fill"
        case .mostZapped, .mostZapValue, .zappedBy, .zapped: "bolt.fill"
        case .supporters: "hands.clap.fill"
        case .mentions: "at"
        case .amplifiedBy: "arrow.2.squarepath"
        case .returningThread: "calendar"
        case .newConversations: "sparkles"
        }
    }
    func hasHighlight(in report: YearReviewReport) -> Bool {
        post(in: report) != nil || (self == .activeDay && report.mostActiveDay != nil) || (self == .polls && report.polls != nil)
    }

    func post(in report: YearReviewReport) -> YearReviewPost? {
        switch self {
        case .polls: report.polls?.mostVoted
        case .returningThread: report.returningThread?.post
        case .newConversations: report.newConversations?.post
        case .conversation: report.conversation
        case .mostReacted: report.mostReacted
        case .mostZapped: report.mostZapped
        case .mostZapValue: report.mostZapValue
        default: nil
        }
    }
    func people(in report: YearReviewReport) -> [YearReviewPerson] {
        switch self {
        case .gang: report.gang
        case .supporters: report.supporters
        case .mentions: [report.mentionedBy].compactMap { $0 }
        case .mostInteracted: report.mostInteracted
        case .mostTalked: report.mostTalked
        case .replyGuy: [report.topReplyGuy].compactMap { $0 }
        case .reactedBy: report.reactedBy
        case .liked: report.liked
        case .zappedBy: report.zappedBy
        case .zapped: report.zapped
        case .amplifiedBy: report.amplifiedBy
        default: []
        }
    }
}

enum YearReviewShareFormat: String, Codable { case report, gang }

@available(iOS 17.0, *)
@MainActor
private struct YearReviewProfilePicker: View {
    @Environment(\.theme) private var theme
    let activeAccount: CloudAccount
    let selectedPubkey: String
    let onSelectAccount: (CloudAccount) -> Void
    let onSelectContact: (Contact) -> Void
    let onDismiss: () -> Void
    @State private var accounts: [CloudAccount] = []

    var body: some View {
        List {
            Section("Your accounts") {
                ForEach(accounts, id: \.publicKey) { profile in
                    Button { onSelectAccount(profile) } label: {
                        HStack(spacing: 12) {
                            PFP(pubkey: profile.publicKey, account: profile, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.anyName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(theme.primary)
                                Text(profile.npub)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                                .opacity(profile.publicKey == selectedPubkey ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(profile.publicKey == selectedPubkey ? .isSelected : [])
                    .listRowBackground(theme.listBackground)
                }
            }
            Section {
                NavigationLink {
                    ContactsSearch(followingPubkeys: activeAccount.followingPubkeys,
                        prompt: "Search profiles", onSelectContact: onSelectContact)
                        .navigationTitle("Find another profile")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { dismissButton }
                        }
                } label: {
                    Label("Find another profile", systemImage: "magnifyingglass")
                }
                .listRowBackground(theme.listBackground)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackgroundHidden()
        .background(theme.background)
        .navigationTitle("Choose a profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { dismissButton }
        }
        .onAppear {
            var available = AccountsState.shared.accounts
            if !available.contains(where: { $0.publicKey == activeAccount.publicKey }) {
                available.append(activeAccount)
            }
            accounts = available.sorted { lhs, rhs in
                let leftActive = lhs.publicKey == activeAccount.publicKey
                let rightActive = rhs.publicKey == activeAccount.publicKey
                if leftActive != rightActive { return leftActive }
                if lhs.lastLoginAt != rhs.lastLoginAt { return lhs.lastLoginAt > rhs.lastLoginAt }
                return lhs.publicKey < rhs.publicKey
            }
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Label("Dismiss", systemImage: "xmark").labelStyle(.iconOnly)
        }
    }
}

private struct YearReviewProfileHeading: View {
    let year: Int
    let showsYearToDate: Bool
    let pubkey: String
    let name: String
    let picture: URL?
    var isCover = false
    let selectProfile: () -> Void

    var body: some View {
        VStack(alignment: isCover ? .center : .leading, spacing: isCover ? 12 : 6) {
            if isCover { PFP(pubkey: pubkey, pictureUrl: picture, size: 64) }
            Group {
                if showsYearToDate { Text("\(String(year)) so far") }
                else { Text(verbatim: String(year)) }
            }
            .font(isCover ? .system(.largeTitle, design: .rounded).weight(.black) : .title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
            Button(action: selectProfile) {
                HStack(spacing: 8) {
                    if !isCover { PFP(pubkey: pubkey, pictureUrl: picture, size: 40) }
                    Text(name).font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose a profile for this report")
            .accessibilityValue(name)
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewFirstVisitCover: View {
    @Environment(\.theme) private var theme
    var profile: YearReviewProfileHeading
    let progress: LocalizedStringResource
    let isLoading: Bool
    let isDownloading: Bool
    let hasCheckedRelays: Bool
    let canRequestHistory: Bool
    let openHistory: () -> Void
    let findHighlights: () -> Void
    let chooseRelays: () -> Void

    private var coverHeading: YearReviewProfileHeading {
        var heading = profile
        heading.isCover = true
        return heading
    }

    var body: some View {
        VStack(spacing: 20) {
            coverHeading
            if isLoading {
                ProgressView { Text(progress) }
                    .font(.subheadline)
                if isDownloading {
                    Button("View history", action: openHistory)
                        .buttonStyle(.bordered)
                }
            } else if hasCheckedRelays {
                Text("We didn’t find enough activity for a recap yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("View history", action: openHistory)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRequestHistory)
            } else {
                Text("Revisit the posts and conversations that made your year on Nostr.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(action: findHighlights) {
                    Label("Find my highlights", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRequestHistory)
                Button("Choose relays", action: chooseRelays)
                    .font(.footnote)
                    .disabled(!canRequestHistory)
            }
        }
        .multilineTextAlignment(.center)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
        .modifier(YearReviewCardStyle(featured: true))
        .tint(theme.accent)
    }
}

@available(iOS 17.0, *)
private struct YearReviewHistorySummary: View {
    let model: YearReviewModel
    let openHistory: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if model.isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        if !model.isDownloading { Text(model.savedReportProgressLabel) }
                        else if let activity = model.activity, YearReviewCollection.isPrimary(activity.work.category) {
                            Text("Fetching \(activity.monthName)")
                        } else { Text(model.progressLabel) }
                    }
                } else {
                    if model.report != nil && (model.archivedCounts.fromYou > 0 || model.archivedCounts.fromOthers > 0) {
                        Text("Saved report")
                    }
                    if let date = model.lastFetchedDate {
                        Text("Last fetched \(date, format: .dateTime.day().month(.abbreviated))")
                    }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: openHistory) { Label("History", systemImage: "calendar") }
                .buttonStyle(.bordered)
                .disabled(model.owner.isEmpty || model.isDeleting || model.isConfiguring)
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    let model: YearReviewModel
    @State private var selectedMonth: YearReviewMonthProgress?
    @State private var showSources = false
    @State private var showHistoryInfo = false
    @State private var extraRelay = ""
    @State private var invalidRelay = false
    @State private var monthlyCounts: [Int: Int]? = nil

    private struct CountsRequest: Hashable {
        let owner: String
        let year: Int
        let timeZone: String
        let busy: Bool
    }

    var body: some View {
        let period = model.currentPeriod
        let countsRequest = CountsRequest(owner: model.owner, year: period.year,
            timeZone: period.timeZoneIdentifier,
            busy: model.isConfiguring || model.isDeleting)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    YearReviewMonthCalendarView(collection: model.collection, period: period,
                        active: model.calendarActivity, activities: model.activeActivities,
                        savedCounts: monthlyCounts,
                        onSelect: { selectedMonth = $0 })
                    if model.isDownloading {
                        HStack(spacing: 12) {
                            Button { model.pause() } label: {
                                Label("Pause collection", systemImage: "pause.fill").labelStyle(.iconOnly)
                            }
                            .buttonStyle(.bordered)
                            ProgressView().controlSize(.small)
                            Text(model.progressLabel).font(.subheadline.weight(.semibold))
                        }
                        Button("Continue in background") { dismiss() }
                            .buttonStyle(.bordered)
                    } else if !model.isRunning {
                        YearReviewActionsView(hasHistory: model.collection != nil || model.lastFetchedDate != nil,
                            canResume: model.canResume,
                            retryFailed: !model.hasNewHistorySources && (model.collection.map { $0.pending.isEmpty && !$0.failed.isEmpty } ?? false),
                            disabled: model.isDeleting || model.viewer != AccountsState.shared.activeAccountPublicKey,
                            create: { showSources = true }, resume: { model.start(download: true, resume: true) })
                        if model.stage == .finished, model.newlySavedDuringDownload > 0 {
                            Label("\(model.newlySavedDuringDownload) new items saved", systemImage: "checkmark.circle")
                                .font(.subheadline).foregroundStyle(theme.accent)
                        }
                        if let job = model.collection, !model.hasNewHistorySources,
                           job.phase == .finished && job.pending.isEmpty && job.failed.isEmpty {
                            Text("Finished checking your selected relays.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if let job = model.collection, job.failed.contains(where: { YearReviewCollection.isPrimary($0.category) }) {
                            Text("Some relays didn’t finish. Tap an orange month for details.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let error = model.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(theme.background)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showHistoryInfo = true } label: {
                        Label("About history", systemImage: "info.circle").labelStyle(.iconOnly)
                    }
                }
            }
            .navigationDestination(isPresented: $showSources) {
                YearReviewSourcesView(model: model, extraRelay: $extraRelay, invalidRelay: $invalidRelay)
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            showSources = false
                            model.start(download: true)
                        } label: {
                            Label("Fetch from selected relays", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).padding()
                        .background(theme.listBackground)
                        .disabled(model.selectedRelays.isEmpty || model.isRunning)
                    }
            }
            .sheet(item: $selectedMonth) { month in
                YearReviewMonthActionsView(model: model, initialMonth: month, savedCounts: $monthlyCounts)
                    .environment(\.theme, theme)
            }
            .sheet(isPresented: $showHistoryInfo) {
                YearReviewHistoryInfoView(model: model)
            }
        }
        .task(id: countsRequest) {
            monthlyCounts = nil
            guard !countsRequest.busy, YearReviewEvent.isHex(countsRequest.owner, length: 64) else { return }
            let archive = await YearReviewArchives.shared.archive(owner: countsRequest.owner)
            var lastRevision: YearReviewReportRevision?
            do {
                while !Task.isCancelled {
                    let revision = try await archive.reportRevision()
                    if revision != lastRevision {
                        let counts = try await archive.monthlyArchivedCounts(year: countsRequest.year,
                            timeZone: TimeZone(identifier: countsRequest.timeZone) ?? .current)
                        try Task.checkCancellation()
                        monthlyCounts = counts
                        lastRevision = revision
                    }
                    // Pick up new local or iCloud history while this sheet is open.
                    // No relay requests; unchanged archives only need a revision read.
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                }
            } catch is CancellationError { }
            catch { L.maintenance.error("History month counts unavailable: \(error.localizedDescription)") }
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewHistoryInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let model: YearReviewModel

    var body: some View {
        NavigationStack {
            List {
                YearReviewAboutRow(title: "Missing something?", icon: "calendar",
                    detail: "Tap a month to look for more activity or retry a relay. Some older posts may no longer be available.")
                YearReviewAboutRow(title: "While gathering history", icon: "iphone",
                    detail: "You can keep using Nostur while it gathers history. If you close the app, continue later from where you left off.")
                YearReviewAboutRow(title: "What the calendar counts", icon: "number",
                    detail: "Each month shows unique saved items. While receiving data, its title shows the received count, including repeats.")
                if model.isDownloading {
                    Section("Download details") {
                        if model.activity == nil { Text(model.zapStatus ?? model.progressLabel) }
                        YearReviewCollectionProgressView(model: model)
                    }
                }
            }
            .navigationTitle("About history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Dismiss", systemImage: "xmark").labelStyle(.iconOnly)
                    }
                }
            }
        }
    }
}

private struct YearReviewActionsView: View {
    let hasHistory: Bool
    let canResume: Bool
    let retryFailed: Bool
    let disabled: Bool
    let create: () -> Void
    let resume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: canResume ? resume : create) {
                if retryFailed { Label("Retry failed sources", systemImage: "arrow.clockwise") }
                else if canResume { Label("Continue fetching", systemImage: "arrow.down.circle") }
                else if hasHistory { Label("Refresh history…", systemImage: "arrow.clockwise") }
                else { Label("Fetch history…", systemImage: "arrow.down.circle") }
            }
            .buttonStyle(.borderedProminent)
            Spacer(minLength: 0)
            if canResume {
                Button(action: create) {
                    Label("Choose relays for a new refresh", systemImage: "slider.horizontal.3").labelStyle(.iconOnly)
                }
            }
        }
        .disabled(disabled)
    }
}

private struct YearReviewPeopleSettingsView: View {
    let pubkeys: [String]
    let names: [String: String]
    @Binding var hiddenPeople: Set<String>

    var body: some View {
        NXForm {
            Section {
                ForEach(pubkeys, id: \.self) { pubkey in
                    Toggle(names[pubkey] ?? String(pubkey.prefix(12)), isOn: Binding(
                        get: { !hiddenPeople.contains(pubkey) },
                        set: { if $0 { hiddenPeople.remove(pubkey) } else { hiddenPeople.insert(pubkey) } }
                    ))
                }
            } footer: {
                Text("Choose who appears in your report and shared image.")
            }
        }
        .navigationTitle("People in your report")
    }
}

@available(iOS 17.0, *)
private struct YearReviewSourcesView: View {
    @Bindable var model: YearReviewModel
    @Binding var extraRelay: String
    @Binding var invalidRelay: Bool

    var body: some View {
        NXForm {
            Section {
                ForEach(model.relays) { relay in
                    Toggle(relay.url, isOn: Binding(
                        get: { model.selectedRelays.contains(relay.url) },
                        set: { selected in
                            if selected && model.selectedRelays.count < 20 { model.selectedRelays.insert(relay.url) }
                            else if !selected { model.selectedRelays.remove(relay.url) }
                        }
                    ))
                }
            } footer: {
                Text("Choose up to 20 relays. Relays you used before may still have older posts.")
            }
            Section {
                TextField("wss://relay.example.com", text: $extraRelay)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Add relay") {
                    invalidRelay = !model.addRelay(extraRelay.trimmingCharacters(in: .whitespacesAndNewlines))
                    if !invalidRelay { extraRelay = "" }
                }
                if invalidRelay { Text(model.relayAdditionError?.label ?? "Enter a valid ws:// or wss:// relay URL.").foregroundStyle(.secondary) }
            }
            Section {
                DisclosureGroup("Relay authentication") {
                    ForEach(model.relays) { relay in
                        Toggle(relay.url, isOn: Binding(
                            get: { model.relays.first(where: { $0.url == relay.url })?.auth ?? false },
                            set: { model.setHistoryRelayAuth(relay.url, enabled: $0) }
                        ))
                    }
                    if !model.relayAuthOverrides.isEmpty {
                        Button("Use app authentication defaults") { model.resetHistoryRelayAuth() }
                    }
                    Text("Some relays ask you to sign in. This shares the public key of the account you’re using, even when the report is about someone else.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(model.isRunning)
        .navigationTitle("History sources")
    }
}

@available(iOS 17.0, *)
private struct YearReviewRestrictedContentInfoView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Includes posts shared only with specific relays, plus replies, reactions and references to them.")
                    Text("These can appear in your report and share image. Private messages are always excluded.")
                    Text("The archive keeps this history either way. Changing the switch rebuilds your report from saved data.")
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .navigationTitle("Relay-restricted content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Dismiss", systemImage: "xmark").labelStyle(.iconOnly)
                    }
                }
            }
        }
        .presentationBackgroundCompat(theme.background)
        .presentationDetents([.medium, .large])
    }
}

private struct YearReviewAboutView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let year: Int
    let report: YearReviewReport?
    let collection: YearReviewReportCoverage?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                YearReviewAboutHero(year: year)
                YearReviewAboutGuide()
                YearReviewAboutHistory(report: report, collection: collection)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    Text("Private messages are always excluded. Relay-restricted posts and interactions are included only if you enable them in Year settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("About your year")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Label("Dismiss", systemImage: "xmark").labelStyle(.iconOnly)
                }
            }
        }
    }
}

private struct YearReviewAboutHero: View {
    @Environment(\.theme) private var theme
    let year: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Ellipse()
                    .fill(theme.accent.opacity(0.09))
                    .frame(width: 210, height: 62)
                    .rotationEffect(.degrees(-8))
                Text(verbatim: String(year))
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .tracking(-2)
                    .foregroundStyle(LinearGradient(colors: [theme.accent, theme.primary],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .rotationEffect(.degrees(12))
                    .offset(x: 98, y: -25)
                Image(systemName: "heart.fill")
                    .font(.system(size: 15))
                    .rotationEffect(.degrees(-18))
                    .offset(x: -105, y: 16)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 17))
                    .rotationEffect(.degrees(10))
                    .offset(x: 106, y: 24)
            }
            .foregroundStyle(theme.accent)
            .frame(height: 96)
            .accessibilityHidden(true)
            Text("A year worth sharing")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Your posts, your people, your standout moments.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct YearReviewAboutGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            YearReviewAboutFeature(icon: "calendar", title: "Find your moments",
                detail: "Open History to look for more posts and interactions.")
            YearReviewAboutFeature(icon: "slider.horizontal.3", title: "Choose what you want to highlight",
                detail: "Hide highlights or people, then preview your image.")
            YearReviewAboutFeature(icon: "paperplane", title: "Share your year",
                detail: "Choose Prepare post to make a draft you can edit.")
        }
    }
}

private struct YearReviewAboutFeature: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .background(theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct YearReviewAboutHistory: View {
    @Environment(\.theme) private var theme
    let report: YearReviewReport?
    let collection: YearReviewReportCoverage?

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 16) {
                if let report {
                    YearReviewCoverageView(report: report, collection: collection)
                }
                Text("You can keep using Nostur while it gathers history. If you close the app, continue later from where you left off.")
                Text("Some older posts may no longer be available.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
        } label: {
            Label("About history", systemImage: "info.circle")
                .font(.subheadline.weight(.medium))
        }
        .tint(theme.accent)
        .padding(.top, 4)
    }
}

private struct YearReviewAboutRow: View {
    @Environment(\.theme) private var theme
    let title: LocalizedStringKey
    let icon: String
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(theme.accent)
                .font(.body).frame(width: 24, height: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct YearReviewCoverageView: View {
    let report: YearReviewReport
    let collection: YearReviewReportCoverage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Activity found", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
            Text("\(report.ownPostCount) posts found · Through \(report.period.cutoffDate, format: report.period.dateFormat)")
                .font(.subheadline).foregroundStyle(.secondary)
            if collection?.phase != .finished || collection?.hasIncompleteSources != false
                || collection?.estimatedResponses ?? 0 > 0 || collection?.parentsLimited == true
                || report.unresolvedParents > 0 {
                Text("Some activity may be missing.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewHighlightsView: View {
    @State private var showMore = false
    let report: YearReviewReport
    let voice: YearReviewVoice
    let names: [String: String]
    let pictures: [String: URL]
    let enabledCards: Set<YearReviewCard>
    let hiddenPeople: Set<String>
    var previews: [String: YearReviewPostPreview] = [:]
    var openPost: ((YearReviewPost) -> Void)? = nil
    var openProfile: ((String) -> Void)? = nil
    let history: YearReviewHistorySummary
    var toggleCard: ((YearReviewCard) -> Void)? = nil

    private var visibleCards: [YearReviewCard] {
        YearReviewCard.allCases.filter { card in
            (enabledCards.contains(card) || toggleCard != nil) && (card.hasHighlight(in: report)
                || card.people(in: report).contains { !hiddenPeople.contains($0.pubkey) })
        }
    }

    private var orderedCards: [YearReviewCard] {
        YearReviewCard.ordered(visibleCards)
    }

    var body: some View {
        let lead = YearReviewCard.openingHighlight(in: orderedCards.filter { enabledCards.contains($0) }, report: report)
        let remaining = orderedCards.filter { $0 != lead }
        VStack(alignment: .leading, spacing: 16) {
            if let lead { row(lead, featured: true) }
            history
            ForEach(remaining.prefix(lead == nil ? 3 : 2)) { card in row(card) }
            let more = remaining.dropFirst(lead == nil ? 3 : 2)
            if !more.isEmpty {
                DisclosureGroup("More highlights", isExpanded: $showMore) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(more) { card in row(card) }
                    }.padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder private func row(_ card: YearReviewCard, featured: Bool = false) -> some View {
        if !enabledCards.contains(card), let toggleCard {
            YearReviewCollapsedCard(card: card, voice: voice, show: { toggleCard(card) })
                .transition(.opacity)
        } else {
            YearReviewHighlightCard(card: card, voice: voice, story: YearReviewConversationStoryContent(card: card, report: report), post: card.post(in: report), activeDay: card == .activeDay ? report.mostActiveDay : nil, averagePostsPerDay: report.averagePostsPerDay, postingRuns: YearReviewPostingRuns(streak: report.longestPostingStreak, gap: report.longestPostingBreak), pollActivity: card == .polls ? report.polls : nil, dateFormat: report.period.dateFormat,
                people: card.people(in: report).filter { !hiddenPeople.contains($0.pubkey) },
                names: names, pictures: pictures, preview: card.post(in: report).flatMap { previews[$0.id] }, openPost: openPost, openProfile: openProfile, featured: featured,
                hide: toggleCard.map { toggle in { toggle(card) } })
                .modifier(YearReviewCardStyle(featured: featured))
                .transition(.opacity)
        }
    }
}

private struct YearReviewCollapsedCard: View {
    @Environment(\.theme) private var theme
    let card: YearReviewCard
    let voice: YearReviewVoice
    let show: () -> Void

    var body: some View {
        Button(action: show) {
            HStack(spacing: 12) {
                Text(card.title(for: voice)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "eye").foregroundStyle(theme.accent)
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 18).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show \(Text(card.title(for: voice))) in your report"))
    }
}

private struct YearReviewHighlightCard: View {
    @Environment(\.theme) private var theme
    let card: YearReviewCard
    let voice: YearReviewVoice
    let story: YearReviewConversationStoryContent
    let post: YearReviewPost?
    let activeDay: YearReviewActiveDay?
    let averagePostsPerDay: Double
    let postingRuns: YearReviewPostingRuns
    let pollActivity: YearReviewPollActivity?
    let dateFormat: Date.FormatStyle
    let people: [YearReviewPerson]
    let names: [String: String]
    let pictures: [String: URL]
    let preview: YearReviewPostPreview?
    let openPost: ((YearReviewPost) -> Void)?
    let openProfile: ((String) -> Void)?
    var featured = false
    var hide: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Label { Text(card.title(for: voice)).font(featured ? .title2.bold() : .title3.bold()) } icon: {
                    Image(systemName: card.icon).foregroundStyle(theme.accent)
                }
                if let hide {
                    Spacer(minLength: 0)
                    Button(action: hide) {
                        Image(systemName: "eye.slash").foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Hide \(Text(card.title(for: voice))) from your report"))
                }
            }
            if let activeDay {
                YearReviewActiveDayContent(day: activeDay, average: averagePostsPerDay, streak: postingRuns.streak, dateFormat: dateFormat)
                postingRuns
            }
            if let pollActivity {
                YearReviewPollActivityContent(activity: pollActivity)
            }
            story
            if let post {
                if card == .polls { Text("Your most-voted poll").font(.subheadline).foregroundStyle(.secondary) }
                YearReviewPostMetric(card: card, post: post, voters: pollActivity?.mostVotedCount ?? 0)
                    .font(.system(featured ? .largeTitle : .title2, design: .rounded).weight(.black))
                    .foregroundStyle(theme.accent)
                if let openPost {
                    Button { openPost(post) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            postPreview(post)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Open highlighted post"))
                } else { postPreview(post) }
            }
            if card == .gang {
                YearReviewPeopleLineup(people: people, names: names, pictures: pictures, openProfile: openProfile)
            } else {
                ForEach(people) { person in
                    YearReviewPersonRow(person: person, name: names[person.pubkey] ?? String(npub(person.pubkey).prefix(16)) + "…",
                        picture: pictures[person.pubkey], card: card, openProfile: openProfile, hidePerson: nil)
                }
            }
        }
    }
    private func postPreview(_ post: YearReviewPost) -> some View {
        MinimalNotePreviewContent(text: preview?.text ?? post.content, thumbnail: preview?.thumbnail,
            extraCount: preview?.extraCount ?? 0, isVideo: preview?.isVideo ?? false, lineLimit: 6, textColor: .primary)
    }

}

private struct YearReviewConversationStoryContent: View {
    @Environment(\.theme) private var theme
    let card: YearReviewCard
    let report: YearReviewReport

    var body: some View {
        switch card {
        case .returningThread:
            if let thread = report.returningThread {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Replies on \(thread.activeDays.count) different days").font(.headline)
                    // Each dot is a day with a reply, not an elapsed day.
                    HStack(spacing: 4) {
                        ForEach(thread.activeDays.prefix(24), id: \.self) { _ in
                            Circle().fill(theme.accent).frame(width: 6, height: 6)
                        }
                        if thread.activeDays.count > 24 {
                            Text("+\(thread.activeDays.count - 24)").font(.caption)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        case .newConversations:
            if let story = report.newConversations {
                Text("First exchanges found with \(story.newConversations) people in this thread")
                    .font(.headline)
            }
        default: EmptyView()
        }
    }
}

private struct YearReviewPollActivityContent: View {
    let activity: YearReviewPollActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if activity.created > 0 {
                if activity.voters > 0 {
                    Text("\(activity.created) polls · \(activity.voters) voters").font(.headline)
                } else {
                    Text("\(activity.created) polls").font(.headline)
                }
            }
            if activity.votedIn > 0 {
                Text("Polls voted in: \(activity.votedIn)")
                    .font(.subheadline)
            }
        }
    }
}

private struct YearReviewPostingRuns: View {
    let streak: Int
    let gap: Int

    var body: some View {
        if (3..<7).contains(streak) || gap >= 7 {
            VStack(alignment: .leading, spacing: 8) {
                if (3..<7).contains(streak) {
                    Label("Longest posting streak: \(streak) days", systemImage: "flame")
                }
                if gap >= 7 {
                    Label("Longest break: \(gap) days between posts", systemImage: "moon.zzz")
                }
            }
            .font(.subheadline)
        }
    }
}

private struct YearReviewActiveDayContent: View {
    @Environment(\.theme) private var theme
    let day: YearReviewActiveDay
    let average: Double
    let streak: Int
    let dateFormat: Date.FormatStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if streak >= 7 {
                Text("\(streak) days")
                    .font(.system(.largeTitle, design: .rounded).weight(.black))
                    .foregroundStyle(theme.accent)
                Text("Longest posting streak").font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    ForEach(0..<min(streak, 14), id: \.self) { _ in
                        Capsule().fill(theme.accent.opacity(0.6)).frame(width: 8, height: 5)
                    }
                    if streak > 14 { Text("+\(streak - 14)").font(.caption2) }
                }
                .padding(.vertical, 5)
                .accessibilityHidden(true)
                Text("\(average, format: .number.precision(.fractionLength(1))) posts per day")
                    .font(.subheadline)
            } else {
                Text(average, format: .number.precision(.fractionLength(1)))
                    .font(.system(.largeTitle, design: .rounded).weight(.black))
                    .foregroundStyle(theme.accent)
                Text("posts per day").font(.subheadline.weight(.semibold))
            }
            Text("Busiest day: \(day.date, format: dateFormat) · \(day.posts) posts")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct YearReviewPeopleLineup: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let people: [YearReviewPerson]
    let names: [String: String]
    let pictures: [String: URL]
    let openProfile: ((String) -> Void)?

    var body: some View {
        let columns = min(max(people.count, 1), typeSize.isAccessibilitySize ? 2 : 5)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns), spacing: 14) {
            ForEach(people) { person in
                let name = names[person.pubkey] ?? String(npub(person.pubkey).prefix(10)) + "…"
                if let openProfile {
                    Button { openProfile(person.pubkey) } label: {
                        portrait(person, name: name)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Open \(name)'s profile"))
                } else {
                    portrait(person, name: name)
                }
            }
        }
    }

    private func portrait(_ person: YearReviewPerson, name: String) -> some View {
        VStack(spacing: 6) {
            PFP(pubkey: person.pubkey, pictureUrl: pictures[person.pubkey], size: 40)
            Text(name).font(.caption.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.center)
            Text("\(person.sent + person.received) replies")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct YearReviewPersonRow: View {
    @Environment(\.locale) private var locale
    let person: YearReviewPerson
    let name: String
    let picture: URL?
    let card: YearReviewCard
    let openProfile: ((String) -> Void)?
    let hidePerson: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if let openProfile {
                Button { openProfile(person.pubkey) } label: { identity }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Open \(name)'s profile"))
            } else { identity }
            Spacer(minLength: 0)
            if let hidePerson {
                Button { hidePerson(person.pubkey) } label: {
                    Label("Hide \(name) from shared cards", systemImage: "minus.circle").labelStyle(.iconOnly)
                }.buttonStyle(.borderless)
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 10) {
            PFP(pubkey: person.pubkey, pictureUrl: picture, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline).lineLimit(1)
                detail.font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var detail: some View {
        switch card {
        case .mentions: Text("Mentioned in \(person.mentions) posts")
        case .gang, .mostTalked:
            let total = person.sent + person.received
            if person.sent > 0 && person.received > 0 { Text("\(total) replies back and forth") }
            else if total > 0 { Text("\(total) replies") }
        case .replyGuy: Text("\(person.received) replies")
        case .mostInteracted: Text("\(person.interactions) public interactions")
        case .supporters:
            Text(verbatim: [
                person.reactions > 0 ? String(localized: "\(person.reactions) reactions", locale: locale) : nil,
                person.reposts > 0 ? String(localized: "\(person.reposts) reposts", locale: locale) : nil,
                person.zaps > 0 ? String(localized: "\(person.zaps) zaps", locale: locale) : nil
            ].compactMap { $0 }.joined(separator: " · "))
        case .reactedBy, .liked: Text("\(person.reactions) posts reacted to")
        case .zappedBy, .zapped:
            if person.millisats >= 1000 { Text("\(person.zaps) zaps · \((person.millisats / 1000).formatted()) sats") }
            else { Text("\(person.zaps) zaps") }
        case .amplifiedBy:
            Text(verbatim: [
                person.reposts > 0 ? String(localized: "\(person.reposts) reposts", locale: locale) : nil,
                person.quotes > 0 ? String(localized: "\(person.quotes) quotes", locale: locale) : nil
            ].compactMap { $0 }.joined(separator: " · "))
        default: EmptyView()
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewSharePreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var showSystemShare = false
    @State private var showHighlightPicker = false
    @State private var choices: Set<YearReviewCard>?
    @State private var rendered: (cards: Set<YearReviewCard>, image: UIImage)?
    @State private var renderFailed = false
    @State private var renderAttempt = 0
    @Environment(\.locale) private var locale
    let content: YearReviewShareContent
    let colorScheme: ColorScheme
    let compose: (UIImage, String) -> Void

    private struct RenderRequest: Equatable {
        let cards: Set<YearReviewCard>
        let attempt: Int
    }

    private var selected: Set<YearReviewCard> { choices ?? content.enabledCards }
    private var image: UIImage? { rendered?.cards == selected ? rendered?.image : nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    if selected.isDisjoint(with: content.shareableCards) {
                        Text("Choose at least one highlight.").padding()
                    } else {
                        if let preview = rendered?.image {
                            Image(uiImage: preview).resizable().scaledToFit()
                                .accessibilityLabel("Your year report image")
                        }
                        if renderFailed {
                            VStack(spacing: 12) {
                                Text("The share image could not be created. Please try again.")
                                Button("Try again") { renderAttempt += 1 }
                            }.padding()
                        } else if image == nil {
                            ProgressView("Preparing preview…").padding()
                        }
                    }
                }
                Button {
                    showHighlightPicker = true
                } label: {
                    Label("Choose highlights", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .padding(.top, 10)
                Button {
                    if let image { compose(image, content.mentions(for: selected, locale: locale)) }
                } label: {
                    Label("Prepare post", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).padding()
                .disabled(image == nil)
            }
            .background(theme.listBackground)
            .navigationTitle("Share your year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSystemShare = true } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share").disabled(image == nil)
                }
            }
            .sheet(isPresented: $showHighlightPicker) {
                NavigationStack {
                    List {
                        ForEach(content.shareableCards) { card in
                            Toggle(card.title(for: content.voice), isOn: Binding(
                                get: { selected.contains(card) },
                                set: { enabled in
                                    var updated = selected
                                    if enabled { updated.insert(card) } else { updated.remove(card) }
                                    choices = updated
                                }
                            ))
                        }
                    }
                    .navigationTitle("Choose highlights")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showHighlightPicker = false } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Dismiss")
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .environment(\.theme, theme)
            }
            .sheet(isPresented: $showSystemShare) {
                if let image { ActivityView(activityItems: [image]) }
            }
        }
        .task(id: RenderRequest(cards: selected, attempt: renderAttempt)) {
            let cards = selected
            renderFailed = false
            guard !cards.isDisjoint(with: content.shareableCards) else { return }
            var poster = content
            poster.cardsToRender = cards
            let image = await ShareCardRenderer.render(poster.environment(\.theme, theme).environment(\.colorScheme, colorScheme).environment(\.locale, locale))
            guard !Task.isCancelled else { return }
            if let image { rendered = (cards, image) }
            else { renderFailed = true }
        }
    }
}

private struct YearReviewShareDraft: Identifiable {
    let id = UUID()
    let content: YearReviewShareContent
    let caption: String
}

private struct YearReviewShareContent: View {
    @Environment(\.theme) private var theme
    let report: YearReviewReport
    let voice: YearReviewVoice
    let ownerName: String
    let owner: String
    let ownerPicture: URL?
    let names: [String: String]
    let pictures: [String: URL]
    let enabledCards: Set<YearReviewCard>
    var cardsToRender: Set<YearReviewCard>? = nil
    let hiddenPeople: Set<String>
    let collection: YearReviewReportCoverage?
    let previews: [String: YearReviewPostPreview]

    var body: some View {
        let cards = shareableCards.filter { (cardsToRender ?? enabledCards).contains($0) }
        let lead = YearReviewCard.openingHighlight(in: cards, report: report)
        VStack(alignment: .leading, spacing: 0) {
            YearReviewPosterHeader(year: report.period.year, ownReport: voice == .author, name: ownerName, owner: owner, picture: ownerPicture, showsYearToDateLabel: report.period.showsYearToDateLabel)
                .padding(.bottom, 24)
            if let lead {
                YearReviewPosterSection(card: lead, voice: voice, report: report, names: names, pictures: pictures,
                    hiddenPeople: hiddenPeople, previews: previews)
                    .modifier(YearReviewCardStyle(featured: true))
                    .padding(.bottom, 12)
            }
            ForEach(cards.filter { $0 != lead }) { card in
                YearReviewPosterSection(card: card, voice: voice, report: report, names: names, pictures: pictures,
                    hiddenPeople: hiddenPeople, previews: previews)
                    .padding(.vertical, 24)
                    .overlay(alignment: .top) { Rectangle().fill(theme.lineColor).frame(height: 1) }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Through \(report.period.cutoffDate, format: report.period.dateFormat)")
                    if collection == nil || collection?.phase != .finished || collection?.estimatedResponses ?? 0 > 0 || collection?.hasIncompleteSources == true || report.unresolvedParents > 0 || collection?.parentsLimited == true {
                        Text("Partial history")
                    }
                }
                .font(.system(size: 11)).foregroundStyle(theme.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(alignment: .center, spacing: 6) {
                        Text("Created with Nostur")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image("NosturLogoCreature")
                            .resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 16, height: 18)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: "nostur.com")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondary)
                }
                .multilineTextAlignment(.trailing)
            }
            .padding(.top, 20)
        }
        .padding(26)
        .frame(width: 440, alignment: .leading)
        .background {
            theme.background
            LinearGradient(colors: [theme.accent.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .foregroundStyle(theme.primary)
        .fixedSize(horizontal: false, vertical: true)
    }

    func mentions(for cards: Set<YearReviewCard>, locale: Locale) -> String {
        var seen: Set<String> = [owner, AccountsState.shared.activeAccountPublicKey]
        let mentions = shareableCards.filter { cards.contains($0) }.flatMap { card in
            card.people(in: report).compactMap { person -> String? in
                guard !hiddenPeople.contains(person.pubkey), seen.insert(person.pubkey).inserted else { return nil }
                let key = npub(person.pubkey)
                return key.hasPrefix("npub1") ? "nostr:" + key : nil
            }
        }
        return mentions.formatted(.list(type: .and).locale(locale))
    }

    var shareableCards: [YearReviewCard] {
        let cards = YearReviewCard.allCases.filter { card in
            card.hasHighlight(in: report) || card.people(in: report).contains { !hiddenPeople.contains($0.pubkey) }
        }
        return YearReviewCard.ordered(cards)
    }
}

private struct YearReviewPosterHeader: View {
    @Environment(\.theme) private var theme
    let year: Int
    let ownReport: Bool
    let name: String
    let owner: String
    let picture: URL?
    let showsYearToDateLabel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Group {
                    if ownReport { Text("My year on Nostr") }
                    else { Text("\(name)'s year on Nostr") }
                }.font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "sparkles").font(.system(size: 27, weight: .bold)).foregroundStyle(theme.accent).rotationEffect(.degrees(12))
            }
            Text(verbatim: String(year))
                .font(.system(size: 108, weight: .black, design: .rounded)).tracking(-7)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 12) {
                PFP(pubkey: owner, pictureUrl: picture, size: 42)
                Text(name).font(.system(size: 26, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            }
            if showsYearToDateLabel {
                Text("The story so far").font(.system(size: 15, weight: .medium)).foregroundStyle(theme.secondary)
            }
        }
    }
}

private struct YearReviewPosterSection: View {
    @Environment(\.theme) private var theme
    let card: YearReviewCard
    let voice: YearReviewVoice
    let report: YearReviewReport
    let names: [String: String]
    let pictures: [String: URL]
    let hiddenPeople: Set<String>
    let previews: [String: YearReviewPostPreview]

    private var people: [YearReviewPerson] { card.people(in: report).filter { !hiddenPeople.contains($0.pubkey) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: card.icon).foregroundStyle(theme.accent)
                Text(card.title(for: voice)).font(.system(size: 19, weight: .bold, design: .rounded))
            }
            YearReviewConversationStoryContent(card: card, report: report)
            if card == .gang {
                YearReviewPeopleLineup(people: people, names: names, pictures: pictures, openProfile: nil)
            } else {
                if card == .activeDay, let day = report.mostActiveDay {
                    YearReviewActiveDayContent(day: day, average: report.averagePostsPerDay, streak: report.longestPostingStreak, dateFormat: report.period.dateFormat)
                    YearReviewPostingRuns(streak: report.longestPostingStreak, gap: report.longestPostingBreak)
                }
                if card == .polls, let activity = report.polls {
                    YearReviewPollActivityContent(activity: activity)
                }
                if let post = card.post(in: report) {
                    if card != .returningThread && card != .newConversations {
                        YearReviewPostMetric(card: card, post: post, voters: report.polls?.mostVotedCount ?? 0)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(theme.accent)
                    }
                    Text(previews[post.id]?.text ?? post.content)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .lineLimit(5).lineSpacing(3)
                        .padding(.leading, 14)
                        .overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 3) }
                }
                ForEach(people) { person in
                    YearReviewPersonRow(person: person, name: names[person.pubkey] ?? String(npub(person.pubkey).prefix(16)) + "…",
                        picture: pictures[person.pubkey], card: card, openProfile: nil, hidePerson: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct YearReviewPostMetric: View {
    let card: YearReviewCard
    let post: YearReviewPost
    let voters: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch card {
            case .conversation: Text("\(post.replies) replies · \(post.respondents) people")
            case .mostReacted: Text("\(post.reactions) reactions")
            case .mostZapped: Text("\(post.zaps) zaps")
            case .mostZapValue: Text("\((post.millisats / 1000).formatted()) sats · \(post.zaps) zaps")
            case .polls: Text("\(voters) voters")
            default: EmptyView()
            }
        }
    }
}

private struct YearReviewCardStyle: ViewModifier {
    @Environment(\.theme) private var theme
    var featured = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(featured ? 22 : 18)
            .background {
                RoundedRectangle(cornerRadius: featured ? 26 : 20)
                    .fill(theme.background)
                    .overlay {
                        if featured {
                            RoundedRectangle(cornerRadius: 26)
                                .fill(LinearGradient(colors: [theme.accent.opacity(0.18), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
            }
    }
}

@available(iOS 17.0, *)
private struct YearReviewCollectionProgressView: View {
    let model: YearReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let activity = model.activity {
                if model.collection?.phase == .primary {
                    if activity.work.category == .authored {
                        Text("Your content · \(activity.monthName)")
                    } else {
                        Text("Other people’s activity · \(activity.monthName)")
                    }
                } else if activity.work.category == .parents {
                    Text("Resolving conversation references")
                } else {
                    Text("Checking references to your posts")
                }
            }
            if model.activeActivities.count > 1 {
                DisclosureGroup("\(model.activeActivities.count) relays active") {
                    YearReviewRelayProgressView(activities: model.activeActivities)
                }
            } else {
                YearReviewRelayProgressView(activities: model.activeActivities)
            }
            if model.activity != nil, let collection = model.collection {
                Text("\(collection.requestsChecked) relay queries completed · \(collection.pending.count) queued")
                    .monospacedDigit()
            }
            if model.activity != nil, let response = model.lastResponse {
                Text("Last response: \(response.received) items received · \(response.added) newly archived")
                    .monospacedDigit()
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

@available(iOS 17.0, *)
private struct YearReviewRelayProgressView: View {
    let activities: [YearReviewActivity]

    var body: some View {
        ForEach(activities, id: \.work.relay) { activity in
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.work.relay).lineLimit(1).truncationMode(.middle)
                if activity.work.category != .parents { Text(activity.dateRange) }
                TimelineView(.periodic(from: activity.startedAt, by: 1)) { timeline in
                    let seconds = max(0, Int(timeline.date.timeIntervalSince(activity.startedAt)))
                    Text("\(Text(activity.step.label)) · \(seconds)s").monospacedDigit()
                }
            }
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewMonthCalendarView: View {
    let collection: YearReviewCollection?
    let period: YearReviewPeriod
    let active: [YearReviewWork]
    let activities: [YearReviewActivity]
    let savedCounts: [Int: Int]?
    let onSelect: (YearReviewMonthProgress) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var receivingMonths: Set<Int> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: period.timeZoneIdentifier) ?? .current
        return Set(activities.compactMap { activity in
            guard activity.isReceivingMonth,
                  active.contains(activity.work) else { return nil }
            return calendar.component(.month, from: Date(timeIntervalSince1970: Double(activity.work.until)))
        })
    }

    private var months: [YearReviewMonthProgress] {
        if let collection { return Array(collection.monthProgress(active: active, received: activities.map { ($0.work, $0.received) }).reversed()) }
        let queued = YearReviewCollection(owner: "", period: period, relays: [], trusted: []).monthProgress(active: [])
            .map { month in
                var month = month
                month.own.pending = 1
                month.others.pending = 1
                return month
            }
        return Array(queued.reversed())
    }

    var body: some View {
        let receiving = receivingMonths
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(months) { month in
                    Button { onSelect(month) } label: {
                        YearReviewMonthCell(month: month, isReceiving: receiving.contains(month.month),
                            savedCount: savedCounts?[month.month])
                    }
                        .buttonStyle(.plain).disabled(!month.available)
                }
            }
            HStack(spacing: 16) {
                Label("Your content", systemImage: "checkmark.circle.fill").foregroundStyle(.orange)
                Label("Interactions", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.caption2)
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewMonthCell: View {
    let month: YearReviewMonthProgress
    let isReceiving: Bool
    let savedCount: Int?

    private var accessibilityCount: Text {
        guard month.available else { return Text("") }
        let saved = savedCount.map { Text(". Unique saved items: \($0)") }
            ?? (Text(". ") + Text("Reading saved history…"))
        if isReceiving { return saved + Text(". \(month.received) items received, including duplicates") }
        return saved
    }

    private var interactionPass: Bool { month.interactionPass }
    private var pass: YearReviewMonthProgress.Pass { month.currentPass }
    private var tint: Color { interactionPass ? .green : .orange }
    private var bothFinished: Bool { month.own.finished && month.others.finished }
    private var incomplete: Bool { month.own.failed > 0 || month.others.failed > 0 }
    private var monthStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.abbreviated)
        style.timeZone = TimeZone(identifier: month.timeZoneIdentifier) ?? .current
        return style
    }
    private var background: Color {
        guard month.available else { return .secondary.opacity(0.04) }
        if bothFinished { return .green.opacity(0.16) }
        if pass.active { return tint.opacity(0.12) }
        if month.own.finished || incomplete { return .orange.opacity(0.12) }
        return .secondary.opacity(0.08)
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if isReceiving { Text("\(month.received) received") }
                else { Text(month.date, format: monthStyle) }
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.7)
            ZStack {
                if !month.available {
                    Image(systemName: "minus").foregroundStyle(.tertiary)
                } else if pass.active {
                    ProgressView().tint(tint)
                } else if bothFinished {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if incomplete {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                } else if month.own.finished {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .frame(height: 20)
            YearReviewSavedMonthCount(available: month.available, count: savedCount)
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            ProgressView(value: month.available ? (pass.active ? pass.fraction : month.own.finished ? 1 : 0) : 0)
                .tint(bothFinished ? .green : pass.active ? tint : .orange)
                .opacity(month.available ? 1 : 0.2)
        }
        .padding(.vertical, 10).padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(background, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(month.date, format: monthStyle))
        .accessibilityValue(accessibilityStatus + accessibilityCount)
    }

    private var accessibilityStatus: Text {
        if !month.available { return Text("Outside the selected period") }
        if pass.active { return interactionPass ? Text("Fetching interactions") : Text("Fetching your content") }
        if month.own.failed > 0 || month.others.failed > 0 { return Text("Some sources remain incomplete. Tap for relay details") }
        if bothFinished { return Text("Month checked") }
        if month.own.finished { return Text("Posts checked. Interactions still to come.") }
        return Text("Queued")
    }
}

@available(iOS 17.0, *)
private struct YearReviewSavedMonthCount: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let available: Bool
    let count: Int?

    var body: some View {
        Group {
            if !available {
                Text("–")
            } else if let count {
                Text("\(count) saved")
                    .transition(.opacity)
            } else {
                Text("\(0) saved")
                    .hidden()
                    .overlay {
                        Capsule()
                            .fill(.secondary)
                            .frame(width: 52, height: 7)
                            .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, dimmed in
                                content.opacity(dimmed ? 0.12 : 0.28)
                            } animation: { _ in
                                .easeInOut(duration: 1.1)
                            }
                    }
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 14)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: count)
    }
}

@available(iOS 17.0, *)
private struct YearReviewMonthActionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: YearReviewModel
    let initialMonth: YearReviewMonthProgress
    @Binding var savedCounts: [Int: Int]?

    private var month: YearReviewMonthProgress {
        model.collection?.monthProgress(active: model.calendarActivity, received: model.activeActivities.map { ($0.work, $0.received) })
            .first { $0.month == initialMonth.month } ?? initialMonth
    }
    private var actionTitle: LocalizedStringKey {
        if model.isDownloading { return "Fetch next" }
        if model.hasNewHistorySources(in: month.month) { return "Continue month" }
        if month.own.failed + month.others.failed > 0 { return "Retry failed sources" }
        if month.own.finished && month.others.finished { return "Check for updates" }
        if month.own.completed + month.others.completed > 0 { return "Continue month" }
        return "Fetch month"
    }
    private var showsUpdateAction: Bool {
        let hasHistory = month.own.completed + month.others.completed + month.own.failed + month.others.failed > 0
        let primaryIsUpdate = month.own.finished && month.others.finished && !model.hasNewHistorySources(in: month.month)
        return hasHistory && !primaryIsUpdate
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let count = savedCounts?[month.month] {
                        LabeledContent("Saved items") { Text(count, format: .number) }
                    }
                    LabeledContent("Your content") {
                        YearReviewMonthPassStatus(pass: month.own)
                    }
                    LabeledContent("Interactions") {
                        YearReviewMonthPassStatus(pass: month.others)
                    }
                }
                Section {
                    Button {
                        model.fetchMonth(month.month)
                        dismiss()
                    } label: { Label(actionTitle, systemImage: "arrow.down.circle") }
                    .disabled(model.isRunning && (!model.isDownloading || month.own.active || month.others.active))
                    if showsUpdateAction {
                        Button {
                            model.fetchMonth(month.month, refresh: true)
                            dismiss()
                        } label: {
                            Label("Check for updates", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isRunning)
                    }
                }
                if !month.failures.isEmpty {
                    Section {
                        NavigationLink("Incomplete source details") { YearReviewIncompleteSourcesView(month: month) }
                    }
                }
                DisclosureGroup("Relay details") {
                    Text("\(month.received) items received, including duplicates").font(.caption).foregroundStyle(.secondary)
                    let sources = model.isDownloading
                        ? model.collection?.relays ?? [] : model.selectedHistorySources.map { YearReviewCollection.RelayDataSnapshot(url: $0.url, auth: $0.auth) }
                    ForEach(sources, id: \.url) { relay in
                        YearReviewMonthRelayStatus(collection: model.collection, month: month, relay: relay.url)
                    }
                }
            }
            .navigationTitle(month.date.formatted(model.currentPeriod.monthFormat))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss")
                }
            }
        }
    }
}

private struct YearReviewMonthPassStatus: View {
    let pass: YearReviewMonthProgress.Pass
    var body: some View {
        if pass.active { Text("Fetching") }
        else if pass.failed > 0 { Text("Incomplete sources").foregroundStyle(.orange) }
        else if pass.finished { Text("All selected sources finished").foregroundStyle(.green) }
        else if pass.completed > 0 { Text("Partly fetched") }
        else { Text("Not fetched") }
    }
}

private struct YearReviewMonthRelayStatus: View {
    let collection: YearReviewCollection?
    let month: YearReviewMonthProgress
    let relay: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(relay).font(.subheadline).lineLimit(2)
            if let failure = month.failures.first(where: { $0.work.relay == relay }) {
                Text(failure.reason).font(.caption).foregroundStyle(.secondary)
            } else if let collection, collection.relays.contains(where: { $0.url == relay }),
                      collection.period.contains(Int64(month.date.timeIntervalSince1970)) {
                let pending = collection.pending.filter { $0.relay == relay && collection.belongsToMonth($0, month: month.month) }
                if pending.isEmpty { Text("Month requests finished").font(.caption).foregroundStyle(.secondary) }
                else { Text("\(pending.count) month requests remaining").font(.caption).foregroundStyle(.secondary) }
            } else { Text("Not fetched").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewIncompleteSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    let month: YearReviewMonthProgress
    private let relays: [String]

    init(month: YearReviewMonthProgress) {
        self.month = month
        relays = Set(month.failures.map { $0.work.relay }).sorted()
    }

    var body: some View {
        List {
            Section {
                Label("Saved history is kept", systemImage: "checkmark.shield")
                Text("If a relay stops responding, Nostur may skip it for later months. Other relays can still finish.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(relays, id: \.self) { relay in
                YearReviewSourceFailureSection(relay: relay,
                    failures: month.failures.filter { $0.work.relay == relay },
                    timeZoneIdentifier: month.timeZoneIdentifier)
            }
        }
        .navigationTitle("Incomplete sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Label("Dismiss", systemImage: "xmark").labelStyle(.iconOnly)
                }
            }
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewSourceFailureSection: View {
    let relay: String
    let timeZoneIdentifier: String
    private let failure: YearReviewSourceFailure?
    private let failed: Int
    private let skipped: Int
    private let cooling: Int

    init(relay: String, failures: [YearReviewSourceFailure], timeZoneIdentifier: String) {
        self.relay = relay
        self.timeZoneIdentifier = timeZoneIdentifier
        failure = failures.first { $0.status == .failed || $0.status == .capped } ?? failures.first
        failed = failures.filter { $0.status == .failed || $0.status == .capped }.count
        skipped = failures.filter { $0.status == .skipped }.count
        cooling = failures.filter { $0.status == .coolingDown }.count
    }

    var body: some View {
        Section {
            if failed > 0 { Label("\(failed) requests failed in this month", systemImage: "exclamationmark.triangle") }
            if skipped > 0 { Label("\(skipped) requests skipped in this month", systemImage: "forward.end") }
            if cooling > 0 { Label("\(cooling) requests deferred for cooldown", systemImage: "clock") }
            if let failure {
                Text(failure.reason).font(.subheadline).textSelection(.enabled)
                if let trigger = failure.trigger {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Request that stopped this source").font(.caption).foregroundStyle(.secondary)
                        Text(YearReviewActivity(work: trigger, timeZoneIdentifier: timeZoneIdentifier, step: .fetching).dateRange)
                            .font(.subheadline.weight(.medium))
                        Text(requestLabel(trigger.category)).font(.subheadline)
                        if failure.status == .failed, failure.received > 0 {
                            Text("At least \(failure.received) items received before the request stopped")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if failure.date != .distantPast {
                    Text(failure.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(relay).textCase(nil)
        }
    }

    private func requestLabel(_ category: YearReviewWork.Category) -> LocalizedStringResource {
        switch category {
        case .authored: "Your posts and interactions"
        case .incoming, .supportIncoming: "Incoming replies and support"
        case .rootIncoming: "Comments on your posts"
        case .outgoingZaps: "Zaps you sent"
        case .outgoing: "Your reactions and reposts"
        case .references, .quoteReferences, .addressReferences: "References to your posts"
        case .parents: "Conversation parents"
        }
    }
}
