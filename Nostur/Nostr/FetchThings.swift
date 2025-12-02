//
//  FetchThings.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import Foundation
import NostrEssentials
import CoreData

func relayReq(_ filter: NostrEssentials.Filters,
              timeout: Double? = 2.5,
              debounceTime: Double? = 0.05,
              isActiveSubscription: Bool = false,
              relays: Set<RelayData> = [],
              accountPubkey: String? = nil,
              relayType: NosturClientMessage.RelayType = .READ,
              useOutbox: Bool = false) async throws -> ReqReturn {
    return try await withCheckedThrowingContinuation({ continuation in
        let reqTask = ReqTask(
            debounceTime: debounceTime ?? 0.05,
            timeout: timeout,
            reqCommand: { taskId in
#if DEBUG
                L.og.debug("⏳⏳ Backlog.shared: Sending request with taskId: \(taskId), timeout: \(timeout?.description ?? "")")
#endif
                nxReq(filter,
                      subscriptionId: taskId,
                      isActiveSubscription: isActiveSubscription,
                      relays: relays,
                      accountPubkey: accountPubkey,
                      relayType: relayType,
                      useOutbox: useOutbox
                )
            },
            processResponseCommand: { taskId, relayMessage, event in
#if DEBUG
                L.og.debug("⏳⏳ Backlog.shared: Received response for taskId: \(taskId), event: \(event?.id ?? "none")")
#endif
                continuation.resume(returning: ReqReturn(taskId: taskId, relayMessage: relayMessage, event: event))
            },
            timeoutCommand: { taskId in
#if DEBUG
                L.og.debug("⏳⏳ Backlog.shared: Timeout triggered for taskId: \(taskId)")
#endif
                continuation.resume(throwing: FetchError.timeout)
            })
        Backlog.shared.add(reqTask)
        reqTask.fetch()
    })

}

/// Await an async operation while pumping the run loop so Timers or RunLoop-based APIs fire.
/// - Parameters:
///   - timeout: Maximum number of seconds to wait before throwing `CancellationError`.
///   - operation: Async operation to execute.
/// - Returns: The result of the async operation.
/// - Throws: Any error thrown by the operation, or `CancellationError` if timeout is exceeded.
func awaitWithRunLoop<T>(
    timeout: TimeInterval = 5,
    _ operation: @escaping () async throws -> T
) async throws -> T {
    var result: Result<T, Error>?
    let semaphore = DispatchSemaphore(value: 0)

    // Start the async operation in a Task
    Task {
        do {
            let value = try await operation()
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }

    // Compute deadline
    let deadline = Date().addingTimeInterval(timeout)

    // Pump the run loop until the async Task finishes or timeout occurs
    while semaphore.wait(timeout: .now()) == .timedOut {
        if Date() > deadline {
            throw CancellationError()
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        // Yield to Swift concurrency so other async tasks can run
        try? await Task.sleep(nanoseconds: 100_000)
    }

    // Return the result or rethrow the error
    return try result!.get()
}

struct ReqReturn {
    let taskId: String
    var relayMessage: Nostur.NXRelayMessage?
    var event: Nostur.Event?
}

enum FetchError: Error, LocalizedError, Equatable {
    
    static func == (lhs: FetchError, rhs: FetchError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
    
    case timeout
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .timeout: return "Timed out."
        case .unknown(let err): return err.localizedDescription
        }
    }
}

func withBgContext<T>(transform: @escaping (NSManagedObjectContext) -> T) async -> T {
    await withCheckedContinuation({ continuation in
        let bgContext = bg()
        bgContext.perform {
            continuation.resume(returning: transform(bgContext))
        }
    })

}

func fetchMissingPs(_ nrContacts: [NRContact]) {
    let missingPs = nrContacts
        .filter { $0.metadata_created_at == 0 }
        .map(\.pubkey)
    QueuedFetcher.shared.enqueue(pTags: missingPs)
}

func fetchProfiles(pubkeys: Set<String>, subscriptionId: String? = nil) {
    // Normally we use "Profiles" sub, and track the timestamp since last fetch
    // if we fetch someone elses feed, the sub is not "Profiles" but "SomeoneElsesProfiles", and we skip the date check
    let since = subscriptionId?.starts(with: "Profiles-") ?? false ? (Nostur.account()?.lastProfileReceivedAt ?? nil) : nil
    let sinceNTimestamp = since != nil ? NTimestamp(date: since!) : nil
    L.fetching.info("checking profiles since: \(since?.description ?? "")")
    
    ConnectionPool.shared
        .sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(
                    type: .REQ,
                    subscriptionId: subscriptionId,
                    filters: [Filters(authors: pubkeys, kinds: [0], since: sinceNTimestamp?.timestamp)]
                ),
                relayType: .READ
            ),
            subscriptionId: subscriptionId
        )
}

func fetchStuffForLastAddedNotes(ids: [String]) {
    guard !ids.isEmpty else {
#if DEBUG
        L.og.error("🔴🔴 fetchStuffForLastAddedNotes, ids is empty, fix it.")
#endif
        return
    }
    
    let sub = "VIEWING-"+UUID().uuidString
    
    ConnectionPool.shared
        .sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(
                    type: .REQ,
                    subscriptionId: sub,
                    filters: [Filters(kinds: [1,1244,1111,6,7,9735], tagFilter: TagFilter(tag: "e", values: Set(ids)), limit: 5000)]
                ),
                relayType: .READ
            )
        )
}

func pubkeys(_ contacts:[Contact]) -> [String] {
    return contacts.map { $0.pubkey }
}

func ids(_ events:[Event]) -> [String] {
    return events.map { $0.id }
}

func ids(_ events:Array<Event>.SubSequence) -> [String] {
    return events.map { $0.id }
}

func ids(_ nrPosts:[NRPost]) -> [String] {
    return nrPosts.map { $0.id }
}

func pubkeys(_ events:[Event]) -> [String] {
    return events.map { $0.pubkey }
}

func toId(_ event:Event) -> String {
    return event.id
}

func toPubkey(_ event:Event) -> String {
    return event.pubkey
}

func toPubkey(_ contact:Contact) -> String {
    return contact.pubkey
}


func serializedP(_ pubkey:String) -> String {
    return "[\"p\",\"\(pubkey)"
}


func serializedE(_ id:String) -> String {
    return "[\"e\",\"\(id)"
}

func serializedT(_ tag:String) -> String {
    return "[\"t\",\"\(tag)"
}

func serializedR(_ tag:String) -> String {
    return "[\"r\",\"\(tag)"
}
