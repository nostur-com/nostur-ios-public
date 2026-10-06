import SwiftUI
import Combine

@available(iOS 17.0, *)
@MainActor
struct YearReviewView: View {
    var initialYear: Int? = nil
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
    @State private var shareImage: UIImage?
    @State private var showShare = false
    @State private var isRendering = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    if model.report?.period.isYearToDate ?? (model.year == YearReviewPeriod.currentYear) {
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
                if model.isRunning {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Button { model.pause() } label: {
                                Label("Pause collection", systemImage: "pause.fill").labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            ProgressView().controlSize(.small)
                            Text(model.progressLabel).font(.subheadline.weight(.semibold))
                        }
                        YearReviewMonthCalendarView(collection: model.collection, period: model.currentPeriod, active: model.calendarActivity, activities: model.activeActivities)
                        if model.stage == .references, let collection = model.collection, collection.phase == .references {
                            Text("\(collection.referenceQueriesChecked ?? 0) extra checks completed · \(collection.pending.count) queued")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.archivedCounts.fromYou) posts or interactions by you")
                            Text("\(model.archivedCounts.fromOthers) interactions by others")
                        }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .yearReviewCard()
                    Label("You can use Nostur while collection runs. Keep the app on screen; or, if you close it, continue later from saved progress.", systemImage: "iphone")
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                } else if model.report == nil {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(theme.accent)
                        Text("Your conversations. Your people. Your year.").font(.title2.bold())
                    }
                    .yearReviewCard()
                }
                if !model.isRunning {
                    YearReviewActionsView(hasReport: model.report != nil, canResume: model.canResume, forOtherProfile: model.owner != account.pubkey,
                        disabled: model.owner.isEmpty || model.viewer != account.pubkey || model.isDeleting,
                        create: { resetPreview(); model.start(download: true) },
                        resume: { resetPreview(); model.start(download: true, resume: true) },
                        preview: { resetPreview(); model.start(download: false) })
                }
                if let report = model.report {
                    YearReviewHighlightsView(report: report, names: model.names, pictures: model.pictures,
                        enabledCards: model.enabledCards, hiddenPeople: model.hiddenPeople, previews: model.postPreviews, openPost: openPost, openProfile: openProfile,
                        toggleCard: { card in
                            if model.enabledCards.contains(card) { model.enabledCards.remove(card) }
                            else { model.enabledCards.insert(card) }
                        })
                    if !hasShareableCard {
                        Text("Show a section to include it in your shared report, or gather more history.")
                            .foregroundStyle(.secondary).yearReviewCard()
                    }
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
        .navigationTitle("Your year on Nostr")
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
                .disabled(!hasShareableCard || isRendering || model.isRunning)
            }
        }
        .task(id: account.pubkey) {
            model.refreshHistoryRelayAuth()
            guard openedAccount != account.pubkey else { return }
            if model.viewer != account.pubkey || model.owner != account.pubkey { await model.configure(account: account) }
            if !model.isRunning, let initialYear, model.year != initialYear { model.year = initialYear }
            guard !Task.isCancelled else { return }
            openedAccount = account.pubkey
            YearReviewDiscovery.markOpened(owner: account.pubkey, year: model.year)
        }
#if DEBUG
        .onChange(of: model.debugTwoMonths) { _, _ in
            resetPreview()
            Task { await model.selectYear() }
        }
