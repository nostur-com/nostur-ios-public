import Foundation
import Observation
import Combine
import NostrEssentials
import CoreData

struct YearReviewPreferences: Codable, Equatable {
    var cardSelectionVersion: Int? = 2
    var relayDefaultsVersion: Int? = 1
    let cards: Set<YearReviewCard>
    let hiddenPeople: Set<String>
    let shareFormat: YearReviewShareFormat
    let selectedRelays: Set<String>
    let relays: [YearReviewCollection.RelayDataSnapshot]
    var relayAuthOverrides: [String: Bool]? = nil

    static func applyingAuth(to relays: [RelayData], configured: [RelayData], overrides: [String: Bool]) -> [RelayData] {
        var defaults: [String: Bool] = [:]
        for relay in configured { defaults[normalizeRelayUrl(relay.url)] = relay.auth }
        return relays.map { relay in
            var value = relay
            let url = normalizeRelayUrl(relay.url)
            value.auth = overrides[url] ?? defaults[url] ?? relay.auth
            return value
        }
    }

    func save(owner: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: "year-review-preferences-" + owner)
    }

    static func load(owner: String, defaults: UserDefaults = .standard) -> Self? {
        guard let data = defaults.data(forKey: "year-review-preferences-" + owner) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

@available(iOS 17.0, *)
@MainActor
@Observable
final class YearReviewModel {
    static let shared = YearReviewModel()

    enum Stage: Equatable {
        case ready, local, posts, interactions, references, parents, zaps, analyzing, paused, finished
        enum Phase: Int, CaseIterable, Identifiable {
            case history = 1, gaps, highlights
            var id: Int { rawValue }
            var title: LocalizedStringResource {
                switch self {
                case .history: "History"
                case .gaps: "Fill gaps"
                case .highlights: "Highlights"
                }
            }
        }
        var phase: Phase {
            switch self {
            case .ready, .local, .posts, .interactions, .paused: .history
            case .references, .parents: .gaps
            case .zaps, .analyzing, .finished: .highlights
            }
        }
        var detail: LocalizedStringResource {
            switch self {
            case .ready, .paused: "Your saved progress is ready to continue."
            case .local: "Starting with public history already saved on this device."
            case .posts: "Collecting your public posts, month by month."
            case .interactions: "Collecting conversations, reactions, reposts and zaps."
            case .references: "Finding replies, reactions, reposts, quotes and zaps linked directly to your posts."
            case .parents: "Loading missing posts so replies can be matched to the right people."
            case .zaps: "Checking zap receipts before counting lightning totals."
            case .analyzing: "Choosing your standout posts and people."
            case .finished: "Your highlights are ready to share."
            }
        }
        var label: LocalizedStringResource {
            switch self {
            case .ready: "Ready to gather your year"
            case .local: "Saving your existing history…"
            case .posts: "Gathering your posts…"
            case .interactions: "Gathering replies and support…"
            case .references: "Finding missed interactions…"
            case .parents: "Filling in conversations…"
            case .zaps: "Checking zap providers…"
            case .analyzing: "Finding your highlights…"
            case .paused: "History collection paused"
            case .finished: "Your preview is ready"
            }
        }
    }

    var year = YearReviewPeriod.defaultYear()
    var relays: [RelayData] = []
    var selectedRelays: Set<String> = [] { didSet { savePreferences() } }
    var enabledCards = YearReviewCard.defaultSelection { didSet { savePreferences() } }
    var hiddenPeople: Set<String> = [] { didSet { savePreferences() } }
    var selectedShareFormat = YearReviewShareFormat.report { didSet { savePreferences() } }
    var relayAuthOverrides: [String: Bool] = [:]
    @ObservationIgnored private var restoringPreferences = false

    private func savePreferences() {
        guard !owner.isEmpty, !restoringPreferences else { return }
        YearReviewPreferences(cards: enabledCards, hiddenPeople: hiddenPeople,
            shareFormat: selectedShareFormat, selectedRelays: selectedRelays,
            relays: relays.map { .init(url: $0.url, auth: $0.auth) }, relayAuthOverrides: relayAuthOverrides).save(owner: owner)
    }
    var postPreviews: [String: YearReviewPostPreview] = [:]
    var report: YearReviewReport?
    var collection: YearReviewCollection?
    var reportCollection: YearReviewCollection?
    var activities: [String: YearReviewActivity] = [:]
    var activeActivities: [YearReviewActivity] { activities.values.sorted { $0.work.relay < $1.work.relay } }
    var activity: YearReviewActivity? { activeActivities.first }
    var calendarActivity: [YearReviewWork] {
        collection?.calendarActivity(active: activeActivities.map(\.work), running: isRunning) ?? []
    }
    var lastResponse: (received: Int, added: Int)?
    var stage: Stage = .ready
    var zapStatus: LocalizedStringResource?
    var progressLabel: LocalizedStringResource { stage == .zaps ? zapStatus ?? stage.label : stage.label }
    var isRunning = false
    var archivedCounts = YearReviewArchivedCounts()
    var relayAdditionError: YearReviewRelayAdditionError?
    var errorMessage: String?
    var names: [String: String] = [:]
    var pictures: [String: URL] = [:]
    var ownerName = ""
    var ownerPicture: URL?
    var owner = ""
    var viewer = ""
#if DEBUG
    private var debugMonthChoice: Int = {
        let key = "year-review-test-month-choice"
        if let value = UserDefaults.standard.object(forKey: key) as? Int { return value }
        let value = Int.random(in: 0..<1_000_000)
        UserDefaults.standard.set(value, forKey: key)
        return value
    }()
    var debugTwoMonths = UserDefaults.standard.bool(forKey: "year-review-two-months") {
        didSet {
            UserDefaults.standard.set(debugTwoMonths, forKey: "year-review-two-months")
            if !isRunning { collection = nil; invalidatePreview() }
        }
    }
#endif

    private func selectedPeriod(year: Int) -> YearReviewPeriod {
#if DEBUG
        let firstMonth = UserDefaults.standard.object(forKey: "year-review-test-month-start-\(year)") as? Int
            ?? YearReviewPeriod.testMonthStart(year: year, choice: debugMonthChoice)
        return YearReviewPeriod(year: year, monthLimit: debugTwoMonths ? 2 : nil,
            monthStart: debugTwoMonths ? firstMonth : nil)
#else
        YearReviewPeriod(year: year)
#endif
    }

    var currentPeriod: YearReviewPeriod { collection?.period ?? report?.period ?? selectedPeriod(year: year) }

    private func checkpointKey(_ period: YearReviewPeriod) -> String {
        "collection-\(period.year)" + (period.monthLimit.map { "-\($0)-months-from-\(period.monthStart ?? 1)" } ?? "")
    }
    var exportURL: URL?
    var isExporting = false
    var isDeleting = false

    @ObservationIgnored private var profileTask: Task<Void, Never>?
    @ObservationIgnored private var profileUpdates: AnyCancellable?
    @ObservationIgnored private var reactionUpdates: AnyCancellable?
    @ObservationIgnored private var reactionRefresh: Task<Void, Never>?

    private init() {
        profileUpdates = ViewUpdates.shared.profileUpdates.sink { [weak self] info in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if info.pubkey == self.owner {
                    if let name = info.anyName { self.ownerName = name }
                    if let picture = info.pfpUrl { self.ownerPicture = picture }
                }
                guard self.report != nil, self.names[info.pubkey] != nil else { return }
                if let name = info.anyName { self.names[info.pubkey] = name }
                if let picture = info.pfpUrl { self.pictures[info.pubkey] = picture }
            }
        }
        reactionUpdates = ViewUpdates.shared.eventStatChanged
            .receive(on: RunLoop.main)
            .filter { [weak self] change in change.likes != nil && change.id == self?.report?.mostReacted?.id }
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMostLovedCount() }
    }

    @ObservationIgnored private var livePacing = YearReviewRelayPacing()
    @ObservationIgnored private var archive: YearReviewArchive?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var ownerProvider: YearReviewZapProvider?
    @ObservationIgnored private var trusted: Set<String> = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var previewRevision = 0

    var canResume: Bool {
        collection?.period.year == year && (collection?.phase != .finished || !(collection?.failed.isEmpty ?? true))
    }

    func configure(account: LoggedInAccount, contact: Contact? = nil) async {
        let selectedOwner = contact?.pubkey ?? account.pubkey
        let selectedName = contact?.anyName ?? account.account.anyName
        let selectedPicture = contact?.pictureUrl ?? (contact == nil ? URL(string: account.account.picture) : nil)
        let contactTrust = contact.map { Set($0.followingPubkeys) } ?? []
        let selectedTrust = contactTrust.isEmpty ? account.account.followingPubkeys : contactTrust
        let selectedProvider = YearReviewZapProvider(pubkey: selectedOwner, keys: [],
            lud16: contact?.lud16 ?? (contact == nil ? account.account.lud16 : nil),
            lud06: contact?.lud06 ?? (contact == nil ? account.account.lud06 : nil))
        guard owner != selectedOwner || viewer != account.pubkey else {
            refreshHistoryRelayAuth()
            return
        }
        pause()
        profileTask?.cancel()
        await task?.value
        guard !Task.isCancelled else { return }
        isRunning = false
        task = nil
        generation = UUID()
        let token = generation
        restoringPreferences = true
        defer { restoringPreferences = false }
        owner = selectedOwner
        viewer = account.pubkey
        ownerName = selectedName
        ownerPicture = selectedPicture
        trusted = selectedTrust
        ownerProvider = selectedProvider
        report = nil
        collection = nil
        reportCollection = nil
        archivedCounts = YearReviewArchivedCounts()
        errorMessage = nil
        isDeleting = false
        isExporting = false
        exportURL = nil
        stage = .ready
        activities.removeAll()
        lastResponse = nil
        await HistoryArchiveSync.shared.start()
        let selectedArchive = await YearReviewArchives.shared.archive(owner: selectedOwner)
        guard generation == token else { return }
        archive = selectedArchive

        let configured = CloudRelay.fetchAll().map { $0.toStruct() }
        var advertised = account.account.accountRelays.map { RelayData.new(url: $0.url, read: true) }
        if contact != nil {
            let selectedPubkey = owner
            let context = DataProvider.shared().newTaskContext()
            let cachedProfileLists = await context.perform { () -> (follows: Set<String>, relays: [RelayData]) in
                var follows = Set<String>()
                var relays: [RelayData] = []
                for kind in [3, 10002] {
                    let request = Event.fetchRequest()
                    request.predicate = NSPredicate(format: "pubkey == %@ AND kind == %d AND otherId == nil", selectedPubkey, kind)
                    request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
                    request.fetchLimit = 1
                    guard let event = (try? context.fetch(request))?.first else { continue }
                    if kind == 3 { follows = Set(event.fastTags.filter { $0.0 == "p" }.map { $0.1 }) }
                    else { relays = event.fastTags.filter { $0.0 == "r" }.map { .new(url: $0.1, read: true) } }
                }
                return (follows, relays)
            }
            guard generation == token else { return }
            if !cachedProfileLists.follows.isEmpty { trusted = cachedProfileLists.follows }
            advertised = cachedProfileLists.relays + advertised
        }
        var choices: [String: RelayData] = [:]
        for relay in advertised + configured where relay.read || relay.write {
            guard !relay.excludedPubkeys.contains(owner), !DisabledRelaysStore.isDisabled(relay.url) else { continue }
            guard let validated = ScannedProfile.relayHints([relay.url], limit: 1).first else { continue }
            var value = relay
            value.url = validated
            value.read = true
            choices[validated] = value
        }
        if choices.isEmpty {
            for url in ["wss://nos.lol", "wss://relay.damus.io", "wss://relay.primal.net"] where !DisabledRelaysStore.isDisabled(url) {
                choices[url] = .new(url: url, read: true)
            }
        }
        relays = choices.values.sorted { $0.url < $1.url }
        let receiveRelays = Set(configured.filter { $0.read }.compactMap { relay -> String? in
            guard !relay.excludedPubkeys.contains(owner), !DisabledRelaysStore.isDisabled(relay.url),
                  let url = ScannedProfile.relayHints([relay.url], limit: 1).first,
                  choices[url] != nil else { return nil }
            return url
        })
        selectedRelays = Set(relays.prefix(3).map(\.url)).union(receiveRelays)
        do {
            if let archive {
                let saved = try await archive.load(YearReviewCollection.self, key: checkpointKey(selectedPeriod(year: year)))
                guard generation == token else { return }
                if saved?.schemaVersion == 3, saved?.owner == owner {
                    collection = saved
                    if let saved {
                        for relay in saved.relays where !relays.contains(where: { $0.url == relay.url }) {
                            relays.append(relay.relayData)
                        }
                        selectedRelays = Set(saved.relays.map(\.url))
                    }
                }
            }
        } catch { if generation == token { errorMessage = error.localizedDescription } }
        guard generation == token else { return }
        let preferences = YearReviewPreferences.load(owner: owner)
        relayAuthOverrides = preferences?.relayAuthOverrides ?? [:]
        enabledCards = preferences.map {
            ($0.cardSelectionVersion ?? 0) < 2 ? YearReviewCard.defaultSelection : $0.cards
        } ?? YearReviewCard.defaultSelection
        hiddenPeople = preferences?.hiddenPeople ?? []
        selectedShareFormat = preferences?.shareFormat ?? .report
        if let preferences {
            for relay in preferences.relays where !relays.contains(where: { $0.url == relay.url }) {
                relays.append(relay.relayData)
            }
            selectedRelays = preferences.selectedRelays.filter { !DisabledRelaysStore.isDisabled($0) }
            if preferences.relayDefaultsVersion == nil { selectedRelays.formUnion(receiveRelays) }
        } else {
            selectedRelays.formUnion(receiveRelays)
        }
        refreshHistoryRelayAuth()
    }

    func addRelay(_ value: String) -> Bool {
        do {
            let url = try YearReviewRelayAdditionError.validate(value, selected: selectedRelays,
                disabled: DisabledRelaysStore.isDisabled)
            if !relays.contains(where: { $0.url == url }) { relays.append(.new(url: url, read: true)) }
            selectedRelays.insert(url)
            relayAdditionError = nil
            return true
        } catch {
            relayAdditionError = error as? YearReviewRelayAdditionError ?? .invalidURL
            return false
        }
    }

    func setHistoryRelayAuth(_ url: String, enabled: Bool) {
        guard !isRunning, let index = relays.firstIndex(where: { $0.url == url }) else { return }
        relayAuthOverrides[normalizeRelayUrl(url)] = enabled
        relays[index].auth = enabled
        savePreferences()
    }

    func refreshHistoryRelayAuth() {
        guard !isRunning, !relays.isEmpty else { return }
        relays = YearReviewPreferences.applyingAuth(to: relays,
            configured: CloudRelay.fetchAll().map { $0.toStruct() }, overrides: relayAuthOverrides)
    }

    func resetHistoryRelayAuth() {
        guard !isRunning else { return }
        relayAuthOverrides = [:]
        // Report-only sources have no app default: reset those to off too.
        relays = relays.map { relay in
            var value = relay
            value.auth = false
            return value
        }
        refreshHistoryRelayAuth()
        savePreferences()
    }

    private func recordArchived(_ result: YearReviewImportResult) {
        archivedCounts.fromYou += result.addedFromYou
        archivedCounts.fromOthers += result.addedFromOthers
    }

    func start(download: Bool, resume: Bool = false) {
        refreshHistoryRelayAuth()
        guard !isRunning, !isDeleting, let archive, !owner.isEmpty else { return }
        if download && selectedRelays.isEmpty {
            errorMessage = String(localized: "Choose at least one relay, or preview your saved history.")
            return
        }
        profileTask?.cancel()
        isRunning = true
        activities.removeAll()
        lastResponse = nil
        errorMessage = nil
        report = nil
        reportCollection = nil
        exportURL = nil
        let token = generation
        let owner = owner
        let trust = trusted
        let previous = resume ? collection : nil
        if download && !resume {
            collection = nil
#if DEBUG
            if debugTwoMonths {
                debugMonthChoice = Int.random(in: 0..<1_000_000)
                UserDefaults.standard.set(debugMonthChoice, forKey: "year-review-test-month-choice")
                UserDefaults.standard.set(YearReviewPeriod.testMonthStart(year: year, choice: debugMonthChoice),
                    forKey: "year-review-test-month-start-\(year)")
            }
#endif
        }
        let period = previous?.period ?? selectedPeriod(year: year)
        let sources = Array(relays.filter { selectedRelays.contains($0.url) }.prefix(20))
        task = Task { [self] in
            defer {
                if generation == token { isRunning = false; activities.removeAll(); task = nil }
            }
            do {
                stage = .local
                let counts = try await archive.archivedCounts()
                guard generation == token else { return }
                archivedCounts = counts
                let context = DataProvider.shared().newTaskContext()
                var offset = 0
                var invalidSeedEvents = 0
                while offset < YearReviewArchive.maximumEvents {
                    try Task.checkCancellation()
                    let batch = try await YearReviewLocalSeed.batch(owner: owner, period: period, offset: offset, context: context)
                    if batch.fetchedCount == 0 { break }
                    try await archive.recordLocalDeletions(batch.deletedIds)
                    let result: YearReviewImportResult
                    do {
                        result = try await archive.ingest(batch.events, source: "local-cache")
                    } catch YearReviewError.archiveLimit {
                        if download { throw YearReviewError.archiveLimit }
                        errorMessage = YearReviewError.archiveLimit.localizedDescription
                        break // Existing archived events remain previewable.
                    }
                    recordArchived(result)
                    invalidSeedEvents += result.invalid
                    offset += batch.fetchedCount
                    if batch.fetchedCount < 200 { break }
                }
                if download {
                    var job = previous ?? YearReviewCollection(owner: owner, period: period, relays: sources, trusted: trust)
                    // Authentication preferences can change before retrying a
                    // checkpoint that previously failed with auth-required.
                    job.relays = job.relays.map { saved in
                        .init(url: saved.url, auth: relays.first(where: { $0.url == saved.url })?.auth ?? saved.auth)
                    }
                    job.invalidEvents += invalidSeedEvents
                    if resume && job.pending.isEmpty && !job.failed.isEmpty {
                        let retryCategories = Set(job.failed.map(\.category))
                        job.pending = job.failed
                        job.failed = []
                        job.sourceFailures = nil
                        // Newly recovered posts can reveal new target IDs and parents.
                        if !retryCategories.isDisjoint(with: [.authored, .incoming, .supportIncoming, .rootIncoming, .outgoing, .outgoingZaps]) { job.phase = .primary }
                        else if !retryCategories.isDisjoint(with: [.references, .quoteReferences, .addressReferences]) { job.phase = .references }
                        else { job.phase = .parents }
                    }
                    try await collect(&job, archive: archive)
                    collection = job
                }
                try Task.checkCancellation()
                // Local parent resolution also makes saved-history-only previews useful.
                stage = .parents
                let inventory = try await archive.inventory(owner: owner, period: period)
                for ids in Array(inventory.missingParentIds.filter { YearReviewEvent.isHex($0, length: 64) }.prefix(20_000)).chunks(of: 128) {
                    try Task.checkCancellation()
                    let parents = try await YearReviewLocalSeed.parents(ids: ids, context: context)
                    try await archive.recordLocalDeletions(parents.deletedIds)
                    do {
                        let result = try await archive.ingest(parents.events, source: "local-cache")
                        recordArchived(result)
                    } catch YearReviewError.archiveLimit {
                        if download { throw YearReviewError.archiveLimit }
                        errorMessage = YearReviewError.archiveLimit.localizedDescription
                        break
                    }
                }
                activities.removeAll()
                stage = .zaps
                let zapperKeys = try await resolveZapProviders(archive: archive, period: period, sources: sources, context: context)
                stage = .analyzing
                let reportTrust = download ? collection?.trusted ?? trust : trust
                let revision = previewRevision
                let ownPosts = try await archive.inventory(owner: owner, period: period).ownPostIds
                try await seedCachedPostReactions(ids: ownPosts, archive: archive)
                let report = try await archive.report(owner: owner, period: period, trusted: reportTrust,
                                                     blocked: CloudBlocked.blockedPubkeys(), zapperKeys: zapperKeys)
                guard generation == token else { return }
                guard previewRevision == revision else { stage = .paused; return }
                let previews = try await loadPostPreviews(report: report, archive: archive)
                guard generation == token, previewRevision == revision else { return }
                postPreviews = previews
                self.report = report
                reportCollection = download ? collection : nil
                archivedCounts = try await archive.archivedCounts()
                let people = report.people
                names = Dictionary(uniqueKeysWithValues: Set(people).map {
                    ($0, Contact.fetchByPubkey($0, context: Nostur.context())?.anyName ?? String(npub($0).prefix(16)) + "…")
                })
                pictures = Dictionary(uniqueKeysWithValues: Set(people).compactMap { key in
                    Contact.fetchByPubkey(key, context: Nostur.context())?.pictureUrl.map { (key, $0) }
                })
                stage = .finished
                prepareHighlightedDetails(report: report, archive: archive)
                resolveMissingProfiles(people: people)
            } catch is CancellationError {
                if generation == token { stage = .paused }
            } catch {
                if generation == token { errorMessage = error.localizedDescription; stage = .paused }
            }
        }
    }

    // Metadata goes through the normal importer and profile cache, independently of analysis.
    private func resolveMissingProfiles(people: Set<String>) {
        let missing = people.filter { key in
            guard let contact = Contact.fetchByPubkey(key, context: Nostur.context()) else { return true }
            return contact.metadata_created_at == 0 || contact.pictureUrl == nil
                || (contact.name ?? "").isEmpty && (contact.display_name ?? "").isEmpty
        }
        guard !missing.isEmpty else { return }
        let owner = owner
        let sources = Array(relays.filter { selectedRelays.contains($0.url) && (collection?.pacing?.delay(for: $0.url) ?? 0) <= 3 }.prefix(3))
        profileTask = Task {
            for relay in sources {
                let limit = await YearReviewRelayLimits.shared.pageSize(for: relay.url)
                guard limit > 0 else { continue }
                for authors in Array(missing).sorted().chunks(of: min(64, limit)) {
                    guard !Task.isCancelled, AccountsState.shared.activeAccountPublicKey == viewer else { return }
                    do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
                    let id = "review-profiles-" + UUID().uuidString
                    let destinations: Set<RelayData> = [relay]
                    nxReq(Filters(authors: Set(authors), kinds: [0], limit: authors.count),
                        subscriptionId: id, relays: destinations, accountPubkey: owner)
                    try? await Task.sleep(for: .seconds(6))
                    req(ClientMessage.close(subscriptionId: id), relays: destinations, accountPubkey: owner)
                }
            }
        }
    }

    private func resolveZapProviders(archive: YearReviewArchive, period: YearReviewPeriod,
                                     sources: [RelayData], context: NSManagedObjectContext) async throws -> [String: Set<String>] {
        let signers = try await archive.zapSigners(period: period)
        let recipients = Set(signers.keys)
        zapStatus = "Checking zap providers: 0 of \(recipients.count)…"
        defer { zapStatus = nil }
        guard !recipients.isEmpty else { return [:] }
        var keys = try await archive.load([String: Set<String>].self, key: "zap-providers") ?? [:]
        let contacts: [YearReviewZapProvider] = try await context.perform {
            let query = Contact.fetchRequest()
            query.predicate = NSPredicate(format: "pubkey IN %@", Array(recipients))
            return try context.fetch(query).map { YearReviewZapProvider(pubkey: $0.pubkey, keys: $0.zapperPubkeys, lud16: $0.lud16, lud06: $0.lud06) }
        }
        var providers = try await archive.load([String: YearReviewZapProvider].self, key: "zap-provider-profiles") ?? [:]
        var checks = try await archive.load([String: YearReviewZapProviderCheck].self, key: "zap-provider-checks") ?? [:]
        for contact in contacts {
            if contact.endpoint == nil, let cached = providers[contact.pubkey] {
                providers[contact.pubkey] = YearReviewZapProvider(pubkey: contact.pubkey,
                    keys: contact.keys.union(cached.keys), lud16: cached.lud16, lud06: cached.lud06)
            } else { providers[contact.pubkey] = contact }
        }
        if let ownerProvider, providers[owner]?.endpoint == nil, ownerProvider.endpoint != nil {
            providers[owner] = YearReviewZapProvider(pubkey: owner, keys: providers[owner]?.keys ?? [],
                lud16: ownerProvider.lud16, lud06: ownerProvider.lud06)
        }
        var unknown = recipients.filter {
            providers[$0]?.endpoint == nil
                && !signers[$0, default: []].isSubset(of: keys[$0, default: []].union(providers[$0]?.keys ?? []))
                && (checks[$0]?.shouldRetry(endpoint: nil, signers: signers[$0, default: []]) ?? true)
        }
        if !unknown.isEmpty { zapStatus = "Finding Lightning profiles for \(unknown.count) people…" }
        for relay in sources.prefix(3) where !unknown.isEmpty && (collection?.pacing?.delay(for: relay.url) ?? 0) <= 3 {
            let limit = await YearReviewRelayLimits.shared.pageSize(for: relay.url)
            guard limit > 0 else { continue }
            for authors in Array(unknown).sorted().chunks(of: min(64, limit)) {
                try Task.checkCancellation()
                try await Task.sleep(for: .seconds(2.2))
                guard let page = try? await YearReviewRelayInbox.request(relay: relay,
                    filter: ["authors": authors, "kinds": [0], "limit": authors.count]) else { break }
                let discovered = await YearReviewZapProvider.from(events: page.events, authors: Set(authors))
                try Task.checkCancellation()
                for provider in discovered {
                    providers[provider.pubkey] = provider
                    unknown.remove(provider.pubkey)
                }
            }
        }
        try await archive.save(providers, key: "zap-provider-profiles")
        var checked = 0
        for recipient in recipients.sorted() {
            try Task.checkCancellation()
            zapStatus = "Checking zap providers: \(checked + 1) of \(recipients.count)…"
            defer { checked += 1 }
            let provider = providers[recipient]
            keys[recipient, default: []].formUnion(provider?.keys ?? [])
            if signers[recipient, default: []].isSubset(of: keys[recipient, default: []]) { continue }
            let endpoint = provider?.endpoint?.absoluteString
            guard checks[recipient]?.shouldRetry(endpoint: endpoint, signers: signers[recipient, default: []]) ?? true else { continue }
            if let provider {
                let resolved = await provider.resolve()
                try Task.checkCancellation()
                keys[recipient, default: []].formUnion(resolved)
                try await archive.save(keys, key: "zap-providers")
            }
            checks[recipient] = .init(checkedAt: .now, endpoint: endpoint, signers: signers[recipient, default: []])
            try await archive.save(checks, key: "zap-provider-checks")
            if provider?.endpoint != nil { try await Task.sleep(for: .seconds(1)) }
        }
        try await archive.save(keys, key: "zap-providers")
        return keys
    }

    private func collect(_ job: inout YearReviewCollection, archive: YearReviewArchive) async throws {
        var requestsThisRun = 0
        var timedPhase = job.phase
        var phaseStartedAt = Date.now
        let timeLimitMessage = String(localized: "Your month scans are saved. Some extra checks remain; resume later to improve the report.")
        job.issues.removeAll { $0 == timeLimitMessage }
        var unavailableThisRun = Set<String>()
        var failuresThisRun: [String: YearReviewSourceFailure] = [:]
        if let previous = try await archive.load(YearReviewRelayPacing.self, key: "relay-pacing") {
            var pacing = job.pacing ?? YearReviewRelayPacing()
            for (relay, date) in previous.nextRequest { pacing.nextRequest[relay] = max(date, pacing.nextRequest[relay, default: .distantPast]) }
            for (relay, count) in previous.failures { pacing.failures[relay] = max(count, pacing.failures[relay, default: 0]) }
            job.pacing = pacing
        }
        livePacing = job.pacing ?? YearReviewRelayPacing()
        try await archive.save(job, key: checkpointKey(job.period))
        collection = job
        while true {
            try Task.checkCancellation()
            if job.pending.isEmpty {
                switch job.phase {
                case .primary:
                    stage = .references
                    let inventory = try await archive.inventory(owner: job.owner, period: job.period)
                    job.phase = .references
                    let targets = inventory.ownPostIds // Do not backfill everyone else’s reactions to posts we merely liked.
                    for relay in job.relays {
                        for ids in targets.chunks(of: 64) {
                            for kinds in [Array(YearReviewKinds.content.union(YearReviewKinds.support)).sorted()] {
                                job.pending.append(YearReviewWork(relay: relay.url, category: .references,
                                    since: job.period.start, until: job.period.end - 1, ids: ids, kinds: kinds))
                            }
                            job.pending.append(YearReviewWork(relay: relay.url, category: .quoteReferences,
                                since: job.period.start, until: job.period.end - 1, ids: ids))
                        }
                        for ids in inventory.ownCoordinates.chunks(of: 64) {
                            job.pending.append(YearReviewWork(relay: relay.url, category: .addressReferences,
                                since: job.period.start, until: job.period.end - 1, ids: ids))
                            job.pending.append(YearReviewWork(relay: relay.url, category: .quoteReferences,
                                since: job.period.start, until: job.period.end - 1, ids: ids))
                        }
                    }
                case .references:
                    stage = .parents
                    let inventory = try await archive.inventory(owner: job.owner, period: job.period)
                    let missing = Array(inventory.missingParentIds.prefix(20_000))
                    job.parentsLimited = inventory.missingParentIds.count > 20_000
                    job.phase = .parents
                    for relay in job.relays {
                        for ids in Array(missing.filter { YearReviewEvent.isHex($0, length: 64) }.prefix(20_000)).chunks(of: 64) {
                            job.pending.append(YearReviewWork(relay: relay.url, category: .parents,
                                since: 0, until: job.period.end - 1, ids: ids))
                        }
                        for address in missing.filter({ !YearReviewEvent.isHex($0, length: 64) }).prefix(20_000) {
                            job.pending.append(YearReviewWork(relay: relay.url, category: .parents,
                                since: 0, until: job.period.end - 1, ids: [address]))
                        }
                    }
                case .parents: job.phase = .finished
                case .finished:
                    try await archive.save(job, key: checkpointKey(job.period))
                    collection = job
                    return
                }
                try await archive.save(job, key: checkpointKey(job.period))
                collection = job
                continue
            }
            if timedPhase != job.phase {
                timedPhase = job.phase
                phaseStartedAt = .now
            }
            if !YearReviewCollection.canContinueSupplementaryWork(phase: job.phase, startedAt: phaseStartedAt) {
                job.recordIssue(timeLimitMessage)
                try await archive.save(job, key: checkpointKey(job.period))
                collection = job
                return // Show saved results; remaining extra checks stay resumable.
            }
            // Bound one foreground session; Resume continues the durable work list.
            guard requestsThisRun < 1_200 else {
                try await archive.save(job, key: checkpointKey(job.period))
                collection = job
                job.recordIssue(String(localized: "Your history is saved. Resume to continue gathering the remaining sources."))
                try await archive.save(job, key: checkpointKey(job.period))
                collection = job
                return // Produce a useful partial report instead of discarding the preview.
            }
            guard AccountsState.shared.activeAccountPublicKey == viewer else { throw CancellationError() }
            let cooled = job.pending.filter { (job.pacing ?? YearReviewRelayPacing()).delay(for: $0.relay) > 3 }.map(\.relay)
            unavailableThisRun.formUnion(cooled)
            if !cooled.isEmpty { job.recordIssue(String(localized: "A relay is cooling down. Resume later to collect its remaining history.")) }
            for relay in Set(job.pending.filter { unavailableThisRun.contains($0.relay) }.map(\.relay)) {
                let cause = failuresThisRun[relay]
                job.markRelayUnavailable(relay,
                    reason: cause?.reason ?? String(localized: "This relay is cooling down after an earlier failure. Retry later."),
                    trigger: cause?.work)
            }
            if job.pending.isEmpty { continue }
            let batch = Array(job.nextBatch(excluding: unavailableThisRun).prefix(1_200 - requestsThisRun))
            guard !batch.isEmpty else { continue }
            switch batch[0].category {
            case .authored: stage = .posts
            case .incoming, .supportIncoming, .rootIncoming, .outgoing, .outgoingZaps: stage = .interactions
            case .references, .quoteReferences, .addressReferences: stage = .references
            case .parents: stage = .parents
            }
            let batchOwner = job.owner
            let zone = job.period.timeZoneIdentifier
            var prepared: [(YearReviewWork, YearReviewCollection.RelayDataSnapshot)] = []
            for work in batch {
                guard let relay = job.relays.first(where: { $0.url == work.relay }) else { throw YearReviewError.database("relay") }
                activities[work.relay] = YearReviewActivity(work: work, timeZoneIdentifier: zone, step: .pacing)
                prepared.append((work, relay))
            }
            // Work stays pending until each response commits; cancellation can safely resume it.
            try await archive.save(job, key: checkpointKey(job.period))
            try await withThrowingTaskGroup(of: YearReviewFetchResult.self) { group in
                var activeRequests = prepared.count
                for (work, relay) in prepared {
                    let notBefore = (job.pacing ?? YearReviewRelayPacing()).nextRequest[work.relay] ?? .distantPast
                    group.addTask { @MainActor [self] in
                        try await fetchHistory(work: work, relay: relay, owner: batchOwner, zone: zone, notBefore: notBefore, archive: archive)
                    }
                }
                for try await response in group {
                    activeRequests -= 1
                    let work = response.work
                    // Pace from actual dispatch, including time spent discovering relay limits.
                    job.pacing = livePacing
                    switch response.result {
                    case .success(let page):
                        activities[work.relay]?.received = page.events.count
                        activities[work.relay]?.step = .saving
                        activities[work.relay]?.startedAt = .now
                        let matching = page.events.filter { work.accepts($0, owner: batchOwner) }
                        let result = try await archive.ingest(matching, source: work.relay)
                        lastResponse = (received: page.events.count, added: result.added)
                        recordArchived(result)
                        job.invalidEvents += result.invalid + page.events.count - matching.count
                        if let index = job.pending.firstIndex(of: work) { job.pending.remove(at: index) }
                        if work.category == .parents {
                            let returned = Set(matching.map(\.id))
                            let remaining = work.ids.filter { YearReviewEvent.isHex($0, length: 64) && !returned.contains($0) }
                            if !matching.isEmpty && !remaining.isEmpty {
                                job.pending.insert(YearReviewWork(relay: work.relay, category: .parents,
                                    since: work.since, until: work.until, ids: remaining), at: 0)
                            }
                        } else if !page.isExhaustive {
                            if page.hasMore || page.events.count >= response.limit {
                                let parts = work.adaptiveSubdivisions(timeZoneIdentifier: zone)
                                if parts.isEmpty {
                                    job.failed.append(work)
                                    job.sourceFailures = job.sourceFailures ?? []
                                    job.sourceFailures?.append(.init(work: work, status: .capped,
                                        reason: String(localized: "The relay capped a one-second history window. Splitting it further cannot safely recover the remaining items."),
                                        trigger: work, received: page.events.count, date: .now))
                                    job.recordIssue(String(localized: "A source capped one timestamp. Some history remains unresolved."))
                                } else { job.pending.insert(contentsOf: parts, at: 0) }
                            } else if !page.events.isEmpty {
                                // A short response is an estimate, not proof against an unadvertised relay cap.
                                job.estimatedResponses += 1
                            }
                        }
                        job.requestsChecked += 1
                        if job.phase == .references { job.referenceQueriesChecked = (job.referenceQueriesChecked ?? 0) + 1 }
                        job.recordMonthlyQuery(work)
                    case .failure(let error):
                        livePacing.failed(work.relay)
                        job.pacing = livePacing
                        unavailableThisRun.insert(work.relay)
                        let received = activities[work.relay]?.received ?? 0
                        failuresThisRun[work.relay] = .init(work: work, status: .failed,
                            reason: error.localizedDescription, trigger: work, received: received, date: .now)
                        job.markRelayUnavailable(work.relay, reason: error.localizedDescription, trigger: work, received: received)
                        job.recordIssue(String(localized: "One or more relays could not finish. Retry incomplete sources to gather more history."))
                    }
                    requestsThisRun += 1
                    job.recordMonthlyReceived(work, count: activities[work.relay]?.received ?? 0)
                    activities.removeValue(forKey: work.relay)
                    collection = job
                    job.pacing = livePacing
                    try await archive.savePacing(livePacing)
                    try await archive.save(job, key: checkpointKey(job.period))
                    collection = job
                    // Refill this relay immediately, instead of waiting for the slowest peer.
                    if requestsThisRun + activeRequests < 1_200,
                       YearReviewCollection.canContinueSupplementaryWork(phase: job.phase, startedAt: phaseStartedAt),
                       !unavailableThisRun.contains(work.relay),
                       let next = job.nextWork(for: work.relay, inMonthOf: batch[0]),
                       let relay = job.relays.first(where: { $0.url == work.relay }) {
                        let notBefore = (job.pacing ?? YearReviewRelayPacing()).nextRequest[work.relay] ?? .distantPast
                        activities[work.relay] = YearReviewActivity(work: next, timeZoneIdentifier: zone, step: .pacing)
                        activeRequests += 1
                        group.addTask { @MainActor [self] in
                            try await fetchHistory(work: next, relay: relay, owner: batchOwner, zone: zone, notBefore: notBefore, archive: archive)
                        }
                    }
                }
            }
        }
    }

    private func fetchHistory(work: YearReviewWork, relay: YearReviewCollection.RelayDataSnapshot,
                              owner: String, zone: String, notBefore: Date, archive: YearReviewArchive) async throws -> YearReviewFetchResult {
        try Task.checkCancellation()
        activities[work.relay] = YearReviewActivity(work: work, timeZoneIdentifier: zone, step: .pacing)
        let delay = notBefore.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        activities[work.relay]?.step = .relayInfo
        activities[work.relay]?.startedAt = .now
        let limit = await YearReviewRelayLimits.shared.pageSize(for: work.relay)
        try Task.checkCancellation()
        let dispatchedAt = Date.now
        livePacing.started(work.relay, now: dispatchedAt, jitter: 0.5)
        try await archive.savePacing(livePacing)
        try Task.checkCancellation()
        activities[work.relay]?.step = .fetching
        activities[work.relay]?.startedAt = dispatchedAt
        do {
            guard limit > 0 else { throw YearReviewError.relay(String(localized: "This relay does not allow historical queries.")) }
            var filter = work.filter(owner: owner)
            filter["limit"] = limit
            let page = try await YearReviewRelayInbox.request(relay: relay.relayData, filter: filter) { [weak self] count in
                guard self?.activities[work.relay]?.work == work else { return }
                self?.activities[work.relay]?.received = count
            }
            try Task.checkCancellation()
            return YearReviewFetchResult(work: work, limit: limit, dispatchedAt: dispatchedAt, result: .success(page))
        } catch is CancellationError { throw CancellationError() }
        catch { return YearReviewFetchResult(work: work, limit: limit, dispatchedAt: dispatchedAt, result: .failure(error)) }
    }

    private func loadPostPreviews(report: YearReviewReport, archive: YearReviewArchive) async throws -> [String: YearReviewPostPreview] {
        let ids = Set([report.conversation, report.mostReacted, report.mostZapped, report.mostZapValue].compactMap { $0?.id })
        var events: [YearReviewEvent] = []
        for id in ids { if let event = try await archive.event(id: id) { events.append(event) } }
        let snapshots = events
        let context = DataProvider.shared().newTaskContext()
        return try await context.perform {
            defer { context.reset() } // Preview objects never enter the feed database or relation queues.
            return try Dictionary(uniqueKeysWithValues: snapshots.map { snapshot in
                (snapshot.id, try YearReviewPostPreview.build(snapshot: snapshot, context: context))
            })
        }
    }

    /// Promote only the tapped archived post to the normal detail-view cache.
    func postForNavigation(_ post: YearReviewPost) async throws -> NRPost? {
        guard let snapshot = try await archive?.event(id: post.id) else { return nil }
        let context = bg()
        return try await context.perform {
            let event: Event
            if let existing = Event.fetchEvent(id: post.id, context: context) { event = existing }
            else {
                let original = try JSONDecoder().decode(NEvent.self, from: JSONEncoder().encode(snapshot))
                event = Event.saveEvent(event: original, context: context)
                DataProvider.shared().saveToDiskNow(.bgContext)
            }
            return NRPost(event: event, withReplyTo: true)
        }
    }

    private func seedCachedPostReactions(ids: [String], archive: YearReviewArchive) async throws {
        let cache = DataProvider.shared().newTaskContext()
        for targets in ids.chunks(of: 128) {
            var cursor = ""
            while true {
                try Task.checkCancellation()
                let page = try await YearReviewLocalSeed.postReactions(ids: targets, after: cursor, context: cache)
                guard let last = page.lastId, last != cursor else { break }
                cursor = last
                _ = try await archive.ingest(page.events, source: "local-post-reactions")
                try await archive.recordLocalDeletions(page.deletedIds)
                await cache.perform { cache.reset() }
            }
        }
    }

    private func refreshMostLovedCount() {
        guard let post = report?.mostReacted, let archive else { return }
        reactionRefresh?.cancel()
        let token = generation
        reactionRefresh = Task {
            do {
                try await seedCachedPostReactions(ids: [post.id], archive: archive)
                let count = try await archive.reactionCount(to: post.id, blocked: CloudBlocked.blockedPubkeys())
                guard !Task.isCancelled, generation == token, report?.mostReacted?.id == post.id else { return }
                report?.mostReacted?.reactions = count
            } catch is CancellationError { }
            catch { if generation == token { errorMessage = error.localizedDescription } }
        }
    }

    private func prepareHighlightedDetails(report: YearReviewReport, archive: YearReviewArchive) {
        detailTask?.cancel()
        let posts = enabledCards.compactMap { $0.post(in: report) }.uniqued(on: { $0.id })
        let blocked = AppState.shared.bgAppState.blockedPubkeys
        let token = generation
        detailTask = Task {
            do {
                for post in posts {
                    try Task.checkCancellation()
                    try await YearReviewDetailHydrator.restore(post: post, archive: archive, blocked: blocked, context: bg())
                }
            } catch is CancellationError { }
            catch { if generation == token { errorMessage = error.localizedDescription } }
        }
    }

    /// Runs after navigation; only the selected highlight is copied into the feed cache.
    func loadArchivedDetails(for post: YearReviewPost, displayedPost: NRPost?) async throws {
        guard let archive else { return }
        let blocked = AppState.shared.bgAppState.blockedPubkeys
        try await YearReviewDetailHydrator.restore(post: post, archive: archive, blocked: blocked, context: bg())
        displayedPost?.loadGroupedReplies()
        refreshMostLovedCount()
    }

    func pause() { task?.cancel(); detailTask?.cancel(); reactionRefresh?.cancel() }

    func invalidatePreview() {
        profileTask?.cancel()
        previewRevision += 1
        report = nil
        reportCollection = nil
        if !isRunning { stage = .ready }
    }

    func recordDeletion(_ id: String) {
        invalidatePreview()
        guard let archive else { return }
        let token = generation
        Task {
            do { try await archive.recordLocalDeletions([id]) }
            catch { if generation == token { errorMessage = error.localizedDescription } }
        }
    }

    func selectYear() async {
        guard !isRunning, let archive else { return }
        profileTask?.cancel()
        report = nil
        collection = nil
        reportCollection = nil
        stage = .ready
        let requestedYear = year
        let token = generation
        do {
            let saved = try await archive.load(YearReviewCollection.self, key: checkpointKey(selectedPeriod(year: requestedYear)))
            if generation == token, year == requestedYear, saved?.schemaVersion == 3 { collection = saved }
        } catch { errorMessage = error.localizedDescription }
    }

    func exportArchive() {
        guard let archive, !isExporting, !isDeleting else { return }
        isExporting = true
        errorMessage = nil
        let token = generation
        Task {
            defer { if generation == token { isExporting = false } }
            do {
                let url = try await archive.export()
                if generation == token { exportURL = url }
            } catch { if generation == token { errorMessage = error.localizedDescription } }
        }
    }

    func deleteArchive() {
        let target = owner
        Task {
            do { try await deleteArchive(owner: target) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func deleteArchive(owner target: String) async throws {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        let token = generation
        if target == owner {
            profileTask?.cancel()
            pause()
            await task?.value
            await detailTask?.value
            await reactionRefresh?.value
        }
        // Finish pending capture first so old queued events cannot immediately
        // recreate an archive that the user just cleared. A failing archive can
        // still be deleted to recover from a corrupt/full store.
        try await YearReviewArchives.shared.clear(owner: target)
        if generation == token, target == owner {
            report = nil; collection = nil; reportCollection = nil
            archivedCounts = YearReviewArchivedCounts(); exportURL = nil; stage = .ready
        }
    }

}

private extension Array {
    func chunks(of count: Int) -> [[Element]] {
        stride(from: 0, to: self.count, by: count).map { Array(self[$0..<Swift.min($0 + count, self.count)]) }
    }
}
