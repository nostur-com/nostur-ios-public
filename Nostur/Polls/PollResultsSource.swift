import Foundation

struct PollRelayCursor: Equatable, Sendable {
    let until: Int
    let boundaryIDs: Set<String>
}

struct PollResultsSource: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case pending, loading, checked, failed, moreAvailable, limited
    }

    let id: String
    var status: Status = .pending
    var lastChecked: Date?
    var cursor: PollRelayCursor?
    var failure: PollRelayFailure?

    mutating func record(_ result: PollRelayResult, at date: Date = .now) {
        lastChecked = date
        failure = nil
        if result.complete {
            status = .checked
            cursor = nil
        } else if let next = result.nextCursor {
            status = .moreAvailable
            cursor = next
        } else if result.hitBoundaryLimit {
            status = .limited
            cursor = nil
        } else {
            status = .failed
            failure = result.failure ?? PollRelayFailure(.unknown)
            // Keep the previous cursor so a failed continuation can be retried.
        }
    }
}

enum PollResultsRequest: Equatable, Sendable {
    case refresh, moreRelays, retryFailed, moreResponses
}

extension PollResultsRequest {
    func selection(from plan: PollRelayPlan.Query, previous: [PollResultsSource],
                   approved: inout Set<String>) -> (sources: [PollResultsSource], relays: [String]) {
        let pending = (plan.relays + plan.more).filter { url in
            (previous.first { $0.id == url }?.status ?? .pending) == .pending
        }
        let nextRelays = Array(pending.prefix(PollRelayPlan.maximumForeign))
        if self == .moreRelays {
            approved.formUnion(nextRelays.filter { plan.more.contains($0) })
        }
        let allowed = plan.relays + plan.more.filter { approved.contains($0) }
        let sources = (plan.relays + plan.more).map { url in
            previous.first { $0.id == url } ?? PollResultsSource(id: url)
        }
        let relays = allowed.filter { url in
            let status = sources.first { $0.id == url }?.status
            switch self {
            case .refresh: return true
            case .moreRelays: return nextRelays.contains(url) && status == .pending
            case .retryFailed: return status == .failed
            case .moreResponses: return status == .moreAvailable
            }
        }
        return (sources, relays)
    }
}

struct PollRelayAuthentication: Sendable {
    let publicKey: String
    let sign: @Sendable (NEvent) async throws -> NEvent
}

struct PollRelayFailure: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case authenticationRequired, authenticationRejected, signingFailed, requestRejected
        case timedOut, connectionFailed, invalidResponse, responseLimit, cancelled, unknown
    }

    let kind: Kind
    var detail: String?

    init(_ kind: Kind, detail: String? = nil) {
        self.kind = kind
        self.detail = detail.map { String($0.components(separatedBy: .controlCharacters).joined(separator: " ").prefix(240)) }
    }

    var title: String {
        switch kind {
        case .authenticationRequired: return String(localized: "Authentication required")
        case .authenticationRejected: return String(localized: "Relay rejected authentication")
        case .signingFailed: return String(localized: "Couldn’t sign relay authentication")
        case .requestRejected: return String(localized: "Relay rejected the request")
        case .timedOut: return String(localized: "Relay request timed out")
        case .connectionFailed: return String(localized: "Relay connection failed")
        case .invalidResponse: return String(localized: "Unreadable relay response")
        case .responseLimit: return String(localized: "Relay didn’t finish its response")
        case .cancelled: return String(localized: "Check cancelled")
        case .unknown: return String(localized: "Relay check failed without a reason")
        }
    }
}
