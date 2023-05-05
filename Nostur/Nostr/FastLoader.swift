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
    private var loadNewerBGSubject = PassthroughSubject<(Int?, String), Never>()
    private var loadNewerEventsSubject = PassthroughSubject<(Int?, String), Never>()
    private var loadOlderEventsSubject = PassthroughSubject<(Int?, String), Never>()
    private var subscriptions = Set<AnyCancellable>()
    
    public var subscriptionId = UUID().uuidString
    public var offset = 0
    public var limit = 10
    public var vPostTransform = true
    
    @Published var vPosts:[VPost] = []
    @Published var events:[Event] = []
    @Published var followingKeys:Set<String> = []
    
    init() {
        viewContext = DataProvider.shared().viewContext
        bgContext = DataProvider.shared().bg
        loadNewerBGSubject
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.global())
            .sink { parameters in
                let (limit, taskId) = parameters
                self._loadNewerBG(limit, taskId: taskId)
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
    
    // What to load
    var predicate:NSPredicate?
    var sortDescriptors:[NSSortDescriptor]?
    
    // How to fetch new
    var fetchNewer:(() -> Void)?
    
    // load first set of [limit] posts
    // loads from local, transforms on main, not not fetch from relays
    public func loadMore(_ limit:Int? = nil) {
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? self.limit
        self.limit = limit ?? self.limit
        
        if vPostTransform {
            next.fetchOffset = max(0, self.vPosts.count - 1)
            let dbEventIds = (try? viewContext.fetch(next)) ?? []
            let currentVPostIds = Set(self.vPosts.map { item in
                item.id
            })
            let onlyUnrendered = dbEventIds.filter { item in
                !currentVPostIds.contains(item.id)
            }
            let nextItems = self.transformOnMain(onlyUnrendered)
            
            vPosts = vPosts + nextItems
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
    
    // Only for .vPosts, not .events
    public func loadMoreBG(_ limit:Int? = nil) {
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchOffset = max(0, self.vPosts.count - 1)
        next.fetchLimit = limit ?? self.limit
        
        self.limit = limit ?? self.limit

        bgContext.perform {
            let dbEventIds = (try? self.bgContext.fetch(next)) ?? []
            let currentVPostIds = Set(self.vPosts.map { item in
                item.id
            })
            let onlyUnrendered = dbEventIds.filter { item in
                !currentVPostIds.contains(item.id)
            }
            let nextItems = self.transformInBG(onlyUnrendered)

            Task { @MainActor in
                self.vPosts = self.vPosts + nextItems
            }
        }
    }
    
    // Only for .vPosts, not .events
    public func loadNewerBG(_ limit:Int? = nil, taskId:String) {
        self.loadNewerBGSubject.send((limit, taskId))
    }
    
    // Only for .vPosts, not .events
    private func _loadNewerBG(_ limit:Int? = nil, taskId:String) {
        print("\(taskId) 🟠🟠🟠🟠 _loadNewerBG()")
        let next = Event.fetchRequest()
        next.predicate = predicate
        next.sortDescriptors = sortDescriptors
        next.fetchLimit = limit ?? 1000
        next.fetchOffset = 0
        bgContext.perform {
            let dbEventIds = (try? self.bgContext.fetch(next)) ?? []
            let currentVPostIds = Set(self.vPosts.map { item in
                item.id
            })
            let onlyUnrendered = dbEventIds.filter { item in
                !currentVPostIds.contains(item.id)
            }
            let nextItems = self.transformInBG(onlyUnrendered)
            Task { @MainActor in
                print("\(taskId) 🟠🟠🟠🟠🟠 self.vPosts = nextItems (\(nextItems.count)) + self.vPosts ")
                self.vPosts = nextItems + self.vPosts
            }
        }
    }
    
    
    // Only for .events, not .vPosts, on main
    public func loadNewerEvents(_ limit:Int? = nil, taskId:String) {
        self.loadNewerEventsSubject.send((limit, taskId))
    }
    
    // Only for .events, not .vPosts, on main
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
    

    // Only for .events, not .vPosts, on main
    public func loadOlderEvents(_ limit:Int? = nil, taskId:String) {
        self.loadOlderEventsSubject.send((limit, taskId))
    }
    
    // Only for .events, not .vPosts, on main
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
    
    
    public func transformOnMain(_ events:[Event]) -> [VPost] {
        if followingKeys.count == 0 { print("🔴🔴🔴 followingKeys is empty, this gives PFP caching problems!!!") }
        let transformer = VPostTransformer(viewContext, followingKeys: followingKeys)
        
        return events
            .compactMap { transformer.toVPost($0) }
    }
    
    private func transformInBG(_ events:[Event]) -> [VPost] {
        let transformer = VPostTransformer.bg
        return bgContext.performAndWait {
            return events
                .compactMap { transformer.toVPost($0, forceBg: true) }
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
    
    public func add(_ task:ReqTask) {
        tasks.insert(task)
    }
    
    public func remove(_ task:ReqTask) {
        tasks.remove(task)
    }
    
    public func task(with subscriptionId:String) -> ReqTask? {
        tasks.first(where: { $0.id == subscriptionId })
    }
    
    public func tasks(with subscriptionIds:Set<String>) -> [ReqTask] {
        return tasks.filter { subscriptionIds.contains($0.id) }
    }
}

struct ReqTask: Identifiable, Hashable {
    
    static func == (lhs: ReqTask, rhs: ReqTask) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let createdAt = Date.now
    let id = UUID().uuidString
    var subscriptionId:String { id }
    
    let reqCommand:(_ taskId:String) -> Void
    let processResponseCommand:(_ taskId:String) -> Void
    
    public func fetch() {
        self.reqCommand(subscriptionId)
    }
    public func process() {
        self.processResponseCommand(subscriptionId)
    }
}
