//
//  FastLoader.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/05/2023.
//

import Foundation
import CoreData
import Combine
import NostrEssentials

@MainActor
final class BoundedRelayRequestCompletionTracker {
    enum Outcome {
        case finished
        case timedOut
    }

    private let subscriptionId: String
    private let policy: BoundedRelayCompletionPolicy
    private let settleDelayNanoseconds: UInt64
    private let deadlineNanoseconds: UInt64
    private let onImport: () -> Void
    private let onCompletion: (Outcome) -> Void
    private let extendQuietPeriodOnImport: Bool

    private var finishedRelays: Set<CanonicalRelayUrl> = []
    private var subscriptions = Set<AnyCancellable>()
    private var completionTask: Task<Void, Never>?
    private var didComplete = false
    private var quorumReached = false

    init(
        subscriptionId: String,
        targets: ConnectionPool.RequestTargetSnapshot,
        settleDelay: TimeInterval = 0.3,
        connectedDeadline: TimeInterval = 3.0,
        connectingDeadline: TimeInterval = 6.0,
        extendQuietPeriodOnImport: Bool = true,
        onImport: @escaping () -> Void = {},
        onCompletion: @escaping (Outcome) -> Void
    ) {
        self.subscriptionId = subscriptionId
        let policy = BoundedRelayCompletionPolicy(
            coreIds: targets.coreIds,
            extraIds: targets.extraIds,
            connectedIds: targets.connectedIds
        )
        self.policy = policy
        self.settleDelayNanoseconds = UInt64(settleDelay * 1_000_000_000)
        self.deadlineNanoseconds = UInt64(
            (policy.usesShortDeadline ? connectedDeadline : connectingDeadline) * 1_000_000_000
        )
        self.extendQuietPeriodOnImport = extendQuietPeriodOnImport
        self.onImport = onImport
        self.onCompletion = onCompletion
    }

    func start() {
        Importer.shared.importedMessagesFromSubscriptionIds
            .filter { [subscriptionId] in $0.contains(subscriptionId) }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.receivedImport()
            }
            .store(in: &subscriptions)

        Importer.shared.importedPrioMessagesFromSubscriptionId
            .filter { [subscriptionId] in $0.subscriptionId == subscriptionId }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.receivedImport()
            }
            .store(in: &subscriptions)

        MessageParser.shared.requestTerminalSub
            .filter { [subscriptionId] in $0.subscriptionId == subscriptionId }
            .receive(on: RunLoop.main)
            .sink { [weak self] response in
                self?.receivedTerminalResponse(from: response.relay)
            }
            .store(in: &subscriptions)

        guard !policy.knownIds.isEmpty else {
            scheduleCompletion(.finished, after: settleDelayNanoseconds)
            return
        }

        let deadlineNanoseconds = deadlineNanoseconds
        completionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: deadlineNanoseconds)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: self?.settleDelayNanoseconds ?? 0)
            guard !Task.isCancelled else { return }
            self?.complete(.timedOut)
        }
    }

    func cancel() {
        completionTask?.cancel()
        completionTask = nil
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }

    private func receivedTerminalResponse(from relay: String) {
        guard !didComplete else { return }
        finishedRelays.insert(normalizeRelayUrl(relay))
        guard policy.shouldFinish(finished: finishedRelays) else { return }
        quorumReached = true
        scheduleCompletion(.finished, after: settleDelayNanoseconds)
    }

    private func receivedImport() {
        guard !didComplete else { return }
        onImport()
        // Catch-up/media: EOSE can arrive while matching events are still
        // being committed, so keep nudging the quiet period. Latest two-phase
        // fetch must not do this — extras drip for a long time and would hold
        // completion for 10s+.
        if quorumReached && extendQuietPeriodOnImport {
            scheduleCompletion(.finished, after: settleDelayNanoseconds)
        }
    }

    private func scheduleCompletion(_ outcome: Outcome, after delay: UInt64) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.complete(outcome)
        }
    }

    private func complete(_ outcome: Outcome) {
        guard !didComplete else { return }
        didComplete = true
        cancel()
        let deadExtras = policy.unreachableExtras(finished: finishedRelays)
        if !deadExtras.isEmpty {
            ConnectionPool.shared.noteUnreachableExtras(deadExtras)
        }
#if DEBUG
        if outcome == .timedOut {
            FeedFetchDebug.shared.markTimeout(subscriptionId: subscriptionId)
        }
        else {
            // The owner closes unfinished relays after the import settle period.
            FeedFetchDebug.shared.markEnded(subscriptionId: subscriptionId)
        }
#endif
        onCompletion(outcome)
    }
}

