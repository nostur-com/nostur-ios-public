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
        bgContext = DataProvider.shared().bg
        loadNewerSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] parameters in
                guard let self = self else { return }
                let (limit, taskId, includeSpam) = parameters
                self._loadNewer(limit, taskId: taskId, includeSpam: includeSpam)
            }
            .store(in: &subscriptions)
        
        loadNewerEventsSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] parameters in
                guard let self = self else { return }
                let (limit, taskId, includeSpam) = parameters
                self._loadNewerEvents(limit, taskId: taskId, includeSpam: includeSpam)
            }
            .store(in: &subscriptions)
        
        loadOlderEventsSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
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
        var nrPost = NRPost(event: event)
        nrPost.cancellationId = event.cancellationId
        return nrPost
    }
    
    // load first set of [limit] posts
    // loads from local, transforms on main, not not fetch from relays
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
                
                DispatchQueue.main.async {
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
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
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
            
            DispatchQueue.main.async {
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

class Backlog {
    
    var tasks = Set<ReqTask>()
    var timer:Timer?
    var timeout = 60.0
    var subscriptions = Set<AnyCancellable>()
    
    // With auto: true we don't need receiveNotification(.importedMessagesFromSubscriptionIds) on a View's .onReceive
    // the Backlog itself will listen for .importedMessagesFromSubscriptionIds notifications and
    // trigger the task.process() commands
    init(timeout:Double = 60.0, auto:Bool = false) {
        self.timeout = timeout
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            guard !self.tasks.isEmpty else { return }
            self.removeOldTasks()
        }
        if (auto) {
            receiveNotification(.importedMessagesFromSubscriptionIds)
                .sink(receiveValue: { [weak self] notification in
                    guard let self = self else { return }
                    let importedNotification = notification.object as! ImportedNotification
                    let reqTasks = self.tasks(with: importedNotification.subscriptionIds)
                    for task in reqTasks {
                        task.process()
                    }
                })
                .store(in: &subscriptions)
            
            receiveNotification(.receivedMessage)
                .sink { [weak self] notification in
                    guard let self = self else { return }
                    let receivedMessage = notification.object as! RelayMessage
                    guard let subscriptionId = receivedMessage.subscriptionId else { return }
                    let reqTasks = self.tasks(with: [subscriptionId])
                    for task in reqTasks {
                        task.process(receivedMessage)
                    }
                }
                .store(in: &subscriptions)
        }
    }
    
    private func removeOldTasks() {
        for task in self.tasks {
            if task.createdAt.timeIntervalSinceNow < -self.timeout {
                task.onTimeout()
                self.tasks.remove(task)
            }
        }
    }
    
    public func clear() {
        tasks.removeAll()
    }
    
    public func add(_ task:ReqTask) {
        tasks.insert(task)
    }
    
    public func remove(_ task:ReqTask) {
        tasks.remove(task)
    }
    
    public func task(with subscriptionId:String) -> ReqTask? {
        tasks.first(where: { $0.subscriptionId == subscriptionId })
    }
    
    public func tasks(with subscriptionIds:Set<String>) -> [ReqTask] {
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
    
    var prefix:String? = nil
    let createdAt = Date.now
    let id:String
    var subscriptionId:String {
        if let prefix = prefix {
            return (prefix + id)
        }
        return id
    }
    
    let reqCommand:(_ taskId:String) -> Void
    let timeoutCommand:((_ taskId:String) -> Void)?
    var didProcess = false
    
    // Use full subscriptionId instead of prefix to have multiple listeners for a task
    // eg. Onboarding + InstantFeed, both having a task with exact subscriptionId: "pubkey-3"
    // So both can listen for "pubkey-3" notifications. (make sure prefix is nil, and subscriptionId is set on ReqTask
    init(debounceTime:Double = 0.1, prefix:String? = nil, subscriptionId:String? = nil, reqCommand: @escaping (_: String) -> Void, processResponseCommand: @escaping (_: String, _:RelayMessage?) -> Void, timeoutCommand: ( (_: String) -> Void)? = nil) {
        self.prefix = prefix
        self.id = subscriptionId ?? UUID().uuidString
        self.reqCommand = reqCommand
        self.timeoutCommand = timeoutCommand
        processSubject
            .debounce(for: RunLoop.SchedulerTimeType.Stride(debounceTime), scheduler: RunLoop.main)
            .sink { [weak self] message in
                guard let self = self else { return }
                guard !didProcess else { return }
                didProcess = true
                processResponseCommand(self.subscriptionId, message)
            }
            .store(in: &subscriptions)
    }
    
    public func fetch() {
        self.reqCommand(subscriptionId)
    }
    
    var subscriptions = Set<AnyCancellable>()
    var processSubject = PassthroughSubject<RelayMessage?, Never>()
    
    public func process(_ message:RelayMessage? = nil) {
        self.processSubject.send(message)
    }
    
    public func onTimeout() {
        L.og.debug("🟠🟠 removing task \(self.subscriptionId) after timeout")
        self.timeoutCommand?(subscriptionId)
    }
}
