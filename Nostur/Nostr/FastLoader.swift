//
//  FastLoader.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/05/2023.
//

import Foundation
import CoreData
import Combine

// Loads anything fast
// First loads 10 so on screen is instant
    // first 10 from viewContext or not?

// Loads remaining after that (in background thread)

// Should be realtime

// Should fetch more from network
// Should use subscriptionIds to match incoming messages

// Usage

//    let fl = FastLoader()
//    fl.predicate = NSPredicate()
//    fl.fetch()
//    results = await fl.first()
//    results = await fl.full()

class FastLoader: ObservableObject {
    private var viewContext:NSManagedObjectContext
    private var bgContext:NSManagedObjectContext
    private var loadNewerSubject = PassthroughSubject<(Int?, String), Never>()
    private var loadNewerEventsSubject = PassthroughSubject<(Int?, String), Never>()
    private var loadOlderEventsSubject = PassthroughSubject<(Int?, String), Never>()
    private var subscriptions = Set<AnyCancellable>()
    
    public var subscriptionId = UUID().uuidString
    public var offset = 0
    public var limit = 10
    public var nrPostTransform = true
    
    @Published var nrPosts:[NRPost] = []
    @Published var events:[Event] = []
    
    init() {
        viewContext = DataProvider.shared().viewContext
        bgContext = DataProvider.shared().bg
        loadNewerSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { parameters in
                let (limit, taskId) = parameters
                self._loadNewer(limit, taskId: taskId)
            }
            .store(in: &subscriptions)
        
        loadNewerEventsSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { parameters in
                let (limit, taskId) = parameters
                self._loadNewerEvents(limit, taskId: taskId)
            }
            .store(in: &subscriptions)
        
        loadOlderEventsSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { parameters in
                let (limit, taskId) = parameters
                self._loadOlderEvents(limit, taskId: taskId)
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
        NRPost(event: event)
    }
    
    // load first set of [limit] posts
    // loads from local, transforms on main, not not fetch from relays
    public func loadMore(_ limit:Int? = nil) {
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? self.limit
        self.limit = limit ?? self.limit
        
        if nrPostTransform {
            next.fetchOffset = max(0, self.nrPosts.count - 1)
            bgContext.perform {
                let dbEventIds = (try? self.bgContext.fetch(next)) ?? []
                let currentNRPostIds = Set(self.nrPosts.map { item in
                    item.id
                })
                let onlyUnrendered = dbEventIds.filter { item in
                    !currentNRPostIds.contains(item.id)
                }
                let nextItems = onlyUnrendered.compactMap { self.transformer($0) }
                DispatchQueue.main.async {
                    self.nrPosts = self.nrPosts + nextItems
                }
            }
        }
        else {
            next.fetchOffset = max(0, self.events.count - 1)
            let dbEventIds = (try? viewContext.fetch(next)) ?? []
            let currentEventIds = Set(self.events.map { event in
                event.id
            })
            let onlyUnrendered = dbEventIds.filter { item in
                !currentEventIds.contains(item.id)
            }
            let nextItems = onlyUnrendered
            
            events = events + nextItems
        }
    }
    
//    // Only for .nrPosts, not .events
//    public func loadMoreBG(_ limit:Int? = nil) {
//        let next = Event.fetchRequest()
//        next.predicate = predicate
//        next.sortDescriptors = sortDescriptors
//        next.fetchOffset = max(0, self.nrPosts.count - 1)
//        next.fetchLimit = limit ?? self.limit
//
//        self.limit = limit ?? self.limit
//
//        bgContext.perform {
//            let dbEventIds = (try? self.bgContext.fetch(next)) ?? []
//            let currentNRPostIds = Set(self.nrPosts.map { item in
//                item.id
//            })
//            let onlyUnrendered = dbEventIds.filter { item in
//                !currentNRPostIds.contains(item.id)
//            }
//            let nextItems = onlyUnrendered.map { NRPost(event: $0) }
//            DispatchQueue.main.async {
//                self.nrPosts = self.nrPosts + nextItems
//            }
//        }
//    }
    
    // Only for .nrPosts, not .events
    public func loadNewer(_ limit:Int? = nil, taskId:String) {
        self.loadNewerSubject.send((limit, taskId))
    }
    
    // Only for .nrPosts, not .events
    private func _loadNewer(_ limit:Int? = nil, taskId:String) {
        print("\(taskId) 🟠🟠🟠🟠 _loadNewer()")
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? 1000
        next.fetchOffset = 0
        bgContext.perform {
            let dbEventIds = (try? self.bgContext.fetch(next)) ?? []
            let currentNRPostIds = Set(self.nrPosts.map { item in
                item.id
            })
            let onlyUnrendered = dbEventIds.filter { item in
                !currentNRPostIds.contains(item.id)
            }
            let nextItems = onlyUnrendered.compactMap { self.transformer($0) }
            DispatchQueue.main.async {
                print("\(taskId) 🟠🟠🟠🟠🟠 self.nrPosts = nextItems (\(nextItems.count)) + self.nrPosts ")
                self.nrPosts = nextItems + self.nrPosts
            }
        }
    }
    
    
    // Only for .events, not .nrPosts, on main
    public func loadNewerEvents(_ limit:Int? = nil, taskId:String) {
        self.loadNewerEventsSubject.send((limit, taskId))
    }
    
    // Only for .events, not .nrPosts, on main
    private func _loadNewerEvents(_ limit:Int? = nil, taskId:String) {
        print("\(taskId) 🟠🟠🟠🟠 _loadNewerEvents()")
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? 1000
        next.fetchOffset = 0
        let dbEventIds = (try? self.viewContext.fetch(next)) ?? []
        let currentEventIds = Set(self.events.map { item in
            item.id
        })
        let nextItems = dbEventIds.filter { item in
            !currentEventIds.contains(item.id)
        }
        Task { @MainActor in
            print("\(taskId) 🟠🟠🟠🟠🟠 self.events = nextItems (\(nextItems.count)) + self.events ")
            self.events = nextItems + self.events
        }
    }
    

    // Only for .events, not .nrPosts, on main
    public func loadOlderEvents(_ limit:Int? = nil, taskId:String) {
        self.loadOlderEventsSubject.send((limit, taskId))
    }
    
    // Only for .events, not .nrPosts, on main
    private func _loadOlderEvents(_ limit:Int? = nil, taskId:String) {
        print("\(taskId) 🟠🟠🟠🟠 _loadOlderEvents()")
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? 1000
        next.fetchOffset = max(0, self.events.count - 1)
        let dbEventIds = (try? self.viewContext.fetch(next)) ?? []
        let currentEventIds = Set(self.events.map { item in
            item.id
        })
        let nextItems = dbEventIds.filter { item in
            !currentEventIds.contains(item.id)
        }
        Task { @MainActor in
            print("\(taskId) 🟠🟠🟠🟠🟠 self.events = self.events + nextItems (\(nextItems.count)) ")
            self.events = self.events + nextItems
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


// TODO: Make thread-safe
class Backlog {
    
    var tasks = Set<ReqTask>()
    var timer:Timer?
    var timeout = 60.0
    
    init(timeout:Double = 60.0) {
        self.timeout = timeout
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.removeOldTasks()
        }
    }
    
    private func removeOldTasks() {
        tasks.forEach { task in
            // TODO: Swift access race in Nostur.Backlog.tasks.modify : Swift.Set<Nostur.ReqTask> at 0x12630f940
            if task.createdAt.timeIntervalSinceNow < -timeout {
                task.onTimeout()
                tasks.remove(task)
            }
        }
    }
    
    public func clear() {
        tasks.removeAll()
    }
    
    public func add(_ task:ReqTask) {
        // TODO: Swift access race in Nostur.Backlog.tasks.modify : Swift.Set<Nostur.ReqTask> at 0x12630f940
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

struct ReqTask: Identifiable, Hashable {
    
    static func == (lhs: ReqTask, rhs: ReqTask) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var prefix:String? = nil
    let createdAt = Date.now
    let id = UUID().uuidString
    var subscriptionId:String { (prefix ?? "") + id }
    
    let reqCommand:(_ taskId:String) -> Void
    let processResponseCommand:(_ taskId:String) -> Void
    let timeoutCommand:((_ taskId:String) -> Void)?
    
    init(prefix:String? = nil, reqCommand: @escaping (_: String) -> Void, processResponseCommand: @escaping (_: String) -> Void, timeoutCommand: ( (_: String) -> Void)? = nil) {
        self.prefix = prefix
        self.reqCommand = reqCommand
        self.processResponseCommand = processResponseCommand
        self.timeoutCommand = timeoutCommand
    }
    
    public func fetch() {
        self.reqCommand(subscriptionId)
    }
    public func process() {
        self.processResponseCommand(subscriptionId)
    }
    
    public func onTimeout() {
        print("🟠🟠 removing task \(subscriptionId) after timeout")
        self.timeoutCommand?(subscriptionId)
    }
}