class FastLoader: ObservableObject {
    
    private var bgContext: NSManagedObjectContext
    
    private var loadNewerSubject = PassthroughSubject<(Int?, String, Bool), Never>()
    private var loadNewerEventsSubject = PassthroughSubject<(Int?, String, Bool), Never>()
    private var loadOlderEventsSubject = PassthroughSubject<(Int?, String, Bool), Never>()
    
    private var subscriptions = Set<AnyCancellable>()
    
    public var subscriptionId = UUID().uuidString
    public var offset: Int = 0
    public var limit: Int = 10
    public var onComplete: (() -> Void)?
    public var accountPubkey: String?
    public var didLoad = false
    
    @Published var nrPosts: [NRPost] = []

    init() {
        bgContext = bg()
        loadNewerSubject
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .sink { [weak self] parameters in
                guard let self = self else { return }
                let (limit, taskId, includeSpam) = parameters
                self._loadNewer(limit, taskId: taskId, includeSpam: includeSpam)
            }
            .store(in: &subscriptions)
        
        receiveNotification(.muteListUpdated)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let mutedRootIds = notification.object as! Set<String>
                let nrPosts = self.nrPosts
                nrPosts.forEach { nrPost in
                    nrPost.muted = mutedRootIds.contains(nrPost.id)
                        || mutedRootIds.contains(nrPost.replyToRootId ?? "!")
                        || (nrPost.isRepost && mutedRootIds.contains(nrPost.firstQuoteId ?? "!"))
                }
                self.nrPosts = nrPosts
            }
            .store(in: &subscriptions)
        
