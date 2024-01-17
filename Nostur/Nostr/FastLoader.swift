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
    private var viewContext:NSManagedObjectContext
    private var bgContext:NSManagedObjectContext
    private var loadNewerSubject = PassthroughSubject<(Int?, String, Bool), Never>()
    private var loadNewerEventsSubject = PassthroughSubject<(Int?, String, Bool), Never>()
    private var loadOlderEventsSubject = PassthroughSubject<(Int?, String, Bool), Never>()
    private var subscriptions = Set<AnyCancellable>()
    
    public var subscriptionId = UUID().uuidString
    public var offset:Int = 0
    public var limit:Int = 10
    public var nrPostTransform = true
    public var onComplete:(() -> Void)?
    
    @Published var nrPosts:[NRPost] = []
    @Published var events:[Event] = []
    
    init() {
        viewContext = DataProvider.shared().viewContext
        bgContext = bg()
        loadNewerSubject
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .sink { [weak self] parameters in
                guard let self = self else { return }
                let (limit, taskId, includeSpam) = parameters
                self._loadNewer(limit, taskId: taskId, includeSpam: includeSpam)
            }
            .store(in: &subscriptions)
        
        loadNewerEventsSubject
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .sink { [weak self] parameters in
                guard let self = self else { return }
                let (limit, taskId, includeSpam) = parameters
                self._loadNewerEvents(limit, taskId: taskId, includeSpam: includeSpam)
            }
            .store(in: &subscriptions)
        
        loadOlderEventsSubject
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .sink { [weak self] parameters in
                guard let self = self else { return }
                let (limit, taskId, includeSpam) = parameters
                self._loadOlderEvents(limit, taskId: taskId, includeSpam: includeSpam)
            }
            .store(in: &subscriptions)
    }
    
    public func reset() {
        self.nrPosts = []
        self.events = []
    }
    
    // What to load
    var predicate:NSPredicate?
    var sortDescriptors:[NSSortDescriptor]?
    
    // How to fetch new
    var fetchNewer:(() -> Void)?
    
    // How to transform (eg from Event to NRPost)
    var transformer:(_ event:Event) -> NRPost? = { event in
        var nrPost = NRPost(event: event, cancellationId: event.cancellationId)
        return nrPost
    }
    
    // load first set of [limit] posts
    // loads from local, transforms in bg, does not fetch from relays
    public func loadMore(_ limit:Int? = nil, includeSpam:Bool = false) {
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? self.limit
        self.limit = limit ?? self.limit
        
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        if nrPostTransform {
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
                let nextItems = onlyUnrendered
                    .filter { includeSpam || !$0.isSpam }
                    .compactMap { self.transformer($0) }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.nrPosts = self.nrPosts + nextItems
                    self.onComplete?()
                }
            }
        }
        else {
            next.fetchOffset = max(0, self.events.count - 1)
            let dbEvents:[Event] = (try? viewContext.fetch(next)) ?? [Event]()
                .map { event in
                    event.cancellationId = cancellationIds[event.id]
                    return event
                }
            
            let currentEventIds = Set(self.events.map { event in
                event.id
            })
            let onlyUnrendered = dbEvents.filter { item in
                !currentEventIds.contains(item.id)
            }
            let nextItems = onlyUnrendered
                .filter { includeSpam || !$0.isSpam }
            
            events = events + nextItems
            self.onComplete?()
        }
    }
    
    // Only for .nrPosts, not .events
    public func loadNewer(_ limit:Int? = nil, taskId:String, includeSpam:Bool = false) {
        self.loadNewerSubject.send((limit, taskId, includeSpam))
    }
    
    // Only for .nrPosts, not .events
    private func _loadNewer(_ limit:Int? = nil, taskId:String, includeSpam:Bool = false) {
        L.og.debug("\(taskId) 🟠🟠🟠🟠 _loadNewer()")
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
            let nextItems = onlyUnrendered
                .filter { includeSpam || !$0.isSpam }
                .compactMap { self.transformer($0) }
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                L.og.debug("\(taskId) 🟠🟠🟠🟠🟠 self.nrPosts = nextItems (\(nextItems.count)) + self.nrPosts ")
                self.nrPosts = nextItems + self.nrPosts
                self.onComplete?()
            }
        }
    }
    
    
    // Only for .events, not .nrPosts, on main
    public func loadNewerEvents(_ limit:Int? = nil, taskId:String, includeSpam:Bool = false) {
        self.loadNewerEventsSubject.send((limit, taskId, includeSpam))
    }
    
    // Only for .events, not .nrPosts, on main
    private func _loadNewerEvents(_ limit:Int? = nil, taskId:String, includeSpam:Bool = false) {
        L.og.debug("\(taskId) 🟠🟠🟠🟠 _loadNewerEvents()")
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? 1000
        next.fetchOffset = 0
        let dbEvents:[Event] = (try? self.viewContext.fetch(next)) ?? [Event]()
            .map { event in
                event.cancellationId = cancellationIds[event.id]
                return event
            }
        let currentEventIds = Set(self.events.map { item in
            item.id
        })
        let nextItems = dbEvents
            .filter { includeSpam || !$0.isSpam }
            .filter { item in
                !currentEventIds.contains(item.id)
            }
        Task { @MainActor in
            L.og.debug("\(taskId) 🟠🟠🟠🟠🟠 self.events = nextItems (\(nextItems.count)) + self.events ")
            self.events = nextItems + self.events
            self.onComplete?()
        }
    }
    

    // Only for .events, not .nrPosts, on main
    public func loadOlderEvents(_ limit:Int? = nil, taskId:String, includeSpam:Bool = false) {
        self.loadOlderEventsSubject.send((limit, taskId, includeSpam))
    }
    
    // Only for .events, not .nrPosts, on main
    private func _loadOlderEvents(_ limit:Int? = nil, taskId:String, includeSpam:Bool = false) {
        L.og.debug("\(taskId) 🟠🟠🟠🟠 _loadOlderEvents()")
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? 1000
        next.fetchOffset = max(0, self.events.count - 1)
        let dbEvents:[Event] = (try? self.viewContext.fetch(next)) ?? [Event]()
            .map { event in
                event.cancellationId = cancellationIds[event.id]
                return event
            }
        let currentEventIds = Set(self.events.map { item in
            item.id
        })
        let nextItems = dbEvents
            .filter { includeSpam || !$0.isSpam }
            .filter { item in
                !currentEventIds.contains(item.id)
            }
        Task { @MainActor in
            L.og.debug("\(taskId) 🟠🟠🟠🟠🟠 self.events = self.events + nextItems (\(nextItems.count)) ")
            self.events = self.events + nextItems
            self.onComplete?()
        }
    }
}

