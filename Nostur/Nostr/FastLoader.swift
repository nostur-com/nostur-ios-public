//
//  FastLoader.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/05/2023.
//

import Foundation
import CoreData
import Combine

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
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.nrPosts = self.nrPosts.filter(notMuted)
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
    
    public var timeout: Double
    
    private var tasks = Set<ReqTask>()
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
                    if self.tasks.count > 0 {
                        L.og.debug("\(backlogDebugName) - subscriptionIds: \(subscriptionIds) tasks: \(self.tasks.count): \(self.tasks.map { $0.subscriptionId }) -[LOG]-")
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
        DispatchQueue.main.async { [weak self] in // timer needs to run on main
            guard let self, self.timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: self.timeout/22, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    guard !self.tasks.isEmpty else { return }
//    #if DEBUG
//                    L.og.debug("⏳⏳ \(self.backlogDebugName) withTimeInterval: \(self.timeout/22) -> \(self.timeout) --> tasks: \(self.tasks.count) -[LOG]-")
//    #endif
                    self.removeOldTasks()
                }
            }
        }
    }
    
    private func removeOldTasks() {
        guard !tasks.isEmpty else { return }
#if DEBUG
        let tasksCount = self.tasks.count
        var removed = 0
#endif
        for task in self.tasks {
            // Check timeoout if configured per task
            if let timeout = task.timeout, task.createdAt.timeIntervalSinceNow < -timeout {
                task.onTimeout()
                self.tasks.remove(task)
#if DEBUG
                L.og.debug("⏳⏳ \(self.backlogDebugName) removeOldTasks(): removed \(task.subscriptionId)")
                removed += 1
#endif
            }
            // else check against the Backlog timeout
            else if task.createdAt.timeIntervalSinceNow < -self.timeout {
                task.onTimeout()
                self.tasks.remove(task)
#if DEBUG
                L.og.debug("⏳⏳ \(self.backlogDebugName) removeOldTasks(): removed \(task.subscriptionId)")
                removed += 1
#endif
                
            }
        }
        
        if self.tasks.isEmpty {
            DispatchQueue.main.async { [weak self] in // needs to be from main
                guard self?.tasks.isEmpty ?? false else { return }
                self?.timer?.invalidate()
                self?.timer = nil
#if DEBUG
                L.og.debug("⏳⏳ \(self?.backlogDebugName) removeOldTasks(): cleanup timer removed")
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
        bg().perform { [weak self] in
#if DEBUG
            L.og.debug("⏳⏳ \(self?.backlogDebugName ?? "") Backlog.clear() - \((self?.tasks.map { $0.subscriptionId })?.description ?? "")")
#endif
            self?.tasks.removeAll()
        }
    }
    
    public func add(_ task: ReqTask) {
        bg().perform { [weak self] in
            guard let self else { return }
#if DEBUG
            L.og.debug("⏳⏳ \(self.backlogDebugName) Backlog.add(\(task.subscriptionId))")
#endif
            self.tasks.insert(task)
            self.startCleanUpTimer()
        }
    }
    
    public func remove(_ task: ReqTask) {
#if DEBUG
        L.og.debug("⏳⏳ \(self.backlogDebugName) Backlog.remove(\(task.subscriptionId))")
#endif
        bg().perform { [weak self] in
            self?.tasks.remove(task)
        }
    }
    
    public func task(with subscriptionId: String) -> ReqTask? {
#if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
#endif
        return tasks.first(where: { $0.subscriptionId == subscriptionId })
    }
    
    public func tasks(with subscriptionIds: Set<String>) -> [ReqTask] {
#if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
#endif
        return tasks.filter { subscriptionIds.contains($0.subscriptionId) }
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
        subscriptions.removeAll()
        tasks.removeAll()
    }
}

class ReqTask: Identifiable, Hashable {
    
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
    private var didProcess = false
    private var skipTimeout = false
    
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
         timeoutCommand: ( (_: String) -> Void)? = nil) {
        self.prio = prio
        self.prefix = prefix
        self.id = subscriptionId ?? String(UUID().uuidString.prefix(48))
        self.reqCommand = reqCommand
        self.processResponseCommand = processResponseCommand
        self.timeoutCommand = timeoutCommand
        self.timeout = timeout
        
        guard !prio else { return }
        
        processSubject
            .debounce(for: .seconds(debounceTime), scheduler: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self = self else { return }
                guard !didProcess else { return }
                didProcess = true
                processResponseCommand(self.subscriptionId, message, nil)
            }
            .store(in: &subscriptions)
    }
    
    public func fetch() {
        self.reqCommand(subscriptionId)
    }
    
    private var subscriptions = Set<AnyCancellable>()
    private var processSubject = PassthroughSubject<NXRelayMessage?, Never>()
    
    public func process(_ message: NXRelayMessage? = nil) {
        self.skipTimeout = true
        self.processSubject.send(message)
    }
    
    public func onTimeout() {
#if DEBUG
        L.og.debug("⏳⏳ ReqTask.onTimout: \(self.subscriptionId)")
#endif
        if didProcess || skipTimeout { // need 2 flags to cover the debounce time where onTimeout could get called before didProcess is set
#if DEBUG
            L.og.debug("⏳⏳ ReqTask: didProcess or skipTimeout, timeout not needed \(self.subscriptionId)")
#endif
            return
        }
        self.timeoutCommand?(subscriptionId)
    }
    
    deinit {
        subscriptions.removeAll()
    }
}