        receiveNotification(.mutedWordsChanged)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let mutedWords = (notification.object as? [String]) ?? AppState.shared.bgAppState.mutedWords
                if mutedWords.isEmpty {
                    self.reset()
                    self.loadMore(self.limit)
                    return
                }
                self.nrPosts = self.nrPosts.filter { nrPost in
                    notMutedWords(in: nrPost.plainText, mutedWords: mutedWords)
                }
            }
            .store(in: &subscriptions)
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                self.nrPosts = self.nrPosts.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &subscriptions)
    }
    
    public func reset() {
        self.nrPosts = []
    }
    
    // What to load
    var predicate: NSPredicate?
    var sortDescriptors: [NSSortDescriptor]?
    
    // How to fetch new
    var fetchNewer: (() -> Void)?
    
    // How to transform (eg from Event to NRPost)
    var transformer: (_ event: Event) -> NRPost? = { event in
        var nrPost = NRPost(event: event, cancellationId: event.cancellationId)
        return nrPost
    }
    
    // load first set of [limit] posts
    // loads from local, transforms in bg, does not fetch from relays
    public func loadMore(_ limit: Int? = nil, includeSpam: Bool = false) {
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? self.limit
        self.limit = limit ?? self.limit
        
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        next.fetchOffset = max(0, self.nrPosts.count - 1)
        bgContext.perform { [weak self] in
            guard let self = self else { return }
            let dbEvents:[Event] = (try? self.bgContext.fetch(next)) ?? [Event]()
                .map { event in
                    event.cancellationId = cancellationIds[event.id]
                    return event
                }
            let currentNRPostIds = Set(self.nrPosts.map { item in
                item.id
            })
            let onlyUnrendered = dbEvents.filter { item in
                !currentNRPostIds.contains(item.id)
            }
            let nextItems: [NRPost] = onlyUnrendered
                .filter { includeSpam || !$0.isSpam }
                .filter { !$0.isMutedByWords }
                .compactMap { [weak self] in
                    guard let self else { return nil }
                    return self.transformer($0)
                }
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.nrPosts = self.nrPosts + nextItems
                self.onComplete?()
            }
        }
    }
    
    // Only for .nrPosts, not .events
    public func loadNewer(_ limit: Int? = nil, taskId: String, includeSpam: Bool = false) {
        self.loadNewerSubject.send((limit, taskId, includeSpam))
    }
    
    // Only for .nrPosts, not .events
    private func _loadNewer(_ limit: Int? = nil, taskId: String, includeSpam: Bool = false) {
#if DEBUG
        L.og.debug("\(taskId) 🟠🟠🟠🟠 _loadNewer()")
#endif
        let cancellationIds:[String: UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? 1000
        next.fetchOffset = 0
        bgContext.perform { [weak self] in
            guard let self = self else { return }
            let dbEvents:[Event] = (try? self.bgContext.fetch(next)) ?? [Event]()
                .map { event in
                    event.cancellationId = cancellationIds[event.id]
                    return event
                }
            let currentNRPostIds = Set(self.nrPosts.map { item in
                item.id
            })
            let onlyUnrendered = dbEvents.filter { item in
                !currentNRPostIds.contains(item.id)
            }
            let nextItems: [NRPost] = onlyUnrendered
                .filter { includeSpam || !$0.isSpam }
                .filter { !$0.isMutedByWords }
                .compactMap { [weak self] in
                    guard let self else { return nil }
                    return self.transformer($0)
                }
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
#if DEBUG
                L.og.debug("\(taskId) 🟠🟠🟠🟠🟠 self.nrPosts = nextItems (\(nextItems.count)) + self.nrPosts ")
#endif
                self.nrPosts = nextItems + self.nrPosts
                self.onComplete?()
            }
        }
    }
}

struct RelayFetchResult {
    let id: String
    let age: RelayFetchResult.age
    
    let events: [Event]

    enum age {
        case newer
        case older
    }
}

struct ImportedNotification {
    let id = UUID()
    let subscriptionIds:Set<String>
}

struct ImportedPrioNotification {
    let id = UUID()
    let subscriptionId: String
    let event: Event
}

class Backlog {
    static let shared = Backlog(auto: true, backlogDebugName: "Shared")
    /// Timeout bookkeeping must remain independent of the importer/Core Data
    /// queue; otherwise a busy feed can prevent unrelated requests from ever
    /// reaching their timeout/recovery path.
    private static let timeoutQueue = DispatchQueue(
        label: "com.nostur.backlog.timeout",
        qos: .utility
    )
    
    public var timeout: Double
    
    private var tasks = Set<ReqTask>()
    /// `tasks` is unrelated to Core Data. Keeping it on `bg()` made request
    /// registration compete with feed imports and could block the main thread
    /// for seconds. A dedicated lock keeps add-before-fetch ordering without
    /// waiting for database work.
    private let tasksLock = NSLock()
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    public var backlogDebugName: String
    
