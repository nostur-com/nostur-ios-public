import Foundation

@MainActor
final class PollViewModel: ObservableObject {
    let poll: NostrPoll
    @Published private(set) var tally: PollTally
    @Published private(set) var isLoading = false
    @Published private(set) var isPublishing = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var isPartial = false
    @Published private(set) var moreRelays: [String] = []
    @Published private(set) var error: String?
    private var responses: [PollVote] = []
    private var lastLoadedAccount: String?
    private var lastLoaded: Date?
    private var checkingMoreRelays = false
    private(set) var authorPubkey: String?

    // Share acknowledged votes and loading state between feed, embeds and detail.
    private static var models: [String: PollViewModel] = [:]
    private static var order: [String] = []

    static func model(for poll: NostrPoll) -> PollViewModel {
        if let model = models[poll.id] { return model }
        let model = PollViewModel(poll: poll)
        models[poll.id] = model
        order.append(poll.id)
        if order.count > 24 { models.removeValue(forKey: order.removeFirst()) }
        return model
    }

    init(poll: NostrPoll, initialVotes: [PollVote]? = nil) {
        self.poll = poll
        responses = initialVotes ?? []
        tally = PollTally(poll: poll, votes: responses, now: Int(Date().timeIntervalSince1970))
        hasLoaded = initialVotes != nil
    }

    func rememberAuthor(_ pubkey: String) {
        guard !pubkey.isEmpty, authorPubkey != pubkey else { return }
        authorPubkey = pubkey
        lastLoaded = nil
    }

    func load(accountPubkey: String, force: Bool = false, includeMoreRelays: Bool = false) async {
        if includeMoreRelays { checkingMoreRelays = true }
        let expand = includeMoreRelays
        // A feed card can disappear just as its detail opens. Wait asynchronously for
        // that caller to finish/cancel, then retry rather than leaving detail unloaded.
        while isLoading {
            do { try await Task.sleep(nanoseconds: 100_000_000) }
            catch { return }
        }
        guard !Task.isCancelled, poll.isSupported,
              force || expand || lastLoadedAccount != accountPubkey || lastLoaded == nil || Date().timeIntervalSince(lastLoaded!) > 30 else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        let author = authorPubkey ?? ""
        let isOwn = !author.isEmpty && author == accountPubkey
        if !accountPubkey.isEmpty {
            let archived = await PollArchive.shared.votes(owner: accountPubkey, pollID: poll.id)
            if !archived.isEmpty {
                responses = await PollRelayClient.shared.merge(responses, archived)
                tally = await PollRelayClient.shared.tally(poll: poll, votes: responses)
                hasLoaded = true
            }
        }
        guard !Task.isCancelled else { return }
        let plan = PollRelayContext.query(accountPubkey: accountPubkey, authorPubkey: author,
                                          eventRelays: poll.relays, includeMore: checkingMoreRelays)
        moreRelays = plan.more
        let relays = plan.relays
        guard !relays.isEmpty else {
            isPartial = !moreRelays.isEmpty
            if !hasLoaded {
                error = String(localized: "No available relays for this poll.")
            }
            return
        }
        let poll = self.poll
        let results = await withTaskGroup(of: PollRelayResult.self) { group in
            for relay in relays {
                group.addTask { await PollRelayClient.shared.fetch(poll: poll, relay: relay, author: nil) }
            }
            var results: [PollRelayResult] = []
            for await result in group { results.append(result) }
            return results
        }
        guard !Task.isCancelled else { return }
        var received = results.flatMap(\.votes)
        // A busy poll's page limit must not hide the account's existing vote.
        if !accountPubkey.isEmpty && results.contains(where: { !$0.complete }) {
            let ownResults = await withTaskGroup(of: PollRelayResult.self) { group in
                for relay in relays {
                    group.addTask { await PollRelayClient.shared.fetch(poll: poll, relay: relay, author: accountPubkey) }
                }
                var votes: [PollVote] = []
                for await result in group { votes.append(contentsOf: result.votes) }
                return votes
            }
            received.append(contentsOf: ownResults)
        }
        guard !Task.isCancelled else { return }
        if isOwn && !accountPubkey.isEmpty {
            await PollArchive.shared.saveResults(owner: accountPubkey, pollID: poll.id, jsons: results.flatMap(\.eventJSON))
        }
        responses = await PollRelayClient.shared.merge(responses, received)
        tally = await PollRelayClient.shared.tally(poll: poll, votes: responses)
        hasLoaded = hasLoaded || results.contains(where: \.reachedRelay)
        isPartial = !moreRelays.isEmpty || results.contains { !$0.complete }
        if results.contains(where: \.reachedRelay) {
            lastLoaded = Date()
            lastLoadedAccount = accountPubkey
            error = nil
        } else {
            error = String(localized: "Couldn’t load all poll results. Try again.")
        }
    }

