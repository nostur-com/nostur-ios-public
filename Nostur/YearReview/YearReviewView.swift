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
    @State private var showProfilePicker = false
    @State private var shareDraft: YearReviewShareDraft?
    @State private var showHistory = false
    @State private var showRefreshSources = false
    @State private var pendingSharePost: NewPostInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    if model.report?.period.showsYearToDateLabel ?? (model.year == YearReviewPeriod.currentYear) {
                        Text("\(String(model.year)) so far").font(.largeTitle.bold())
                    } else {
                        Text("My Nostr in \(String(model.year))").font(.largeTitle.bold())
                    }
                    Button { showProfilePicker = true } label: {
                        HStack(spacing: 10) {
                            PFP(pubkey: model.owner.isEmpty ? account.pubkey : model.owner, pictureUrl: model.ownerPicture, size: 40)
                            Text(model.ownerName).font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose a profile for this report")
                    .accessibilityValue(model.ownerName)
#if DEBUG
                    if model.debugTwoMonths {
                        Label {
                            Text("Test report · \(Date(timeIntervalSince1970: TimeInterval(model.currentPeriod.start)), format: model.currentPeriod.monthFormat) – \(model.currentPeriod.cutoffDate, format: model.currentPeriod.monthFormat)")
                        } icon: { Image(systemName: "hammer") }
                            .font(.caption).foregroundStyle(.secondary)
                    }
#endif
                }
                YearReviewHistorySummary(model: model, openHistory: { showHistory = true })
                if !model.isRunning, (model.report?.ownPostCount ?? 0) == 0, !hasShareableCard,
                   model.collection == nil {
                    Button { showRefreshSources = true } label: {
                        Label("Fetch history…", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.owner.isEmpty || model.viewer != account.pubkey || model.isDeleting)
                }
                if let report = model.report {
                    YearReviewHighlightsView(report: report, voice: model.owner == account.pubkey ? .reader : .neutral(ownerName: model.ownerName), names: model.names, pictures: model.pictures,
                        enabledCards: model.enabledCards, hiddenPeople: model.hiddenPeople, previews: model.postPreviews, openPost: openPost, openProfile: openProfile,
                        toggleCard: { card in
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                                if model.enabledCards.contains(card) { model.enabledCards.remove(card) }
                                else { model.enabledCards.insert(card) }
                            }
                        })

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
#if DEBUG
        .onChange(of: model.debugTwoMonths) { _, _ in
            Task { await model.selectYear() }
        }
#endif
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
        .confirmationDialog("Delete this account's collected public history?", isPresented: $showDelete, titleVisibility: .visible) {
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
                            model.start(download: true)
                        } label: {
                            Label("Fetch from selected relays", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent).padding()
                        .background(theme.listBackground)
                        .disabled(model.selectedRelays.isEmpty)
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
#if DEBUG
            Section("Testing") {
                Toggle("Start with two random adjacent months", isOn: $model.debugTwoMonths)
                    .disabled(model.isRunning)
                Text("Starts with two months. Tap another month in the calendar to add it. Test progress is saved separately from full-year progress.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
#endif

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

    private var hasShareableCard: Bool {
        guard let report = model.report else { return false }
        return YearReviewCard.allCases.contains { card in
            card.hasHighlight(in: report) || card.people(in: report).contains { !model.hiddenPeople.contains($0.pubkey) }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    YearReviewMonthCalendarView(collection: model.collection, period: model.currentPeriod,
                        active: model.calendarActivity, activities: model.activeActivities, onSelect: { selectedMonth = $0 })
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
                        if let job = model.collection, !model.hasNewHistorySources,
                           job.phase == .finished && job.pending.isEmpty && job.failed.isEmpty {
                            Text("Finished checking your selected relays.")
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
                YearReviewMonthActionsView(model: model, initialMonth: month)
                    .environment(\.theme, theme)
            }
            .sheet(isPresented: $showHistoryInfo) {
                YearReviewHistoryInfoView(model: model)
            }
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
                    detail: "The calendar counts everything relays send, including repeats. Repeat copies don’t add to your report totals.")
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
                    Text("Your report uses public posts and interactions. Private messages aren’t included.")
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
    var hidePerson: ((String) -> Void)? = nil
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
        let cards = orderedCards
        VStack(alignment: .leading, spacing: 16) {
            ForEach(cards.prefix(3)) { card in row(card) }
            if cards.count > 3 {
                DisclosureGroup("More highlights", isExpanded: $showMore) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(cards.dropFirst(3)) { card in row(card) }
                    }.padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder private func row(_ card: YearReviewCard) -> some View {
        if !enabledCards.contains(card), let toggleCard {
            YearReviewCollapsedCard(card: card, voice: voice, show: { toggleCard(card) })
                .transition(.opacity)
        } else {
            YearReviewHighlightCard(card: card, voice: voice, story: YearReviewConversationStoryContent(card: card, report: report), post: card.post(in: report), activeDay: card == .activeDay ? report.mostActiveDay : nil, averagePostsPerDay: report.averagePostsPerDay, postingRuns: YearReviewPostingRuns(streak: report.longestPostingStreak, gap: report.longestPostingBreak), pollActivity: card == .polls ? report.polls : nil, dateFormat: report.period.dateFormat,
                people: card.people(in: report).filter { !hiddenPeople.contains($0.pubkey) },
                names: names, pictures: pictures, preview: card.post(in: report).flatMap { previews[$0.id] }, openPost: openPost, openProfile: openProfile, hidePerson: hidePerson,
                hide: toggleCard.map { toggle in { toggle(card) } })
                .yearReviewCard()
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
    let hidePerson: ((String) -> Void)?
    var hide: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Label { Text(card.title(for: voice)).font(.title3.bold()) } icon: {
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
                YearReviewActiveDayContent(day: activeDay, average: averagePostsPerDay, dateFormat: dateFormat)
                postingRuns
            }
            if let pollActivity {
                YearReviewPollActivityContent(activity: pollActivity)
            }
            story
            if let post {
                if card == .polls { Text("Your most-voted poll").font(.subheadline).foregroundStyle(.secondary) }
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
                switch card {
                case .polls: Text("\(pollActivity?.mostVotedCount ?? 0) voters").font(.headline)
                case .conversation: Text("\(post.replies) replies · \(post.respondents) people").font(.headline)
                case .mostReacted: Text("\(post.reactions) reactions").font(.headline)
                case .mostZapped: Text("\(post.zaps) zaps").font(.headline)
                case .mostZapValue: Text("\((post.millisats / 1000).formatted()) sats · \(post.zaps) zaps").font(.headline)
                default: EmptyView()
                }
            }
            ForEach(people) { person in
                YearReviewPersonRow(person: person, name: names[person.pubkey] ?? String(npub(person.pubkey).prefix(16)) + "…",
                    picture: pictures[person.pubkey], card: card, openProfile: openProfile, hidePerson: hidePerson)
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
        if streak >= 3 || gap >= 7 {
            VStack(alignment: .leading, spacing: 8) {
                if streak >= 3 {
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
    let day: YearReviewActiveDay
    let average: Double
    let dateFormat: Date.FormatStyle

    var body: some View {
        Text("You posted an average of \(average, format: .number.precision(.fractionLength(1))) times per day and your most active day was \(day.date, format: dateFormat) with \(day.posts) posts.")
            .font(.headline)
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
                NavigationLink {
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
                } label: {
                    Label("Choose highlights", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered).padding(.vertical, 10)
                ScrollView {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel("Your year report image")
                    } else if selected.isDisjoint(with: content.shareableCards) {
                        Text("Choose at least one highlight.").padding()
                    } else if renderFailed {
                        VStack(spacing: 12) {
                            Text("The share image could not be created. Please try again.")
                            Button("Try again") { renderAttempt += 1 }
                        }.padding()
                    } else {
                        ProgressView("Preparing preview…").padding()
                    }
                }
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
        VStack(alignment: .leading, spacing: 0) {
            YearReviewPosterHeader(year: report.period.year, ownReport: voice == .author, name: ownerName, owner: owner, picture: ownerPicture, showsYearToDateLabel: report.period.showsYearToDateLabel)
                .padding(.bottom, 28)
            ForEach(shareableCards.filter { (cardsToRender ?? enabledCards).contains($0) }) { card in
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
                Image("NosturLogoCreature").resizable().renderingMode(.template).scaledToFit().frame(width: 20, height: 24)
                Text(verbatim: "nostur.com").font(.system(size: 12, weight: .bold, design: .rounded))
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
                HStack(alignment: .top, spacing: 8) {
                    ForEach(people) { person in
                        VStack(spacing: 8) {
                            PFP(pubkey: person.pubkey, pictureUrl: pictures[person.pubkey], size: 54)
                            Text(names[person.pubkey] ?? String(npub(person.pubkey).prefix(10)) + "…")
                                .font(.system(size: 11, weight: .bold)).lineLimit(2).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity)
                    }
                }
            } else {
                if card == .activeDay, let day = report.mostActiveDay {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(report.averagePostsPerDay, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 60, weight: .black, design: .rounded)).tracking(-2)
                        Text("posts per day").font(.system(size: 15, weight: .semibold))
                    }
                    Text("Busiest day: \(day.date, format: report.period.dateFormat) · \(day.posts) posts")
                        .font(.system(size: 14, weight: .medium))
                    YearReviewPostingRuns(streak: report.longestPostingStreak, gap: report.longestPostingBreak)
                }
                if card == .polls, let activity = report.polls {
                    YearReviewPollActivityContent(activity: activity)
                }
                if let post = card.post(in: report) {
                    if card != .returningThread && card != .newConversations {
                        YearReviewPosterPostMetric(card: card, post: post, voters: report.polls?.mostVotedCount ?? 0)
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

private struct YearReviewPosterPostMetric: View {
    let card: YearReviewCard
    let post: YearReviewPost
    let voters: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch card {
            case .conversation: Text("\(post.replies) replies")
            case .mostReacted: Text("\(post.reactions) reactions")
            case .mostZapped: Text("\(post.zaps) zaps")
            case .mostZapValue: Text("\((post.millisats / 1000).formatted()) sats")
            case .polls: Text("\(voters) voters")
            default: EmptyView()
            }
        }
        .font(.system(size: 36, weight: .black, design: .rounded))
    }
}

private struct YearReviewCardStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 20))
    }
}

private extension View {
    func yearReviewCard() -> some View { modifier(YearReviewCardStyle()) }
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
    let onSelect: (YearReviewMonthProgress) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

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
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(months) { month in
                    Button { onSelect(month) } label: { YearReviewMonthCell(month: month) }
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

    private var interactionPass: Bool { month.own.pending == 0 }
    private var pass: YearReviewMonthProgress.Pass { interactionPass ? month.others : month.own }
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
            Text(month.available ? String(localized: "\(month.received) received") : "–")
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
        .accessibilityValue(accessibilityStatus + Text(". \(month.received) items received, including duplicates"))
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
            List {
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