#endif
        .onChange(of: model.year) { _, _ in
            if model.owner == account.pubkey { YearReviewDiscovery.markOpened(owner: account.pubkey, year: model.year) }
            resetPreview()
            Task { await model.selectYear() }
        }
        .onChange(of: model.report) { _, _ in
            shareImage = nil
            showShare = false
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
                YearReviewAboutView(report: model.report, collection: model.reportCollection)
            }
        }
        .sheet(isPresented: $showProfilePicker) {
            NavigationStack {
                ContactsSearch(followingPubkeys: account.account.followingPubkeys, prompt: "Search profiles", onSelectContact: { contact in
                    showProfilePicker = false
                    Task { await model.configure(account: account, contact: contact) }
                })
                .navigationTitle("Choose a profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { showProfilePicker = false } label: {
                            Label("Done", systemImage: "checkmark").labelStyle(.iconOnly)
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showProfilePicker = false
                            Task { await model.configure(account: account) }
                        } label: {
                            Label("My profile", systemImage: "person.crop.circle").labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showShare, onDismiss: { shareImage = nil }) {
            if let shareImage, let report = model.report {
                ActivityView(activityItems: [shareImage, shareCaption(report)])
            }
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
                .disabled(model.isRunning)
            }
#if DEBUG
            Section("Testing") {
                Toggle("Fetch two random adjacent months", isOn: $model.debugTwoMonths)
                    .disabled(model.isRunning)
                Text("Limits history scans and extra interaction checks to two months. Test progress is saved separately from full-year progress.")
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
                    Toggle(card.title, isOn: Binding(
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
                Picker("Share format", selection: $model.selectedShareFormat) {
                    Text("Summary").tag(YearReviewShareFormat.report)
                    Text("My Nostr Gang").tag(YearReviewShareFormat.gang)
                }
            } header: {
                Text("Choose what to share")
            } footer: {
                Text("Only selected cards and visible people appear in the shared image. Nothing is posted automatically.")
            }

            Section {
                Button("Export signed public history") { model.exportArchive() }
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
        let cards: Set<YearReviewCard> = model.selectedShareFormat == .gang ? model.enabledCards.intersection([.gang]) : model.enabledCards
        return cards.contains { card in
            card.hasHighlight(in: report) || card.people(in: report).contains { !model.hiddenPeople.contains($0.pubkey) }
        }
    }

    private func resetPreview() {
        shareImage = nil
    }

    private func shareCaption(_ report: YearReviewReport) -> String {
        var caption = report.period.isYearToDate
            ? String(localized: "My Nostr in \(String(report.period.year)) so far")
            : String(localized: "My Nostr in \(String(report.period.year))")
        if model.owner != model.viewer {
            caption = String(localized: "\(model.ownerName)'s Nostr in \(String(report.period.year))")
        }
        if report.period.monthLimit != nil { caption += "\n" + String(localized: "Test report: \(Date(timeIntervalSince1970: TimeInterval(report.period.start)).formatted(report.period.monthFormat)) – \(report.period.cutoffDate.formatted(report.period.monthFormat))") }
        if model.selectedShareFormat == .report, model.enabledCards.contains(.conversation),
           let id = report.conversation?.id, let note = note1(id) { caption += "\nnostr:" + note }
        return caption + "\n" + String(localized: "Created with Nostur")
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
        isRendering = true
        let cards: Set<YearReviewCard> = model.selectedShareFormat == .gang ? model.enabledCards.intersection([.gang]) : model.enabledCards
        let hidden = model.hiddenPeople
        let names = model.names
        let pictures = model.pictures
        let collection = model.reportCollection
        let owner = model.owner
        Task {
            defer { isRendering = false }
            let image = await ShareCardRenderer.render(
                ShareCardCanvas(showsBranding: true) {
                    YearReviewShareContent(report: report, ownerName: model.ownerName, names: names,
                        pictures: pictures, enabledCards: cards, hiddenPeople: hidden, collection: collection, previews: model.postPreviews)
                }.environment(\.theme, theme)
            )
            guard model.owner == owner, model.report == report else { return }
            if let image { shareImage = image; showShare = true }
            else { model.errorMessage = String(localized: "The share image could not be created. Please try again.") }
        }
    }
}

enum YearReviewCard: String, CaseIterable, Identifiable, Codable {
    case gang, activeDay, conversation, mostReacted, mostZapped, mostZapValue, supporters, mentions
    case mostInteracted, mostTalked, replyGuy, reactedBy, liked, zappedBy, zapped, amplifiedBy
    static let defaultSelection: Set<Self> = Set(allCases)
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .gang: "My Nostr Gang"
        case .activeDay: "Your posting rhythm"
        case .conversation: "You got people talking"
        case .mostReacted: "Your most-loved post"
        case .mostZapped: "Your most-zapped post"
        case .mostZapValue: "Your biggest lightning moment"
        case .supporters: "Your supporters"
        case .mentions: "Who can't stop talking about you?"
        case .mostInteracted: "Your closest connections"
        case .mostTalked: "Your public conversations"
        case .replyGuy: "Your top reply guy"
        case .reactedBy: "Your biggest fans"
        case .liked: "You couldn't help reacting"
        case .zappedBy: "Who sent you the most zaps?"
        case .zapped: "Who you zapped the most"
        case .amplifiedBy: "Who spread your words?"
        }
    }
    var icon: String {
        switch self {
        case .gang, .mostInteracted: "person.3.fill"
        case .activeDay: "calendar"
        case .conversation, .mostTalked, .replyGuy: "bubble.left.and.bubble.right.fill"
        case .mostReacted, .reactedBy, .liked: "heart.fill"
        case .mostZapped, .mostZapValue, .zappedBy, .zapped: "bolt.fill"
        case .supporters: "hands.clap.fill"
        case .mentions: "at"
        case .amplifiedBy: "arrow.2.squarepath"
        }
    }
    func hasHighlight(in report: YearReviewReport) -> Bool {
        post(in: report) != nil || (self == .activeDay && report.mostActiveDay != nil)
    }

    func post(in report: YearReviewReport) -> YearReviewPost? {
        switch self {
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

private struct YearReviewActionsView: View {
    let hasReport: Bool
    let canResume: Bool
    let forOtherProfile: Bool
    let disabled: Bool
    let create: () -> Void
    let resume: () -> Void
    let preview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: canResume ? resume : create) {
                if canResume {
                    Label("Continue gathering", systemImage: "arrow.down.circle")
                } else if hasReport {
                    if forOtherProfile { Label("Update report", systemImage: "arrow.clockwise") }
                    else { Label("Update my year", systemImage: "arrow.clockwise") }
                } else {
                    if forOtherProfile { Label("Create report", systemImage: "sparkles") }
                    else { Label("Create my year", systemImage: "sparkles") }
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button(action: preview) { Label("Refresh from saved history", systemImage: "cylinder.split.1x2") }
                if canResume {
                    Button(action: create) { Label("Check all sources again", systemImage: "arrow.clockwise") }
                }
            } label: {
                Label("More report actions", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                    .font(.title2)
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
                Text("Choose up to 20 relays. Nostur checks different relays in parallel, with one history request at a time per relay. Old relays may have history that your current relays no longer store.")
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
                    Text("App relays inherit their Auth setting unless you change it here. Report-only relays start with Auth off.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Authenticate with your logged-in signing account. This identifies your public key to the relay, including when gathering a report for someone else.")
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
    let report: YearReviewReport?
    let collection: YearReviewCollection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title2).foregroundStyle(theme.accent)
                        .frame(width: 48, height: 48)
                        .background(theme.accent.opacity(0.12), in: Circle())
                    Text("A year worth sharing").font(.title.bold())
                    Text("Your posts, your people, your standout moments.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 18) {
                    YearReviewAboutRow(title: "Public activity only", icon: "text.bubble",
                        detail: "Posts, photos, videos, voice messages and articles. Your private messages stay private.")
                    YearReviewAboutRow(title: "Choose what you want to highlight", icon: "square.and.arrow.up",
                        detail: "And who you want to include. Nothing is posted automatically.")
                }
                .yearReviewCard()

                YearReviewAboutRow(title: "While gathering history", icon: "iphone",
                    detail: "You can use Nostur while collection runs. Keep the app on screen; or, if you close it, continue later from saved progress.")
                    .yearReviewCard()

                if let report {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(report.ownPostCount, format: .number).font(.title2.bold()).monospacedDigit()
                            Text("of your posts found").font(.subheadline).foregroundStyle(.secondary)
                        }
                        YearReviewAboutDetail(title: "History coverage", icon: "chart.bar") {
                            YearReviewCoverageView(report: report, collection: collection)
                        }
                    }
                    .yearReviewCard()
                }

                VStack(alignment: .leading, spacing: 14) {
                    YearReviewAboutDetail(title: "How highlights are counted", icon: "trophy") {
                        Text("Your most-loved post counts positive reaction events, like post details. People rankings count each person once per post. Supporters combine reactions, reposts and validated zaps.")
                        Text("You got people talking includes direct replies, sub-replies and your own replies in the collected conversation. People are counted once per thread. Relationship highlights count direct exchanges.")
                        Text("People rankings cover the report period with your trust filters applied. Most-loved post totals include all available positive reactions to posts from that year and update when more reactions are found.")
                        Text("Your most active day counts public posts, including replies, pictures, videos, voice messages and articles. Reactions, reposts and zaps are not posts. Edited articles count once on their original publication day. The daily average includes every calendar day covered by the report, including days without posts.")
                        Text("The mentions highlight needs more than ten explicit mentions in public posts or comments. Threading tags alone do not count.")
                    }
                    Divider()
                    YearReviewAboutDetail(title: "Relays & missing history", icon: "network") {
                        Text("Collection is paced per relay and saves progress as it goes. Relays may omit old content or cap results, so your report only reflects the history we could find.")
                    }
                    Divider()
                    YearReviewAboutDetail(title: "Zap validation", icon: "bolt") {
                        Text("Lightning totals use provider-authorized receipts. Anonymous zaps contribute to post totals without identifying a sender.")
                        Text("Checking zap providers may fetch missing profiles from relays and contact Lightning services to verify who signed the receipts. Slow services and missing provider information can make this step take longer. Saved provider keys are reused.")
                        Text("Verified receipts stay cached even if a Lightning address changes. Unresolved provider checks are normally retried after 24 hours; a changed address or a new signer can trigger an earlier check.")
                        Text("Older outgoing receipts without a sender tag can be included when known locally, but may not be discoverable on relays. Receipts from historical providers we cannot authorize are excluded.")
                    }
                }
                .yearReviewCard()
            }
            .padding(20)
            .frame(maxWidth: 650, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.listBackground)
        .navigationTitle("About your year")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: {
                    Label("Done", systemImage: "checkmark").labelStyle(.iconOnly)
                }
            }
        }
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

private struct YearReviewAboutDetail<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: LocalizedStringKey
    let icon: String
    let content: Content

    init(title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) { content }
                .font(.footnote).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
        } label: {
            Label { Text(title).font(.subheadline.weight(.semibold)) } icon: {
                Image(systemName: icon).foregroundStyle(theme.accent).frame(width: 24)
            }
        }
        .tint(theme.accent)
    }
}