    // With auto: true we don't need receiveNotification(.importedMessagesFromSubscriptionIds) on a View's .onReceive
    // the Backlog itself will listen for .importedMessagesFromSubscriptionIds notifications and
    // trigger the task.process() commands
    // TODO: 25.00 ms    0.2%    0 s           closure #1 in Backlog.init(timeout:auto:)
    init(timeout: Double = 12.0, auto: Bool = false, backlogDebugName: String = "Default") {
        self.backlogDebugName = backlogDebugName
        self.timeout = timeout
        if (auto) {
            Importer.shared.importedMessagesFromSubscriptionIds
                .sink { [weak self] subscriptionIds in
                    guard let self = self else { return }
                    let reqTasks = self.tasks(with: subscriptionIds)
#if DEBUG
                    let taskSnapshot = self.allTasks()
                    if !taskSnapshot.isEmpty {
                        L.og.debug("\(backlogDebugName) - subscriptionIds: \(subscriptionIds) tasks: \(taskSnapshot.count): \(taskSnapshot.map { $0.subscriptionId }) -[LOG]-")
                    }
#endif
                    for task in reqTasks {
#if DEBUG
                        L.og.debug("\(backlogDebugName) - task.process(): \(task.subscriptionId)  -[LOG]-")
#endif
                        task.process()
                    }
                }
                .store(in: &subscriptions)
            
            Importer.shared.importedPrioMessagesFromSubscriptionId
                .sink { [weak self] importedPrioNotification in
                    guard let self = self else { return }
                    if let task = self.task(with: importedPrioNotification.subscriptionId) {
                        task.processResponseCommand(importedPrioNotification.subscriptionId, nil, importedPrioNotification.event)
                        self.remove(task)
                    }
                }
                .store(in: &subscriptions)
            
            receiveNotification(.receivedMessage)
                .sink { [weak self] notification in
                    let receivedMessage = notification.object as! NXRelayMessage
                    guard let subscriptionId = receivedMessage.subscriptionId else { return }
                    bg().perform { [weak self] in
                        guard let self = self else { return }
                        if let messageType = receivedMessage.type, subscriptionId.prefix(4) == "-DB-", messageType != .EVENT {
                            // for noDb (-DB-) we only need to handle .EVENT, not EOSE, AUTH or other
                            // so cancel if -DB- but not .EVENT
                            return
                        }
                        let reqTasks = self.tasks(with: [subscriptionId])
                        for task in reqTasks {
                            task.process(receivedMessage)
                        }
                    }
                }
                .store(in: &subscriptions)
        }
    }
    
    private func startCleanUpTimer() {
        let interval = max(timeout/22, 0.50)
        let installTimer = { [weak self] in
            guard self?.timer == nil else { return }
            self?.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                Backlog.timeoutQueue.async { [weak self] in
                    self?.removeOldTasks()
                }
            }
        }
        if Thread.isMainThread {
            installTimer()
        }
        else {
            DispatchQueue.main.async(execute: installTimer)
        }
    }
    
    private func removeOldTasks() {
        let taskSnapshot = allTasks()
        guard !taskSnapshot.isEmpty else { return }
#if DEBUG
        let tasksCount = taskSnapshot.count
        var removed = 0
#endif
        // Collect tasks to remove to avoid modifying the set during iteration
        var tasksToRemove = [ReqTask]()
        
        for task in taskSnapshot {
            // Don't timeout if task is still running (or about to run, because of debounce/delays)
            if task.isRunning {
#if DEBUG
                L.og.debug("⏳⏳ \(self.backlogDebugName) removeOldTasks(): not removing, isRunning=true \(task.subscriptionId) -[LOG]-")
#endif
                continue
            }
            
            // Check timeout if configured per task
            if let timeout = task.timeout, task.createdAt.timeIntervalSinceNow < -timeout {
                task.onTimeout()
                tasksToRemove.append(task)
#if DEBUG
                removed += 1
#endif
            }
            // else check against the Backlog timeout
            else if task.createdAt.timeIntervalSinceNow < -self.timeout {
                task.onTimeout()
                tasksToRemove.append(task)
#if DEBUG
                removed += 1
#endif
            }
        }
        
        // Now safely remove the collected tasks
        withTasksLock {
            for task in tasksToRemove {
                self.tasks.remove(task)
#if DEBUG
                L.og.debug("⏳⏳ \(self.backlogDebugName) removeOldTasks(): removed \(task.subscriptionId) -[LOG]-")
#endif
            }
        }
        
        if allTasks().isEmpty {
            DispatchQueue.main.async { [weak self] in // needs to be from main
                self?.timer?.invalidate()
                self?.timer = nil
#if DEBUG
                L.og.debug("⏳⏳ \(self?.backlogDebugName) removeOldTasks(): cleanup timer removed -[LOG]-")
#endif
            }
        }
#if DEBUG
        if removed > 0 {
            L.og.debug("⏳⏳ \(self.backlogDebugName) removeOldTasks(): removed: \(removed)/\(tasksCount) timeout: \(self.timeout.description) -[LOG]-")
        }
#endif
    }
    
    public func clear() {
        let tasksToRemove = withTasksLock {
            let snapshot = Array(tasks)
            tasks.removeAll(keepingCapacity: false)
            return snapshot
        }
#if DEBUG
        L.og.debug("⏳⏳ \(self.backlogDebugName) Backlog.clear() - \((tasksToRemove.map { $0.subscriptionId }).description) -[LOG]-")
#endif

        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }

        tasksToRemove.forEach { $0.cleanup() }
    }
    
    public func add(_ task: ReqTask) {
        // Callers conventionally do `backlog.add(task); task.fetch()`. Registration
        // must finish before add() returns, but must not wait for the importer/Core
        // Data queue. The task-set lock makes this operation synchronous and tiny.
        withTasksLock {
#if DEBUG
            L.og.debug("⏳⏳ \(self.backlogDebugName) Backlog.add(\(task.subscriptionId)) -[LOG]-")
#endif
            self.tasks.insert(task)
        }
        startCleanUpTimer()
    }
    
    public func remove(_ task: ReqTask) {
#if DEBUG
        L.og.debug("⏳⏳ \(self.backlogDebugName) Backlog.remove(\(task.subscriptionId)) -[LOG]-")
#endif
        withTasksLock {
            tasks.remove(task)
        }
    }
    
    public func removeTask(with subscriptionId: String) {
#if DEBUG
        L.og.debug("⏳⏳ \(self.backlogDebugName) Backlog.removeTask(with: \(subscriptionId)) -[LOG]-")
#endif
        withTasksLock {
            guard let taskToRemove = tasks.first(where: { $0.subscriptionId == subscriptionId }) else { return }
            tasks.remove(taskToRemove)
        }
    }
    
    public func task(with subscriptionId: String) -> ReqTask? {
        withTasksLock {
            tasks.first(where: { $0.subscriptionId == subscriptionId })
        }
    }
    
    public func tasks(with subscriptionIds: Set<String>) -> [ReqTask] {
        withTasksLock {
            tasks.filter { subscriptionIds.contains($0.subscriptionId) }
        }
    }