struct RelayFetchResult {
    let id:String
    let age:RelayFetchResult.age
    
    let events:[Event]

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
    let subscriptionId:String
    let event:Event
}

class Backlog {
    
    static let shared = Backlog(auto: true)
    
    private var tasks = Set<ReqTask>()
    private var timer:Timer?
    public var timeout = 60.0
    private var subscriptions = Set<AnyCancellable>()
    
    // With auto: true we don't need receiveNotification(.importedMessagesFromSubscriptionIds) on a View's .onReceive
    // the Backlog itself will listen for .importedMessagesFromSubscriptionIds notifications and
    // trigger the task.process() commands
    init(timeout:Double = 60.0, auto:Bool = false) {
        self.timeout = timeout
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
            bg().perform { [weak self] in
                guard let self = self else { return }
                guard !self.tasks.isEmpty else { return } // Swift access race in Nostur.Backlog.tasks.modify : Swift.Set<Nostur.ReqTask> at 0x10b7ffd20 - Thread 1
                self.removeOldTasks()
            }
        }
        if (auto) {
            Importer.shared.importedMessagesFromSubscriptionIds
                .sink { [weak self] subscriptionIds in
                    guard let self = self else { return }
                    let reqTasks = self.tasks(with: subscriptionIds)
                    for task in reqTasks {
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
                .sink { notification in
                    let receivedMessage = notification.object as! RelayMessage
                    guard let subscriptionId = receivedMessage.subscriptionId else { return }
                    bg().perform { [weak self] in
                        guard let self = self else { return }
                        let reqTasks = self.tasks(with: [subscriptionId])
                        for task in reqTasks {
                            task.process(receivedMessage)
                        }
                    }
                }
                .store(in: &subscriptions)
        }
    }
    
    private func removeOldTasks() {
        for task in self.tasks {
            // Check timeoout if configured per task
            if let timeout = task.timeout, task.createdAt.timeIntervalSinceNow < -timeout {
                task.onTimeout()
                self.tasks.remove(task)
            }
            // else check against the Backlog timeout
            else if task.createdAt.timeIntervalSinceNow < -self.timeout {
                task.onTimeout()
                self.tasks.remove(task)
            }
        }
    }
    
    public func clear() {
        bg().perform { [weak self] in
            self?.tasks.removeAll()
        }
    }
    
    public func add(_ task:ReqTask) {
        bg().perform { [weak self] in
            self?.tasks.insert(task)
        }
    }
    
    public func remove(_ task:ReqTask) {
        bg().perform { [weak self] in
            self?.tasks.remove(task)
        }
    }
    
    public func task(with subscriptionId:String) -> ReqTask? {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        return tasks.first(where: { $0.subscriptionId == subscriptionId })
    }
    
    public func tasks(with subscriptionIds:Set<String>) -> [ReqTask] {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        return tasks.filter { subscriptionIds.contains($0.subscriptionId) }
    }
}

class ReqTask: Identifiable, Hashable {
    