private struct YearReviewCoverageView: View {
    let report: YearReviewReport
    let collection: YearReviewCollection?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trusted public activity · \(report.ownPostCount) of your posts found")
            if let collection {
                if collection.phase != .finished || !collection.failed.isEmpty || collection.estimatedResponses > 0 || report.unresolvedParents > 0 || collection.parentsLimited {
                    Label("Partial history", systemImage: "info.circle")
                } else {
                    Label("Selected sources checked", systemImage: "checkmark.circle")
                }
                Text("\(collection.relays.count) relays · \(collection.requestsChecked) requests checked")
                ForEach(collection.issues, id: \.self) { issue in Text(issue) }
                if collection.estimatedResponses > 0 {
                    Text("Some relays did not confirm exhaustive responses. More activity may exist elsewhere.")
                }
                if collection.invalidEvents > 0 {
                    Text("\(collection.invalidEvents) invalid or unrelated events excluded")
                }
                if collection.parentsLimited { Text("The missing-parent lookup reached its limit. Some conversations remain unresolved.") }
            } else {
                Label("Saved history only · partial history", systemImage: "info.circle")
            }
            if report.excludedAuthors > 0 { Text("\(report.excludedAuthors) authors excluded by trust or block filtering") }
            if report.unverifiedZaps > 0 { Text("\(report.unverifiedZaps) zap receipts could not be validated and are excluded") }
            if report.anonymousZaps > 0 { Text("\(report.anonymousZaps) anonymous zaps contribute only to post totals") }
            if report.unresolvedParents > 0 { Text("\(report.unresolvedParents) replies still have missing parents") }
            Text("Through \(report.period.cutoffDate, format: report.period.dateFormat)")
        }
        .font(.footnote).foregroundStyle(.secondary)
    }
}