#if DEBUG
    /// Test/debug inspection that preserves task-set serialization.
    func containsTask(with subscriptionId: String) -> Bool {
        withTasksLock {
            tasks.contains(where: { $0.subscriptionId == subscriptionId })
        }
    }
#endif

    private func allTasks() -> [ReqTask] {
        withTasksLock { Array(tasks) }
    }

    @discardableResult
    private func withTasksLock<T>(_ body: () -> T) -> T {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return body()
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
        subscriptions.removeAll()
    }
}

class ReqTask: Identifiable, Hashable {
    enum TimeoutDelivery {
        /// Legacy/default contract: timeout callbacks may read or transform
        /// objects owned by the app's shared private context.
        case backgroundContext
        /// For bookkeeping-only callbacks that are explicitly Core Data free.
        case immediate
        /// For callbacks that exclusively update UI/main-context state.
        case main
    }
    
    static func == (lhs: ReqTask, rhs: ReqTask) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    private var prefix: String? = nil
    public let createdAt = Date.now
    public let id: String
    public var subscriptionId: String {
        if let prefix = prefix {
            return ((prio ? "prio-" : "") + prefix + id)
        }
        return ((prio ? "prio-" : "") + id)
    }
    
    private let reqCommand:(_ taskId: String) -> Void
    public let processResponseCommand:(_: String, _: NXRelayMessage?, _:Event?) -> Void
    private let timeoutCommand:((_ taskId: String) -> Void)?
    private let timeoutDelivery: TimeoutDelivery
    private let stateLock = NSLock()
    private var didProcess = false
    private var _isRunning = false
    private var skipTimeout = false

    public var isRunning: Bool {
        withStateLock { _isRunning }
    }
    