    static func == (lhs: ReqTask, rhs: ReqTask) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    private var prefix:String? = nil
    public let createdAt = Date.now
    public let id:String
    public var subscriptionId:String {
        if let prefix = prefix {
            return ((prio ? "prio-" : "") + prefix + id)
        }
        return ((prio ? "prio-" : "") + id)
    }
    
    private let reqCommand:(_ taskId:String) -> Void
    public let processResponseCommand:(_: String, _:RelayMessage?, _:Event?) -> Void
    private let timeoutCommand:((_ taskId:String) -> Void)?
    private var didProcess = false
    private var skipTimeout = false
    
    // Only use for fetching specific ids. different relays can return different events
    // prio will return the first received, this is wrong if we need for example the most recent event .
    private var prio = false
    public var timeout: Double? // default is 60.0 set in Backlog, this overrides it on a request basis
    
    // Use full subscriptionId instead of prefix to have multiple listeners for a task
    // eg. Onboarding + InstantFeed, both having a task with exact subscriptionId: "pubkey-3"
    // So both can listen for "pubkey-3" notifications. (make sure prefix is nil, and subscriptionId is set on ReqTask
    init(prio:Bool = false, debounceTime:Double = 0.1, timeout:Double? = nil, prefix:String? = nil,
         subscriptionId:String? = nil,
         reqCommand: @escaping (_: String) -> Void,
         processResponseCommand: @escaping (_: String, _:RelayMessage?, _:Event?) -> Void,
         timeoutCommand: ( (_: String) -> Void)? = nil) {
        self.prio = prio
        self.prefix = prefix
        self.id = subscriptionId ?? UUID().uuidString
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
    private var processSubject = PassthroughSubject<RelayMessage?, Never>()
    
    public func process(_ message:RelayMessage? = nil) {
        self.skipTimeout = true
        self.processSubject.send(message)
    }
    
    public func onTimeout() {
        guard !didProcess && !skipTimeout else { // need 2 flags to cover the debounce time where onTimeout could get called before didProcess is set
            L.og.debug("🟠🟠 didProcess or skipTimeout, timeout not needed"); return
        }
        self.timeoutCommand?(subscriptionId)
    }
}