    func vote(selection: Set<String>, accountPubkey: String) async -> Bool {
        guard !isPublishing, !selection.isEmpty, poll.isSupported else { return false }
        error = nil
        let now = Int(Date().timeIntervalSince1970)
        guard !poll.hasEnded(at: now) else { return false }
        guard let account = account(), account.publicKey == accountPubkey, account.isFullAccount else {
            error = String(localized: "Sign in with a signing account to vote.")
            return false
        }
        if let previous = tally.votes.first(where: { $0.pubkey == accountPubkey }), previous.createdAt >= now {
            error = String(localized: "Please wait a moment before changing your vote.")
            return false
        }
        let ordered = poll.options.map(\.id).filter { selection.contains($0) }
        guard !ordered.isEmpty, poll.multipleChoice || ordered.count == 1 else { return false }
        isPublishing = true
        defer { isPublishing = false }
        do {
            var tags = [NostrTag(["e", poll.id])]
            if let author = authorPubkey, !author.isEmpty {
                tags.append(NostrTag(["p", author]))
            }
            tags.append(contentsOf: ordered.map { NostrTag(["response", $0]) })
            let event = NEvent(publicKey: accountPubkey, content: "", kind: .pollResponse, tags: tags)
            let signed = try await PollSigningRequest.sign(event, accountPubkey: accountPubkey)
            guard AccountsState.shared.activeAccountPublicKey == accountPubkey,
                  !poll.hasEnded(at: Int(Date().timeIntervalSince1970)) else { return false }
            guard signed.publicKey == accountPubkey, signed.kind == event.kind,
                  signed.tags.map(\.tag) == event.tags.map(\.tag), signed.content == event.content,
                  signed.createdAt.timestamp == event.createdAt.timestamp,
                  await PollRelayClient.shared.isVerified(signed) else {
                error = String(localized: "The signer returned an invalid vote. Try again.")
                return false
            }
            responses = await PollRelayClient.shared.merge(responses, [PollVote(event: signed)])
            tally = await PollRelayClient.shared.tally(poll: poll, votes: responses)
            await PollArchive.shared.save(owner: accountPubkey, json: signed.eventJson())
            // Same write relays as a post. The p tag lets outbox reach the author's read relays.
            Unpublisher.shared.publishNow(signed, skipDB: true)
            return true
        } catch {
            self.error = String(localized: "Couldn’t sign your vote. Try again.")
            return false
        }
    }
}

extension PollRelayClient {
    func isVerified(_ event: NEvent) -> Bool { (try? event.verified(logInvalidID: false)) == true }

    func merge(_ previous: [PollVote], _ incoming: [PollVote]) -> [PollVote] {
        var latest: [String: PollVote] = [:]
        for vote in previous + incoming {
            if let old = latest[vote.pubkey], old.createdAt > vote.createdAt
                || (old.createdAt == vote.createdAt && old.id <= vote.id) { continue }
            latest[vote.pubkey] = vote
        }
        return Array(latest.values)
    }

    func tally(poll: NostrPoll, votes: [PollVote]) -> PollTally {
        PollTally(poll: poll, votes: votes, now: Int(Date().timeIntervalSince1970))
    }
}

/// Existing remote signing can outlive the screen or never call back. Bound the UI's
/// wait without blocking a queue, and ignore a callback after timeout/cancellation.
@MainActor
final class PollSigningRequest {
    private var continuation: CheckedContinuation<NEvent, Error>?

    private func finish(_ result: Result<NEvent, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    static func sign(_ event: NEvent, accountPubkey: String) async throws -> NEvent {
        try await wait {
            try await Nostur.sign(nEvent: event, accountPubkey: accountPubkey)
        }
    }

    static func wait(timeoutNanoseconds: UInt64 = 15_000_000_000,
                     operation: @escaping @MainActor () async throws -> NEvent) async throws -> NEvent {
        let request = PollSigningRequest()
        let timeout = Task {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                request.finish(.failure(SignEventError.timeout))
            } catch { }
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                request.continuation = continuation
                Task {
                    do {
                        let signed = try await operation()
                        request.finish(.success(signed))
                    } catch { request.finish(.failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor in request.finish(.failure(CancellationError())) }
        }
    }
}