    // Only use for fetching specific ids. different relays can return different events
    // prio will return the first received, this is wrong if we need for example the most recent event .
    private var prio = false
    public var timeout: Double? // default is 60.0 set in Backlog, this overrides it on a request basis
    
    // Use full subscriptionId instead of prefix to have multiple listeners for a task
    // eg. Onboarding + InstantFeed, both having a task with exact subscriptionId: "pubkey-3"
    // So both can listen for "pubkey-3" notifications. (make sure prefix is nil, and subscriptionId is set on ReqTask
    
    // debounce  is for task.process() when waiting for latest event, fast relay might send older/wrong event earlier
    // need to wait for all relays, but not too long, so debounce.
    init(prio: Bool = false, debounceTime: Double = 0.1, timeout: Double? = nil, prefix: String? = nil,
         subscriptionId: String? = nil,
         reqCommand: @escaping (_: String) -> Void,
         processResponseCommand: @escaping (_: String, _: NXRelayMessage?, _:Event?) -> Void,
         timeoutCommand: ( (_: String) -> Void)? = nil,
         timeoutDelivery: TimeoutDelivery = .backgroundContext) {
        self.prio = prio
        self.prefix = prefix
        self.id = subscriptionId ?? String(UUID().uuidString.prefix(48))
        self.reqCommand = reqCommand
        self.processResponseCommand = processResponseCommand
        self.timeoutCommand = timeoutCommand
        self.timeoutDelivery = timeoutDelivery
        self.timeout = timeout
        
        guard !prio else { return }
        
        processSubject
            .debounce(for: .seconds(debounceTime), scheduler: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self = self else { return }
                let shouldProcess = self.withStateLock {
                    guard !self.didProcess else {
                        self._isRunning = false
                        return false
                    }
                    self.didProcess = true
                    return true
                }
                guard shouldProcess else { return }
                self.processResponseCommand(self.subscriptionId, message, nil)
                self.withStateLock {
                    self._isRunning = false
                }
            }
            .store(in: &subscriptions)
    }
    
    public func fetch() {
        self.reqCommand(subscriptionId)
    }
    
    private var subscriptions = Set<AnyCancellable>()
    private var processSubject = PassthroughSubject<NXRelayMessage?, Never>()
    
    public func process(_ message: NXRelayMessage? = nil) {
        withStateLock {
            skipTimeout = true
            if !didProcess {
                _isRunning = true
            }
        }
        processSubject.send(message)
    }
    
    public func onTimeout() {
#if DEBUG
        L.og.debug("⏳⏳ ReqTask.onTimout: \(self.subscriptionId) -[LOG]-")
#endif
        let shouldTimeout = withStateLock {
            _isRunning = false
            return !didProcess && !skipTimeout
        }
        if !shouldTimeout { // cover the debounce window before didProcess is set
#if DEBUG
            L.og.debug("⏳⏳ ReqTask: didProcess or skipTimeout, timeout not needed \(self.subscriptionId) -[LOG]-")
#endif
            return
        }
        let timedOutSubscriptionId = subscriptionId
#if DEBUG
        Task { @MainActor in
            FeedFetchDebug.shared.markTimeout(subscriptionId: timedOutSubscriptionId)
        }
#endif
        guard let timeoutCommand else { return }
        switch timeoutDelivery {
        case .backgroundContext:
            // Backlog expiry detection stays on its independent queue, but the
            // callback retains the historical bg-context contract. Running the
            // callback directly on timeoutQueue caused managed-object crashes.
            bg().perform {
                timeoutCommand(timedOutSubscriptionId)
            }
        case .immediate:
            timeoutCommand(timedOutSubscriptionId)
        case .main:
            DispatchQueue.main.async {
                timeoutCommand(timedOutSubscriptionId)
            }
        }
    }
    
    public func cleanup() {
        let subscriptionsToCancel = withStateLock {
            _isRunning = false
            let snapshot = subscriptions
            subscriptions.removeAll()
            return snapshot
        }
        subscriptionsToCancel.forEach { $0.cancel() }
    }

    @discardableResult
    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
    
    deinit {
        cleanup()
    }
}
