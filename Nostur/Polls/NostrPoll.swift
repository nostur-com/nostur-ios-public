import Foundation

/// Immutable protocol values. Never pass managed events into the poll loader.
struct NostrPoll: Sendable {
    struct Option: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
    }

    let id: String
    let createdAt: Int
    let options: [Option]
    let multipleChoice: Bool
    let endsAt: Int?
    let relays: [String]
    let isSupported: Bool

    init(id: String, createdAt: Int, tags: [[String]]) {
        self.id = id
        self.createdAt = createdAt
        var seen = Set<String>()
        options = tags.compactMap { tag in
            guard tag.count >= 3, tag[0] == "option", !tag[1].isEmpty,
                  !tag[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(tag[1]).inserted else { return nil }
            return Option(id: tag[1], label: tag[2])
        }
        let type = tags.first { $0.first == "polltype" }?.dropFirst().first ?? "singlechoice"
        multipleChoice = type == "multiplechoice"
        let endTag = tags.first { $0.first == "endsAt" }
        endsAt = endTag.flatMap { $0.count > 1 ? Int($0[1]) : nil }
        isSupported = ["singlechoice", "multiplechoice"].contains(type)
            && options.count >= 2 && (endTag == nil || endsAt != nil)
        relays = Self.relayURLs(tags.filter { $0.first == "relay" && $0.count > 1 }.map { $0[1] })
    }

    func hasEnded(at now: Int) -> Bool { endsAt.map { now > $0 } ?? false }

    /// Preserve case-sensitive paths; normalize only the scheme/host and a root slash.
    static func relayURLs(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard var parts = URLComponents(string: candidate),
                  let scheme = parts.scheme?.lowercased(), ["ws", "wss"].contains(scheme),
                  let host = parts.host, !host.isEmpty, !host.contains(","),
                  parts.user == nil, parts.password == nil, parts.fragment == nil,
                  !candidate.contains(where: { $0.isWhitespace }) else { return nil }
            parts.scheme = scheme
            parts.host = host.lowercased()
            if parts.path == "/" { parts.path = "" }
            guard let url = parts.url?.absoluteString, seen.insert(url).inserted else { return nil }
            return url
        }
    }
}

struct PollVote: Identifiable, Equatable, Sendable {
    let id: String
    let pubkey: String
    let createdAt: Int
    let responses: [String]

    init(id: String, pubkey: String, createdAt: Int, responses: [String]) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.responses = responses
    }

    init(event: NEvent) {
        self.init(id: event.id, pubkey: event.publicKey, createdAt: event.createdAt.timestamp,
                  responses: event.tags.filter { $0.type == "response" }.map(\.value))
    }
}

struct PollTally: Sendable {
    let votes: [PollVote]
    let votersByOption: [String: [PollVote]]
    var totalVoters: Int { votes.count }

    func voters(for optionID: String?) -> [PollVote] {
        guard let optionID else { return votes }
        return votersByOption[optionID] ?? []
    }

    func filtered(to pubkeys: Set<String>) -> PollTally {
        PollTally(countedVotes: votes.filter { pubkeys.contains($0.pubkey) })
    }

    private init(countedVotes: [PollVote]) {
        votes = countedVotes
        votersByOption = Dictionary(grouping: countedVotes.flatMap { vote in
            vote.responses.map { ($0, vote) }
        }, by: { $0.0 }).mapValues { $0.map { $0.1 } }
    }

    init(poll: NostrPoll, votes: [PollVote], now: Int) {
        var latest: [String: PollVote] = [:]
        for vote in votes where vote.createdAt >= poll.createdAt && vote.createdAt <= now
            && (poll.endsAt == nil || vote.createdAt <= poll.endsAt!) {
            if let previous = latest[vote.pubkey],
               previous.createdAt > vote.createdAt || (previous.createdAt == vote.createdAt && previous.id <= vote.id) {
                continue
            }
            // Select the latest event before interpreting its responses; an invalid first
            // response must not make a later tag count in a single-choice poll.
            latest[vote.pubkey] = vote
        }
        let validIDs = Set(poll.options.map(\.id))
        let counted = latest.values.compactMap { vote -> PollVote? in
            let candidates = poll.multipleChoice ? vote.responses : Array(vote.responses.prefix(1))
            var seen = Set<String>()
            let responses = candidates.filter { validIDs.contains($0) && seen.insert($0).inserted }
            guard !responses.isEmpty else { return nil }
            return PollVote(id: vote.id, pubkey: vote.pubkey, createdAt: vote.createdAt, responses: responses)
        }.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
        self.votes = counted
        var byOption: [String: [PollVote]] = [:]
        for vote in counted {
            for response in vote.responses { byOption[response, default: []].append(vote) }
        }
        votersByOption = byOption
    }
}