private struct YearReviewHighlightsView: View {
    let report: YearReviewReport
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(visibleCards) { card in
                if !enabledCards.contains(card), let toggleCard {
                    YearReviewCollapsedCard(card: card, show: { toggleCard(card) })
                } else {
                    YearReviewHighlightCard(card: card, post: card.post(in: report), activeDay: card == .activeDay ? report.mostActiveDay : nil, averagePostsPerDay: report.averagePostsPerDay, dateFormat: report.period.dateFormat,
                        people: card.people(in: report).filter { !hiddenPeople.contains($0.pubkey) },
                        names: names, pictures: pictures, preview: card.post(in: report).flatMap { previews[$0.id] }, openPost: openPost, openProfile: openProfile, hidePerson: hidePerson,
                        hide: toggleCard.map { toggle in { toggle(card) } })
                        .yearReviewCard()
                }
            }
        }
    }
}

private struct YearReviewCollapsedCard: View {
    @Environment(\.theme) private var theme
    let card: YearReviewCard
    let show: () -> Void

    var body: some View {
        Button(action: show) {
            HStack(spacing: 12) {
                Text(card.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
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
        .accessibilityLabel(Text("Show \(Text(card.title)) in your report"))
    }
}

private struct YearReviewHighlightCard: View {
    @Environment(\.theme) private var theme
    let card: YearReviewCard
    let post: YearReviewPost?
    let activeDay: YearReviewActiveDay?
    let averagePostsPerDay: Double
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
                Label { Text(card.title).font(.title3.bold()) } icon: {
                    Image(systemName: card.icon).foregroundStyle(theme.accent)
                }
                if let hide {
                    Spacer(minLength: 0)
                    Button(action: hide) {
                        Image(systemName: "eye.slash").foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Hide \(Text(card.title)) from your report"))
                }
            }
            if let activeDay {
                YearReviewActiveDayContent(day: activeDay, average: averagePostsPerDay, dateFormat: dateFormat)
            }
            if let post {
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
        case .mentions: Text("Mentioned you in \(person.mentions) posts")
        case .gang, .mostTalked: Text("\(person.sent) replies from you · \(person.received) back")
        case .replyGuy: Text("\(person.received) replies to you")
        case .mostInteracted: Text("\(person.interactions) public interactions")
        case .supporters: Text("\(person.reactions) reactions · \(person.reposts) reposts · \(person.zaps) zaps")
        case .reactedBy, .liked: Text("\(person.reactions) posts reacted to")
        case .zappedBy, .zapped: Text("\(person.zaps) zaps · \((person.millisats / 1000).formatted()) sats")
        case .amplifiedBy: Text("\(person.reposts) reposts · \(person.quotes) quotes")
        default: EmptyView()
        }
    }
}

private struct YearReviewShareContent: View {
    let report: YearReviewReport
    let ownerName: String
    let names: [String: String]
    let pictures: [String: URL]
    let enabledCards: Set<YearReviewCard>
    let hiddenPeople: Set<String>
    let collection: YearReviewCollection?
    let previews: [String: YearReviewPostPreview]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                if report.period.isYearToDate {
                    Text("My Nostr in \(String(report.period.year)) so far").font(.largeTitle.bold())
                } else {
                    Text("My Nostr in \(String(report.period.year))").font(.largeTitle.bold())
                }
                Text(ownerName).font(.headline).foregroundStyle(.secondary)
            }
            YearReviewHighlightsView(report: report, names: names, pictures: pictures,
                enabledCards: availableCards, hiddenPeople: hiddenPeople)
            Text("Trusted public activity found through \(report.period.cutoffDate, format: report.period.dateFormat)")
                .font(.caption).foregroundStyle(.secondary)
            if collection == nil || collection?.phase != .finished || collection?.estimatedResponses ?? 0 > 0 || !(collection?.failed.isEmpty ?? true) || report.unresolvedParents > 0 || collection?.parentsLimited == true {
                Text("Partial history").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var availableCards: Set<YearReviewCard> {
        Set(enabledCards.filter { card in
            card.hasHighlight(in: report) || card.people(in: report).contains { !hiddenPeople.contains($0.pubkey) }
        })
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
                    YearReviewMonthCell(month: month)
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
    @State private var showingIncompleteSources = false

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
        .onTapGesture {
            if incomplete { showingIncompleteSources = true }
        }
        .sheet(isPresented: $showingIncompleteSources) {
            NavigationStack {
                YearReviewIncompleteSourcesView(month: month)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(month.date, format: monthStyle))
        .accessibilityValue(accessibilityStatus + Text(". \(month.received) items received, including duplicates"))
    }

    private var accessibilityStatus: Text {
        if !month.available { return Text("Outside the selected period") }
        if pass.active { return interactionPass ? Text("Fetching interactions") : Text("Fetching your content") }
        if month.own.failed > 0 || month.others.failed > 0 { return Text("Some sources remain incomplete. Tap for relay details") }
        if bothFinished { return Text("Both month passes checked") }
        if month.own.finished { return Text("Your content checked; interactions queued") }
        return Text("Queued")
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
                Text("One failed request can pause a relay for the rest of this run. Other months may be skipped without being attempted. Other relays can still finish.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(relays, id: \.self) { relay in
                YearReviewSourceFailureSection(relay: relay,
                    failures: month.failures.filter { $0.work.relay == relay },
                    timeZoneIdentifier: month.timeZoneIdentifier)
            }
            Section {
                Text("Use Continue gathering on the report screen to resume remaining checks and retry incomplete sources. Successful saved batches are kept. Items buffered in a failed request may need to be downloaded again.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Incomplete sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: {
                    Label("Done", systemImage: "checkmark").labelStyle(.iconOnly)
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
