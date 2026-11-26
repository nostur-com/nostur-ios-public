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
                if let report = model.report, hasShareableCard {
                    profile
                    YearReviewHighlightsView(report: report, voice: model.owner == account.pubkey ? .reader : .neutral(ownerName: model.ownerName), names: model.names, pictures: model.pictures,
                        enabledCards: model.enabledCards, hiddenPeople: model.hiddenPeople, previews: model.postPreviews, openPost: openPost, openProfile: openProfile,
                        history: YearReviewHistorySummary(model: model, openHistory: { showHistory = true }, share: renderShare),
                        toggleCard: { card in
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                                if model.enabledCards.contains(card) { model.enabledCards.remove(card) }
                                else { model.enabledCards.insert(card) }
                            }
                        })

                    if availableHighlightCount <= 2, !model.isRunning {
                        Button { showHistory = true } label: {
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
                        chooseRelays: openRelaySettings)
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
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                YearReviewAboutView(year: model.year, report: model.report, collection: model.reportCollection)
            }
            .environment(\.theme, theme)
            .presentationBackgroundCompat(theme.listBackground)
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
        .sheet(isPresented: $showHistory, onDismiss: { showRefreshSources = false }) {
            YearReviewHistoryView(model: model, opensRelaySettings: showRefreshSources)
                .environment(\.theme, theme)
                .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(item: $shareDraft, onDismiss: {
            if let post = pendingSharePost {
                pendingSharePost = nil
                AppSheetsModel.shared.newPostInfo = post
            }
        }) { draft in
            YearReviewSharePreview(content: draft.content, colorScheme: colorScheme,
                hiddenPeople: Binding(get: { model.hiddenPeople }, set: { model.hiddenPeople = $0 })) { image, people in
                guard let attachment = shareCardComposerImage(image, altText: draft.caption) else { return }
                let text = people.isEmpty ? draft.caption : draft.caption + "\n\n" + String(localized: "With \(people)")
                pendingSharePost = NewPostInfo(kind: .textNote, initialText: text, initialImages: [attachment], startsInPreview: true)
                shareDraft = nil
            }
            .environment(\.theme, theme)
            .presentationBackgroundCompat(theme.listBackground)
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
                HStack(spacing: 12) {
                    Toggle("Include limited posts", isOn: $model.includeRestrictedContent)
                        .disabled(model.isRunning || model.isConfiguring || model.isDeleting)
                    Button { showRestrictedInfo = true } label: {
                        Label("About limited posts", systemImage: "info.circle").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Report content")
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

    private var hasShareableCard: Bool {
        guard let report = model.report else { return false }
        return availableHighlightCount > 0 || !report.people.isEmpty
    }

    private var canRequestHistory: Bool {
        !model.owner.isEmpty && model.viewer == account.pubkey && !model.isDeleting && !model.isConfiguring && !model.isRunning
    }

    private func openRelaySettings() {
        showRefreshSources = true
        showHistory = true
    }

    private func findActivity() {
        if model.selectedHistorySources.isEmpty {
            openRelaySettings()
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
    case gang, activeDay, polls, articles, recipes, conversation, mostReacted, mostZapped, mostZapValue, supporters, mentions
    case mostInteracted, mostTalked, replyGuy, reactedBy, liked, zappedBy, zapped, amplifiedBy
    case returningThread, newConversations
    static let defaultSelection: Set<Self> = Set(allCases)
    var id: String { rawValue }
    static func ordered(_ cards: [Self]) -> [Self] {
        let featured: [Self] = [.activeDay, .articles, .recipes, .returningThread, .newConversations, .gang, .conversation, .mostReacted, .mostZapped]
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
        case .articles: "In their own words"
        case .recipes: "Recipes"
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

    func title(for voice: YearReviewVoice, recipeCount: Int = 0) -> LocalizedStringKey {
        if self == .recipes, recipeCount > 5 {
            switch voice {
            case .reader: return "You were cooking"
            case .author: return "I was cooking"
            case .neutral: return "A year of cooking"
            }
        }
        switch voice {
        case .neutral(let ownerName):
            if self == .amplifiedBy, !ownerName.isEmpty { return "Who spread \(ownerName)'s words?" }
            return title
        case .reader:
            switch self {
            case .gang: return "Your Nostr Gang"
            case .activeDay: return "Your posting rhythm"
            case .polls: return "You put it to a vote"
            case .articles: return "In your own words"
            case .recipes: return title
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
            case .articles: return "In my own words"
            case .recipes: return title
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
        case .articles: "book"
        case .recipes: "fork.knife"
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
        post(in: report) != nil || (self == .activeDay && report.mostActiveDay != nil) || (self == .polls && report.polls != nil) || publications(in: report) != nil
    }

    func publications(in report: YearReviewReport) -> YearReviewPublications? {
        switch self {
        case .articles: report.articles
        case .recipes: report.recipes
        default: nil
        }
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
    @State private var recents: [Contact] = []

    var body: some View {
        List {
            Section("Your accounts") {
                ForEach(accounts, id: \.publicKey) { profile in
                    profileButton(pubkey: profile.publicKey, name: profile.anyName, npubText: profile.npub, account: profile) {
                        onSelectAccount(profile)
                    }
                }
            }
            if !recents.isEmpty {
                Section("Recents") {
                    ForEach(recents, id: \.pubkey) { contact in
                        profileButton(pubkey: contact.pubkey, name: contact.anyName, npubText: contact.npub, contact: contact) {
                            YearReviewRecentProfiles.remember(contact.pubkey)
                            onSelectContact(contact)
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    ContactsSearch(followingPubkeys: activeAccount.followingPubkeys,
                        prompt: "Search profiles", onSelectContact: { contact in
                            YearReviewRecentProfiles.remember(contact.pubkey)
                            onSelectContact(contact)
                        })
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
        .onAppear(perform: loadProfiles)
    }

    private func loadProfiles() {
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
        let wanted = YearReviewRecentProfiles.visible(stored: YearReviewRecentProfiles.pubkeys(),
            accountPubkeys: Set(accounts.map(\.publicKey)))
        let found = Contact.fetchByPubkeys(wanted, context: viewContext())
        let byPubkey = Dictionary(found.map { ($0.pubkey, $0) }, uniquingKeysWith: { first, _ in first })
        recents = wanted.compactMap { byPubkey[$0] }
    }

    private func profileButton(pubkey: String, name: String, npubText: String, account: CloudAccount? = nil, contact: Contact? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PFP(pubkey: pubkey, contact: contact, account: account, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.primary)
                    Text(npubText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .foregroundStyle(theme.accent)
                    .opacity(pubkey == selectedPubkey ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(pubkey == selectedPubkey ? .isSelected : [])
        .listRowBackground(theme.listBackground)
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
            .font(isCover ? .largeTitle.bold() : .title2.weight(.semibold))
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
    let share: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(alignment: .leading, spacing: 10) { actions }
            }
            if model.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    if model.isDownloading { Text(model.progressLabel) }
                    else { Text(model.savedReportProgressLabel) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button(action: openHistory) { Label("History", systemImage: "calendar") }
            .buttonStyle(.bordered)
            .disabled(model.owner.isEmpty || model.isDeleting || model.isConfiguring)
        Button(action: share) { Label("Share your year", systemImage: "square.and.arrow.up") }
            .buttonStyle(.borderedProminent)
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

    @State private var countIndexProgress: Double?
    @State private var countsFailed = false
    @State private var countAttempt = 0

    init(model: YearReviewModel, opensRelaySettings: Bool = false) {
        self.model = model
        _showSources = State(initialValue: opensRelaySettings)
    }

    private struct CountsRequest: Hashable {
        let owner: String
        let year: Int
        let timeZone: String
        let busy: Bool
        let attempt: Int
    }

    var body: some View {
        let period = model.currentPeriod
        let countsRequest = CountsRequest(owner: model.owner, year: period.year,
            timeZone: period.timeZoneIdentifier,
            busy: model.isConfiguring || model.isDeleting, attempt: countAttempt)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    YearReviewMonthCalendarView(collection: model.collection, period: period,
                        active: model.calendarActivity,
                        savedCounts: monthlyCounts,
                        onSelect: { selectedMonth = $0 })
                    if countsFailed {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved totals are unavailable.").font(.subheadline)
                            Button("Try again") { countAttempt += 1 }
                                .buttonStyle(.bordered)
                        }
                    } else if monthlyCounts == nil, !countsRequest.busy {
                        if let countIndexProgress {
                            ProgressView(value: countIndexProgress) {
                                Text("Organizing your saved history…")
                            } currentValueLabel: {
                                Text(countIndexProgress, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        } else {
                            ProgressView("Reading saved history…").font(.subheadline)
                        }
                    }
                    if model.isDownloading {
                        YearReviewHistoryDownloadStatus(model: model)
                        Button { dismiss() } label: {
                            Text("Continue in background").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                    } else if !model.isRunning {
                        YearReviewActionsView(hasHistory: model.collection != nil || model.lastFetchedDate != nil,
                            canResume: model.canResume,
                            retryFailed: !model.hasNewHistorySources && (model.collection.map { $0.pending.isEmpty && !$0.failed.isEmpty } ?? false),
                            disabled: model.isConfiguring || model.isDeleting || model.selectedHistorySources.isEmpty
                                || model.viewer != AccountsState.shared.activeAccountPublicKey,
                            fetch: { model.start(download: true, resume: model.canResume) })
                        if model.selectedHistorySources.isEmpty {
                            Text("Choose at least one relay in Relay settings.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
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
                    VStack(spacing: 0) {
                        Button {
                            showSources = true
                        } label: {
                            YearReviewHistoryLinkLabel(title: "Relay settings", icon: "slider.horizontal.3")
                        }
                        .disabled(model.isRunning || model.isConfiguring || model.isDeleting)
                        Divider().overlay(theme.lineColor).padding(.leading, 48)
                        NavigationLink {
                            YearReviewArchiveOptions(model: model)
                        } label: {
                            YearReviewHistoryLinkLabel(title: "History archive", icon: "archivebox")
                        }
                    }
                    .buttonStyle(.plain)
                    .background(theme.background, in: RoundedRectangle(cornerRadius: 16))
                    if let error = model.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(theme.listBackground)
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
            }
            .sheet(item: $selectedMonth) { month in
                YearReviewMonthActionsView(model: model, initialMonth: month)
                    .environment(\.theme, theme)
                    .presentationBackgroundCompat(theme.listBackground)
            }
            .sheet(isPresented: $showHistoryInfo) {
                YearReviewHistoryInfoView(model: model)
                    .environment(\.theme, theme)
                    .presentationBackgroundCompat(theme.listBackground)
            }
        }
        .task(id: countsRequest) {
            monthlyCounts = nil
            countIndexProgress = nil
            countsFailed = false
            guard !countsRequest.busy, YearReviewEvent.isHex(countsRequest.owner, length: 64) else { return }
            let archive = await YearReviewArchives.shared.archive(owner: countsRequest.owner)
            var lastRevision: YearReviewReportRevision?
            do {
                while !Task.isCancelled {
                    let revision = try await archive.reportRevision()
                    if revision != lastRevision {
                        let counts = try await archive.monthlyArchivedCounts(year: countsRequest.year,
                            timeZone: TimeZone(identifier: countsRequest.timeZone) ?? .current) { fraction in
                            guard !Task.isCancelled else { return }
                            countIndexProgress = fraction
                        }
                        try Task.checkCancellation()
                        monthlyCounts = counts
                        lastRevision = revision
                    }
                    // Pick up new local or iCloud history while this sheet is open.
                    // No relay requests; unchanged archives only need a revision read.
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                }
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                countsFailed = true
                L.maintenance.error("History month counts unavailable: \(error.localizedDescription)")
            }
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewHistoryDownloadStatus: View {
    let model: YearReviewModel

    private var activeMonth: YearReviewMonthProgress? {
        let work = model.calendarActivity
        guard !work.isEmpty, let collection = model.collection else { return nil }
        let received = model.activeActivities.filter(\.isReceivingMonth).map { ($0.work, $0.received) }
        return collection.monthProgress(active: work, received: received)
            .first { $0.own.active || $0.others.active }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { model.pause() } label: {
                Label("Pause collection", systemImage: "pause.fill").labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                if let month = activeMonth {
                    Text("Fetching \(month.date, format: model.currentPeriod.monthFormat)")
                        .font(.subheadline.weight(.semibold))
                    Text("\(month.received) received")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(model.progressLabel).font(.subheadline.weight(.semibold))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewHistoryInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    let model: YearReviewModel

    var body: some View {
        NavigationStack {
            NXList {
                YearReviewAboutRow(title: "Missing something?", icon: "calendar",
                    detail: "Tap a month to look for more activity or retry a relay. Some older posts may no longer be available.")
                YearReviewAboutRow(title: "While gathering history", icon: "iphone",
                    detail: "You can keep using Nostur while it gathers history. If you close the app, continue later from where you left off.")
                YearReviewAboutRow(title: "Your content", icon: "text.bubble",
                    detail: "Posts and replies you wrote, including photos, videos, and polls you shared.")
                YearReviewAboutRow(title: "Interactions", icon: "heart",
                    detail: "Activity involving you or your posts, like mentions, replies, reactions, reposts, and zaps.")
                if model.isDownloading {
                    Section("Download details") {
                        if model.activity == nil { Text(model.zapStatus ?? model.progressLabel) }
                        YearReviewCollectionProgressView(model: model)
                    }
                }
            }
            .nosturNavBgCompat(theme: theme)
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

private struct YearReviewHistoryLinkLabel: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(theme.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(theme.primary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct YearReviewActionsView: View {
    let hasHistory: Bool
    let canResume: Bool
    let retryFailed: Bool
    let disabled: Bool
    let fetch: () -> Void

    var body: some View {
        Button(action: fetch) {
            Group {
                if retryFailed { Label("Retry failed sources", systemImage: "arrow.clockwise") }
                else if canResume { Label("Continue fetching", systemImage: "arrow.down.circle") }
                else if hasHistory { Label("Refresh history", systemImage: "arrow.clockwise") }
                else { Label("Fetch history", systemImage: "arrow.down.circle") }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
    }
}

@available(iOS 17.0, *)
private struct YearReviewArchiveOptions: View {
    let model: YearReviewModel
    @State private var showDelete = false

    var body: some View {
        NXForm {
            Section {
                Button("Export public history") { model.exportArchive() }
                    .disabled(model.isExporting || model.isRunning || model.isDeleting)
                if let url = model.exportURL {
                    ShareLink(item: url) { Label("Share history archive", systemImage: "square.and.arrow.up") }
                }
                Button("Delete collected history", role: .destructive) { showDelete = true }
                    .disabled(model.isRunning || model.isDeleting || model.isExporting)
            }
        }
        .navigationTitle("History archive")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this account's collected history?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete collected history", role: .destructive) { model.deleteArchive() }
        } message: {
            Text("Your feed database and posts on relays will remain available.")
        }
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
        .navigationTitle("Relay settings")
        .navigationBarTitleDisplayMode(.inline)
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
                    Text("Some posts are shared only on certain relays.")
                        .font(.body)
                    YearReviewAboutRow(title: "In your recap", icon: "photo",
                        detail: "Turn this on to include those posts and activity like replies and reactions. They may appear in your shared image.")
                    YearReviewAboutRow(title: "Private messages", icon: "lock",
                        detail: "Your recap never includes private messages.")
                }
                .padding(24)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(theme.listBackground)
            .nosturNavBgCompat(theme: theme)
            .navigationTitle("Limited posts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Dismiss", systemImage: "xmark").labelStyle(.iconOnly)
                    }
                }
            }
        }
        .presentationBackgroundCompat(theme.listBackground)
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
                    Text("Private messages stay out of your recap. You can include limited posts in Year settings.")
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
        .background(theme.listBackground)
        .nosturNavBgCompat(theme: theme)
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
            YearReviewHighlightCard(card: card, voice: voice, story: YearReviewConversationStoryContent(card: card, report: report), post: card.post(in: report), activeDay: card == .activeDay ? report.mostActiveDay : nil, averagePostsPerDay: report.averagePostsPerDay, postingRuns: YearReviewPostingRuns(streak: report.longestPostingStreak, gap: report.longestPostingBreak), pollActivity: card == .polls ? report.polls : nil, publications: card.publications(in: report), publicationPreviews: previews, dateFormat: report.period.dateFormat,
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
    let publications: YearReviewPublications?
    let publicationPreviews: [String: YearReviewPostPreview]
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
                Label { Text(card.title(for: voice, recipeCount: publications?.count ?? 0)).font(featured ? .title2.bold() : .title3.bold()) } icon: {
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
            if let publications {
                YearReviewPublicationContent(publications: publications, isRecipe: card == .recipes,
                    previews: publicationPreviews, open: openPost)
            }
            story
            if let post {
                if card == .polls { Text("Your most-voted poll").font(.subheadline).foregroundStyle(.secondary) }
                YearReviewPostMetric(card: card, post: post, voters: pollActivity?.mostVotedCount ?? 0)
                    .font(featured ? .largeTitle.bold() : .title2.bold())
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

private struct YearReviewPublicationContent: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let publications: YearReviewPublications
    let isRecipe: Bool
    let previews: [String: YearReviewPostPreview]
    let open: ((YearReviewPost) -> Void)?
    var posterFont: YearReviewPosterFont?

    private var accent: Color {
        guard isRecipe, posterFont == nil else { return theme.accent }
        return colorScheme == .dark ? Color(red: 1, green: 0.70, blue: 0.43)
            : Color(red: 0.63, green: 0.29, blue: 0.14)
    }

    private var countLabel: Text {
        if isRecipe {
            return publications.count == 1 ? Text("1 recipe") : Text("\(publications.count) recipes")
        }
        return publications.count == 1 ? Text("1 article") : Text("\(publications.count) articles")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                countLabel
                    .font(posterFont?.font(size: 34, weight: .bold) ?? .largeTitle.bold())
                    .foregroundStyle(accent)
                if !isRecipe, publications.words > 1 {
                    Text("About \(publications.words.formatted()) words")
                        .font(posterFont?.font(size: 14, weight: .regular) ?? .subheadline)
                        .foregroundStyle(theme.secondary)
                }
            }

            if let spotlight = publications.highlights.first {
                if isRecipe {
                    publication(spotlight, isSpotlight: true)
                        .padding(14)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    publication(spotlight, isSpotlight: true)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Capsule().fill(accent.opacity(0.55)).frame(width: 3)
                        }
                }
            }
            ForEach(publications.highlights.dropFirst()) { item in
                publication(item, isSpotlight: false)
            }
        }
    }

    @ViewBuilder private func publication(_ item: YearReviewPublication, isSpotlight: Bool) -> some View {
        let label = YearReviewPublicationLabel(title: item.title,
            thumbnail: isSpotlight ? previews[item.id]?.thumbnail : nil,
            recipeAccent: isRecipe ? accent : nil, featured: isSpotlight,
            isLink: open != nil, posterFont: posterFont)
        if let open {
            Button { open(item.post) } label: { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }
}

private struct YearReviewPublicationLabel: View {
    @Environment(\.theme) private var theme
    let title: String
    let thumbnail: URL?
    let recipeAccent: Color?
    let featured: Bool
    let isLink: Bool
    let posterFont: YearReviewPosterFont?

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail {
                MinimalMediaThumbnail(url: thumbnail, extraCount: 0, isVideo: false)
                    .accessibilityHidden(true)
            } else if featured, let recipeAccent {
                Image(systemName: "fork.knife")
                    .font(.title3)
                    .foregroundStyle(recipeAccent)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(posterFont?.font(size: featured ? 21 : 15, weight: featured ? .bold : .regular)
                    ?? (featured ? .title3.weight(.semibold) : .subheadline))
                .foregroundStyle(theme.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isLink {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
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
    var posterFont: YearReviewPosterFont? = nil

    private var cadence: (value: Double, unit: LocalizedStringKey) {
        if average >= 1 { return (average, "posts per day") }
        let weekly = average * 7
        if weekly >= 1 { return (weekly, "posts per week") }
        return (average * (365.2425 / 12), "posts per month")
    }

    var body: some View {
        let (value, unit) = cadence
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(value > 0 && value < 0.1 ? 2 : 1))
        VStack(alignment: .leading, spacing: 4) {
            if streak >= 7 {
                Text("\(streak) days")
                    .font(posterFont?.font(size: 36, weight: .black) ?? .largeTitle.bold())
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
                Text("\(value, format: format) \(Text(unit))")
                    .font(.subheadline)
            } else {
                Text(value, format: format)
                    .font(posterFont?.font(size: 36, weight: .black) ?? .largeTitle.bold())
                    .foregroundStyle(theme.accent)
                Text(unit).font(.subheadline.weight(.semibold))
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

private enum YearReviewPosterTheme: String, CaseIterable, Identifiable {
    case nostur, newsprint, electric, cobalt, rose, hashtagNostr

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .nostur: "Nostur"
        case .hashtagNostr: "nostr protocol"
        case .newsprint: "Newsprint"
        case .electric: "Electric"
        case .cobalt: "Cobalt"
        case .rose: "Rose Quartz"
        }
    }

    func palette(using appTheme: Theme) -> Theme {
        switch self {
        case .nostur: appTheme
        case .hashtagNostr: palette(background: 0x16202A, surface: 0x22303D, ink: 0xF3F8FC, muted: 0xBCCFDE, accent: 0x70C9F8)
        case .newsprint: palette(background: 0xF5EFE3, surface: 0xEBE2D1, ink: 0x23211D, muted: 0x514C44, accent: 0x962B22)
        case .electric: palette(background: 0x171821, surface: 0x25293A, ink: 0xF7FAE7, muted: 0xCCD1B8, accent: 0xE2FD47)
        case .cobalt: palette(background: 0x102DA8, surface: 0x1739BD, ink: 0xFFFFFF, muted: 0xDAE5FF, accent: 0x9EEFFF)
        case .rose: palette(background: 0xFBE8ED, surface: 0xF4D4DD, ink: 0x49213A, muted: 0x70485E, accent: 0x983754)
        }
    }

    var mark: String? {
        switch self {
        case .nostur: "sparkles"
        case .hashtagNostr: nil
        case .newsprint: "asterisk"
        case .electric: "bolt.fill"
        case .cobalt: "plus"
        case .rose: "circle.hexagongrid.fill"
        }
    }

    private func palette(background: UInt32, surface: UInt32, ink: UInt32, muted: UInt32, accent: UInt32) -> Theme {
        var result = Theme()
        result.id = "year-review-" + rawValue
        result.background = color(background)
        result.secondaryBackground = color(surface)
        result.primary = color(ink)
        result.secondary = color(muted)
        result.accent = color(accent)
        result.lineColor = result.primary.opacity(0.2)
        return result
    }

    private func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 0xff) / 255,
              green: Double((rgb >> 8) & 0xff) / 255,
              blue: Double(rgb & 0xff) / 255)
    }
}

private enum YearReviewPosterFont: String, CaseIterable, Identifiable {
    case didot, gillSans, condensed, rockwell, mono

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .didot: "Didot"
        case .gillSans: "Gill Sans"
        case .condensed: "Helvetica Condensed"
        case .rockwell: "Rockwell"
        case .mono: "Monospace"
        }
    }

    var design: Font.Design {
        switch self {
        case .didot, .rockwell: .serif
        case .gillSans, .condensed: .default
        case .mono: .monospaced
        }
    }

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        let regular = weight == .regular
        let face: String
        switch self {
        case .didot: face = regular ? "Didot" : "Didot-Bold"
        case .gillSans: face = regular ? "GillSans" : "GillSans-SemiBold"
        case .condensed: face = "HelveticaNeue-CondensedBold"
        case .rockwell: face = regular ? "Rockwell-Regular" : "Rockwell-Bold"
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        }
        if UIFont(name: face, size: size) != nil {
            return .custom(face, fixedSize: size)
        }
        return .system(size: size, weight: weight, design: design)
    }
}

@available(iOS 17.0, *)
private struct YearReviewSharePreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @AppStorage("year-review-poster-theme") private var posterTheme = YearReviewPosterTheme.nostur
    @AppStorage("year-review-poster-font") private var posterFont = YearReviewPosterFont.didot
    @State private var showSystemShare = false
    @State private var showHighlightPicker = false
    @State private var choices: Set<YearReviewCard>?
    @State private var rendered: (request: RenderRequest, image: UIImage)?
    @State private var renderFailed = false
    @State private var renderAttempt = 0
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: YearReviewShareContent
    let colorScheme: ColorScheme
    @Binding var hiddenPeople: Set<String>
    let compose: (UIImage, String) -> Void

    private struct RenderRequest: Equatable {
        let cards: Set<YearReviewCard>
        let hiddenPeople: Set<String>
        let theme: YearReviewPosterTheme
        let font: YearReviewPosterFont
        let attempt: Int
    }

    private var selected: Set<YearReviewCard> { choices ?? content.enabledCards }
    private var request: RenderRequest {
        RenderRequest(cards: selected, hiddenPeople: hiddenPeople, theme: posterTheme, font: posterFont, attempt: renderAttempt)
    }
    private var image: UIImage? { rendered?.request == request ? rendered?.image : nil }
    private var currentContent: YearReviewShareContent {
        var poster = content
        poster.hiddenPeople = hiddenPeople
        return poster
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Theme", selection: $posterTheme) {
                ForEach(YearReviewPosterTheme.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            Picker("Font", selection: $posterFont) {
                ForEach(YearReviewPosterFont.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            Button { showHighlightPicker = true } label: {
                Label("Choose what to share", systemImage: "checklist")
            }
            Divider()
            Button { showSystemShare = true } label: {
                Label("Share image", systemImage: "square.and.arrow.up")
            }
            .disabled(image == nil)
        } label: {
            Label("Options", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
        }
    }

    private var imageArrival: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if selected.isDisjoint(with: currentContent.shareableCards) {
                    Text("Choose at least one highlight.").padding()
                } else if renderFailed {
                    VStack(spacing: 12) {
                        Text("The share image could not be created. Please try again.")
                        Button("Try again") { renderAttempt += 1 }
                    }.padding()
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .accessibilityLabel("Your year report image")
                        .transition(.asymmetric(insertion: imageArrival, removal: .opacity))
                } else {
                    YearReviewSharePreparing(year: content.report.period.year, name: content.ownerName,
                        ownReport: content.voice == .author, font: posterFont)
                        .environment(\.theme, posterTheme.palette(using: theme))
                        .transition(.opacity)
                }
            }
            .animation(.spring(duration: 0.72, bounce: reduceMotion ? 0 : 0.08), value: image != nil)
            .scrollContentBackground(.hidden)
            .background(theme.listBackground)
            .navigationTitle("Share your year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.listBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss")
                }
                ToolbarItem(placement: .primaryAction) { optionsMenu }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let image { compose(image, currentContent.mentions(for: selected, locale: locale)) }
                    } label: {
                        Label("Prepare post", systemImage: "square.and.pencil").labelStyle(.iconOnly)
                    }
                    .disabled(image == nil)
                }
            }
            .sheet(isPresented: $showHighlightPicker) {
                NavigationStack {
                    List {
                        Section {
                            ForEach(currentContent.shareableCards) { card in
                                Toggle(card.title(for: content.voice), isOn: Binding(
                                    get: { selected.contains(card) },
                                    set: { enabled in
                                        var updated = selected
                                        if enabled { updated.insert(card) } else { updated.remove(card) }
                                        choices = updated
                                    }
                                ))
                            }
                        } header: {
                            Text("Highlights")
                        }
                        if !content.report.people.isEmpty {
                            Section {
                                NavigationLink {
                                    YearReviewPeopleSettingsView(pubkeys: content.report.people.sorted(),
                                        names: content.names, hiddenPeople: $hiddenPeople)
                                } label: {
                                    Label("People in your report", systemImage: "person.2")
                                }
                                if !hiddenPeople.isEmpty {
                                    Button("Restore hidden people") { hiddenPeople = [] }
                                }
                            }
                        }
                    }
                    .navigationTitle("Choose what to share")
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
        .background(theme.listBackground.ignoresSafeArea())
        .presentationBackgroundCompat(theme.listBackground)
        .task(id: request) { [request] in
            let cards = request.cards
            renderFailed = false
            var poster = content
            poster.hiddenPeople = request.hiddenPeople
            guard !cards.isDisjoint(with: poster.shareableCards) else { return }
            poster.cardsToRender = cards
            poster.font = request.font
            poster.appearance = request.theme
            let palette = request.theme.palette(using: theme)
            let image = await ShareCardRenderer.render(poster
                .environment(\.theme, palette)
                .environment(\.colorScheme, colorScheme)
                .environment(\.locale, locale), maximumPixelDimension: 8192)
            guard !Task.isCancelled else { return }
            if let image {
                withAnimation(.spring(duration: 0.72, bounce: reduceMotion ? 0 : 0.08)) {
                    rendered = (request, image)
                }
            } else {
                renderFailed = true
            }
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewSharePreparing: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let year: Int
    let name: String
    let ownReport: Bool
    let font: YearReviewPosterFont

    var body: some View {
        Group {
            if reduceMotion {
                poster(sweep: 1)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let cycle = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.2) / 2.2
                    poster(sweep: cycle)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing preview…")
    }

    private var yearFont: Font { font.font(size: 92, weight: .black) }

    private func poster(sweep: Double) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.background)
            LinearGradient(colors: [theme.accent.opacity(0.2), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            sheen(sweep: sweep)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Group {
                        if ownReport { Text("My year on Nostr") }
                        else { Text("\(name)'s year on Nostr") }
                    }
                    .font(font.font(size: 16, weight: .bold))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(2)
                    Spacer(minLength: 0)
                    Image("NosturLogoCreature")
                        .resizable().renderingMode(.template).scaledToFit()
                        .frame(width: 20, height: 24)
                        .foregroundStyle(theme.accent)
                        .offset(y: reduceMotion ? 0 : CGFloat(sin(sweep * .pi * 2)) * -4)
                        .accessibilityHidden(true)
                }
                Text(verbatim: String(year))
                    .font(yearFont)
                    .tracking(font == .mono ? -3 : -6)
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(0.35 + 0.65 * min(sweep / 0.35, 1))
                if !name.isEmpty {
                    Text(name)
                        .font(font.font(size: 24, weight: .bold))
                        .foregroundStyle(theme.primary)
                        .lineLimit(2)
                        .opacity(sweep > 0.12 ? 1 : 0.35)
                }
                VStack(alignment: .leading, spacing: 16) {
                    printedLine(fraction: lineFraction(sweep, lead: 0.08))
                    printedLine(fraction: lineFraction(sweep, lead: 0.24))
                    printedLine(fraction: lineFraction(sweep, lead: 0.4))
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
            }
            .padding(26)
        }
        .containerRelativeFrame(.horizontal) { length, _ in min(max(length - 36, 240), 420) }
        .frame(height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(theme.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: theme.accent.opacity(0.16), radius: 26, y: 14)
    }

    private func sheen(sweep: Double) -> some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, theme.accent.opacity(0.28), .clear],
                startPoint: .top, endPoint: .bottom)
                .frame(height: geo.size.height * 0.3)
                .offset(y: -geo.size.height * 0.3 + CGFloat(sweep) * geo.size.height * 1.3)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lineFraction(_ sweep: Double, lead: Double) -> CGFloat {
        CGFloat(min(max((sweep - lead) / 0.42, 0), 1))
    }

    private func printedLine(fraction: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(theme.accent.opacity(0.55))
                .frame(width: max(geo.size.width * fraction, fraction > 0 ? 8 : 0), height: 2)
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(iOS 17.0, *)
private struct YearReviewShareDraft: Identifiable {
    let id = UUID()
    let content: YearReviewShareContent
    let caption: String
}

@available(iOS 17.0, *)
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
    var appearance = YearReviewPosterTheme.nostur
    var font = YearReviewPosterFont.didot
    var cardsToRender: Set<YearReviewCard>? = nil
    var hiddenPeople: Set<String>
    let collection: YearReviewReportCoverage?
    let previews: [String: YearReviewPostPreview]

    var body: some View {
        let cards = shareableCards.filter { (cardsToRender ?? enabledCards).contains($0) }
        let lead = YearReviewCard.openingHighlight(in: cards, report: report)
        VStack(alignment: .leading, spacing: 0) {
            YearReviewPosterHeader(year: report.period.year, ownReport: voice == .author, name: ownerName, owner: owner, picture: ownerPicture, showsYearToDateLabel: report.period.showsYearToDateLabel, font: font, mark: appearance.mark)
                .padding(.bottom, 24)
            if let lead {
                YearReviewPosterSection(card: lead, voice: voice, report: report, names: names, pictures: pictures,
                    hiddenPeople: hiddenPeople, previews: previews, font: font)
                    .padding(22)
                    .background(theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 26))
                    .padding(.bottom, 12)
            }
            ForEach(cards.filter { $0 != lead }) { card in
                YearReviewPosterSection(card: card, voice: voice, report: report, names: names, pictures: pictures,
                    hiddenPeople: hiddenPeople, previews: previews, font: font)
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
                .font(font.font(size: 11, weight: .regular)).foregroundStyle(theme.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(alignment: .center, spacing: 6) {
                        Text("Created with Nostur")
                            .font(font.font(size: 12, weight: .semibold))
                        Image("NosturLogoCreature")
                            .resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 16, height: 18)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: "nostur.com")
                        .font(font.font(size: 10, weight: .regular))
                        .foregroundStyle(theme.secondary)
                }
                .multilineTextAlignment(.trailing)
            }
            .padding(.top, 20)
        }
        .padding(26)
        .frame(width: 440, alignment: .leading)
        .background {
            YearReviewPosterBackdrop(appearance: appearance)
        }
        .foregroundStyle(theme.primary, theme.secondary)
        .fontDesign(font.design)
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

private struct YearReviewPosterBackdrop: View {
    @Environment(\.theme) private var theme
    let appearance: YearReviewPosterTheme

    var body: some View {
        ZStack(alignment: .top) {
            theme.background
            switch appearance {
            case .nostur:
                LinearGradient(colors: [theme.accent.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .hashtagNostr:
                Rectangle().fill(theme.accent).frame(height: 6)
            case .newsprint:
                VStack {
                    Rectangle().fill(theme.accent).frame(height: 4)
                    Spacer()
                    Rectangle().fill(theme.primary).frame(height: 1)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
            case .electric:
                Canvas { context, size in
                    var slash = Path()
                    slash.move(to: CGPoint(x: size.width * 0.74, y: 0))
                    slash.addLine(to: CGPoint(x: size.width, y: 0))
                    slash.addLine(to: CGPoint(x: size.width, y: size.height * 0.54))
                    slash.addLine(to: CGPoint(x: size.width * 0.48, y: size.height))
                    slash.closeSubpath()
                    context.fill(slash, with: .color(theme.accent.opacity(0.2)))
                }
                .frame(height: 255)
            case .cobalt:
                Canvas { context, size in
                    var grid = Path()
                    for x in stride(from: CGFloat(0), to: size.width, by: 24) {
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: CGFloat(0), to: size.height, by: 24) {
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(theme.accent.opacity(0.18)), lineWidth: 0.75)
                }
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .frame(height: 380)
            case .rose:
                Canvas { context, size in
                    let upper = CGRect(x: size.width * 0.58, y: -95, width: 290, height: 290)
                    let lower = CGRect(x: size.width * 0.44, y: -30, width: 310, height: 310)
                    context.fill(Path(ellipseIn: lower), with: .color(theme.accent.opacity(0.10)))
                    context.stroke(Path(ellipseIn: upper), with: .color(theme.accent.opacity(0.28)), lineWidth: 2)
                }
                .frame(height: 290)
            }
        }
        .accessibilityHidden(true)
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
    let font: YearReviewPosterFont
    let mark: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Group {
                    if ownReport { Text("My year on Nostr") }
                    else { Text("\(name)'s year on Nostr") }
                }.font(font.font(size: 16, weight: .bold))
                Spacer()
                if let mark {
                    Image(systemName: mark)
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .rotationEffect(.degrees(12))
                } else {
                    Image("HashtagNostr")
                        .resizable().renderingMode(.original).scaledToFit()
                        .frame(width: 40, height: 40)
                        .overlay { Rectangle().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1) }
                        .accessibilityHidden(true)
                }
            }
            Text(verbatim: String(year))
                .font(font.font(size: 108, weight: .black)).tracking(font == .mono ? -3 : -7)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 12) {
                PFP(pubkey: owner, pictureUrl: picture, size: 42)
                Text(name).font(font.font(size: 26, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            }
            if showsYearToDateLabel {
                Text("The story so far").font(font.font(size: 15, weight: .regular)).foregroundStyle(theme.secondary)
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
    let font: YearReviewPosterFont

    private var people: [YearReviewPerson] { card.people(in: report).filter { !hiddenPeople.contains($0.pubkey) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: card.icon).foregroundStyle(theme.accent)
                Text(card.title(for: voice, recipeCount: report.recipes?.count ?? 0)).font(font.font(size: 19, weight: .bold))
            }
            YearReviewConversationStoryContent(card: card, report: report)
            if card == .gang {
                YearReviewPeopleLineup(people: people, names: names, pictures: pictures, openProfile: nil)
            } else {
                if card == .activeDay, let day = report.mostActiveDay {
                    YearReviewActiveDayContent(day: day, average: report.averagePostsPerDay, streak: report.longestPostingStreak, dateFormat: report.period.dateFormat, posterFont: font)
                    YearReviewPostingRuns(streak: report.longestPostingStreak, gap: report.longestPostingBreak)
                }
                if card == .polls, let activity = report.polls {
                    YearReviewPollActivityContent(activity: activity)
                }
                if let publications = card.publications(in: report) {
                    YearReviewPublicationContent(publications: publications, isRecipe: card == .recipes,
                        previews: previews, open: nil, posterFont: font)
                }
                if let post = card.post(in: report) {
                    if card != .returningThread && card != .newConversations {
                        YearReviewPostMetric(card: card, post: post, voters: report.polls?.mostVotedCount ?? 0)
                            .font(font.font(size: 36, weight: .black))
                            .foregroundStyle(theme.accent)
                    }
                    Text(previews[post.id]?.text ?? post.content)
                        .font(font.font(size: 17, weight: .regular))
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
    let savedCounts: [Int: Int]?
    let onSelect: (YearReviewMonthProgress) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var months: [YearReviewMonthProgress] {
        if let collection { return Array(collection.monthProgress(active: active).reversed()) }
        let queued = YearReviewCollection(owner: "", period: period, relays: [], trusted: []).monthProgress(active: [])
            .map { month in
                var month = month
                month.own.pending = 1
                month.others.pending = 1
                return month
            }
        return Array(queued.reversed())
    }

    @ViewBuilder private var legend: some View {
        Label {
            Text("Your content")
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
        }
        .foregroundStyle(.secondary)
        Label {
            Text("Interactions")
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .foregroundStyle(.secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(months) { month in
                    Button { onSelect(month) } label: {
                        YearReviewMonthCell(month: month, savedCount: savedCounts?[month.month])
                    }
                        .buttonStyle(.plain).disabled(!month.available)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { legend }
                VStack(spacing: 6) { legend }
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
        }
    }
}

@available(iOS 17.0, *)
private struct YearReviewMonthCell: View {
    let month: YearReviewMonthProgress
    let savedCount: Int?

    private var accessibilityCount: Text {
        guard month.available else { return Text("") }
        return savedCount.map { Text(". Unique saved items: \($0)") } ?? Text("")
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
            Text(month.date, format: monthStyle)
                .font(.caption.weight(.semibold))
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
                            .opacity(0.18)
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
            NXList {
                Section {
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
                Section {
                    if !month.failures.isEmpty {
                        NavigationLink {
                            YearReviewIncompleteSourcesView(month: month)
                        } label: {
                            Label("Incomplete sources", systemImage: "exclamationmark.circle")
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

struct YearReviewMonthPassStatus: View {
    let pass: YearReviewMonthProgress.Pass
    var body: some View {
        Group {
            if pass.active {
                Label("Fetching", systemImage: "arrow.down.circle")
            } else if pass.failed > 0 {
                Label("Incomplete sources", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            } else if pass.finished {
                Label("Checked", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else if pass.completed > 0 {
                Text("Partly fetched")
            } else {
                Text("Not fetched")
            }
        }
        .labelStyle(.titleAndIcon)
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
        NXList {
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
