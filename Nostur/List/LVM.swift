//
//  ListViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import Foundation
import CoreData
import Combine
import Compactor

let LVM_MAX_VISIBLE = 150 // Will only be ignored if last appeared is older

class LVMState: ObservableObject {
    @Published var listId = "Following"
    @Published var viewIsVisible = true
    @Published var isAtTop = true
    @Published var restoreScrollTo:Event? = nil // @TODO: Maybe doesn't need to be @Published?
    @Published var restoreScrollToAnchor = "BOTTOM"  // @TODO: Maybe doesn't need to be @Published?
    
    // LAST IS OLDEST, NEWEST IS AT TOP (FIRST)
    var vPostLeafs:[VPost] = [] {
        didSet {
            DispatchQueue.main.async {
                self.vPosts = self.vPostLeafs.listEmptySectionModels()
            }
        }
    }
    
    @Published var vPosts:[RagiSmoothListSectionModel<RagiSmoothListEmptySection, VPost>] = [] // This is fed to the RegiSmoothList
    @Published var state:LVM.LIST_STATE = .AWAITING_FIRST_FETCH {
        didSet {
            print("LVMState.state: \(oldValue) -> \(state) vPosts: \(vPostLeafs.count) visible: \(viewIsVisible) id:\(listId)")
        }
    }
        
}

//@MainActor
class LVM: NSObject, ObservableObject {
    let ot:OnboardingTracker = .shared
    
    let FETCH_FEED_INTERVAL = 3.0
    
    var listId:String
    var id:String { listId }
    var listStateObjectId:NSManagedObjectID?
    var pubkey:String
    var pubkeys:Set<String>
    
    var viewIsVisible:Bool { lvmState.viewIsVisible }
    var state:LIST_STATE {
        get { lvmState.state }
        set { lvmState.state = newValue }
    }
    
    var frc:NSFetchedResultsController<Event>?
    
    enum LIST_STATE:String {
        case AWAITING_FIRST_FETCH = "AWAITING_FIRST_FETCH"
        case AWAITING_RESTORED_FETCH = "AWAITING_RESTORED_FETCH"
        case COMPLETED_FIRST_FETCH = "COMPLETED_FIRST_FETCH"
        case AWAITING_RESTORE_SCROLL = "AWAITING_RESTORE_SCROLL"
        case AWAITING_SCROLL = "AWAITING_SCROLL"
        case COMPLETED_RESTORED_FETCH_WITH_SCROLL = "COMPLETED_RESTORED_FETCH_WITH_SCROLL"
        case SCROLLED_TO_END = "SCROLLED_TO_END"
        case SWITCHING_ACCOUNT = "SWITCHING_ACCOUNT"
    }
    
    private var fetchFeedTimer: Timer?
    var contentChangedSubject = CurrentValueSubject<[Event], Never>([]) // Need it for debounce etc
    
    
    
    var previousLastAppearedEvent:Event?
    
    var lastAppearedSubject = CurrentValueSubject<Event?, Never>(nil) // Need it for debounce etc
    var lastAppeared:Event? {
        get { lastAppearedSubject.value }
        set { lastAppearedSubject.send(newValue) }
    }
    var lastAppearedId:String? // so we dont have to fetch from different context by objectId if we want to save ListState in background
    var lastAppearedAnchor = "BOTTOM"
    var lastAppearedIndex:Int? { lastAppearedId != nil ? lvmState.vPostLeafs.firstIndex(where: { $0.id == self.lastAppearedId }) : nil }

    var lastRead:Event? {
        didSet {
            lastReadId = lastRead?.id
        }
    }
    var lastReadId:String? // so we dont have to fetch from different context by objectId if we want to save ListState in background
    var lastReadIdIndex:Int? { lastReadId != nil ? lvmState.vPostLeafs.firstIndex(where: { $0.id == self.lastReadId }) : nil }
    
    private var subscriptions = Set<AnyCancellable>()
    
    var unrenderedEventsSubject = CurrentValueSubject<[Event], Never>([])
    var unrenderedEvents:[Event] {
        get { unrenderedEventsSubject.value }
        set { unrenderedEventsSubject.send(newValue) }
    }
    var alreadySkipped = false
    var danglingObjectIds:Set<NSManagedObjectID> = [] // posts that are transformed, but somehow not on screen. either we put on on screen or not, dont transform over and over again, so for some reason these are not on screen, dont know why. keep track here and dont transform again
    
    var didCatchup = false
    
    // MARK: FROM DB TO SCREEN STEP 3:
    private func processPostsInBackground(_ events:[Event]) { // events are from viewContext
        let context = DataProvider.shared().container.newBackgroundContext()
        
        // onScreenIds includes leafs and parents, so all posts.
        let onScreenIds = self.lvmState.vPostLeafs.reduce(Set<NSManagedObjectID>()) { partialResult, vPost in
            partialResult.union(Set([vPost.objectID] + vPost.parentPosts.map { $0.objectID }))
        }
        
        context.perform { [unowned self] in
            let transformer = VPostTransformer(context) // Tranform in bg
            let currentVPostLeafs = self.lvmState.vPostLeafs // viewContext. First (0) is newest
            let lastCreatedAt = currentVPostLeafs.last?.created_at ?? 0
            var newVPostLeafs:[VPost] = []
            var transformedObjectIds = Set<NSManagedObjectID>()
            for event in self.unrenderedEvents {
                guard !danglingObjectIds.contains(event.objectID) else { continue } // Skip if the post is already on screen
                guard !onScreenIds.contains(event.objectID) else { continue } // Skip if the post is already on screen
                if let newVPostLeaf = transformer.toVPost(event) {
                    guard newVPostLeaf.created_at > lastCreatedAt else { continue } // Skip if it is older than last leaf on screen
                    transformedObjectIds.insert(newVPostLeaf.objectID)
//                    print("transformed: \(newVPostLeaf.id) \(newVPostLeaf.displayName) -- parentPosts: \(newVPostLeaf.parentPosts.count)")
                    newVPostLeafs.append(newVPostLeaf)
                }
            }
            
            let added = newVPostLeafs
//                .filter(notMuted) // TODO ADD BACK NOT MUtED IN RIGHT CONTEXT / THREAD
                .suffix(LVM_MAX_VISIBLE) // Don't add too many posts
            
            print("Transformed \(transformedObjectIds.count) posts")
            if currentVPostLeafs.count == 0 {
                let leafThreads = self.renderLeafs(added) // Transforms seperate posts into threads, .id for each thread is leaf.id
                print("🟢🟢🟢🟢🟢🟢🟢🟢🟢")
                print("🟢🟢🟢🟢🟢🟢🟢🟢🟢")
                print("🟢🟢🟢🟢🟢🟢🟢🟢🟢")
                
                DispatchQueue.main.async {
                    self.lvmState.vPostLeafs = leafThreads
//                    self.lvmState.vPosts = leafThreads.listEmptySectionModels()
                    self.lvmCounter.count = self.itemsAfterLastAppeared
                }
            }
            else {
                
                // FOR REALTIME, FETCH RELATED OF LAST 4 POSTS
                if !alreadySkipped && transformedObjectIds.count > 0 && transformedObjectIds.count < 5 {
                    fetchRelated(added.prefix(4))
                    alreadySkipped = true // Skip this render, wait for the next one so we have the related items
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
                        if self.alreadySkipped == true {
                            print("Still waiting... force render")
                            self.processPostsInBackground(self.unrenderedEvents)
                        }
                    }
                    return
                }
                else {
                    alreadySkipped = false
                }
                
                // if we have just 1 new post, and it is a reply to the most recent post on screen, merge it
                // hmmm added, first is not enough the know if just 1 was added
                if added.first?.parentPosts.first?.id == currentVPostLeafs.first?.id {
                    let lastCountValue = currentVPostLeafs.first?.threadPostsCount ?? 0
                    var truncateFirst = added.first!
                    truncateFirst.parentPosts = truncateFirst.parentPosts.suffix(lastCountValue)
                    truncateFirst.threadPostsCount = 1 + lastCountValue
                    let currentAndJustOneExtra = Array([truncateFirst] + currentVPostLeafs.dropFirst(1))
                    
                    DispatchQueue.main.async {
                        self.lvmState.vPostLeafs = currentAndJustOneExtra
//                        self.lvmState.vPosts = self.lvmState.vPostLeafs.listEmptySectionModels()
                        self.lvmCounter.count = self.lvmState.isAtTop ? 0 : (self.lvmCounter.count + 1)
                    }
                }
                else {
                    // truncate new replies for threads already on screen
                    let addedTruncated = self.renderNewLeafs(added, onScreen: currentVPostLeafs)
//                    let currentVPostsCount = threadCount(currentVPosts)
                    
                    DispatchQueue.main.async {
                        self.lvmState.vPostLeafs = (addedTruncated + currentVPostLeafs)
                        
                        self.danglingObjectIds = self.danglingObjectIds.union(transformedObjectIds.subtracting(Set(self.lvmState.vPostLeafs.map { $0.objectID })))
//                        self.lvmState.vPosts = self.lvmState.vPostLeafs.listEmptySectionModels()
                        self.lvmCounter.count = self.lvmState.isAtTop ? 0 : (self.lvmCounter.count + transformedObjectIds.count) // transformCounter is also added right???
                    }
                }
            }
        }
    }
    
    func fetchRelated(_ recentVPosts:ArraySlice<VPost>) {
        let ids = recentVPosts.map { $0.id }
        SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventReferences(ids: ids)))
        print("Skip render and fetch related of \(ids.joined(separator: ",")) first.")
    }
    
    func renderLeafs(_ vPosts:ArraySlice<VPost>) -> [VPost] {
        let sortedByLongest = vPosts.sorted(by: { $0.parentPosts.count > $1.parentPosts.count })

        var renderedIds = [String]()
        var renderedPosts = [VPost]()
        for post in sortedByLongest {
            if post.isRepost && post.firstQuoteId != nil && renderedIds.contains(post.firstQuoteId!) {
                // Reposted post already on screen
                continue
            }
            guard !renderedIds.contains(post.id) else { continue } // Post is already in screen
            
            guard !post.isRepost else {
                // Render a repost, but track firstQuoteId instead of .id in renderedIds
                if let firstQuoteId = post.firstQuoteId {
                    renderedIds.append(firstQuoteId)
                    renderedIds.append(post.id)
                    renderedPosts.append(post)
                }
                continue
            }
            
            guard post.parentPosts.count > 0 else {
                // Render a root post, that has no parents
                renderedIds.append(post.id)
                renderedPosts.append(post)
                continue
            }
            // render thread, truncated
            var truncatedPost = post
            truncatedPost.parentPosts = post.parentPosts.filter { !renderedIds.contains($0.id) }
            truncatedPost.threadPostsCount = 1 + truncatedPost.parentPosts.count
            truncatedPost.isTruncated = post.parentPosts.count > truncatedPost.parentPosts.count
            renderedIds.append(contentsOf: [truncatedPost.id] + truncatedPost.parentPosts.map { $0.id })
            renderedPosts.append(truncatedPost)
        }
        return renderedPosts
            .sorted(by: { $0.parentPosts.first?.created_at ?? $0.created_at > $1.parentPosts.first?.created_at ?? $1.created_at })
    }
    
    func renderNewLeafs(_ added:ArraySlice<VPost>, onScreen:[VPost]) -> [VPost] {
        let newSortedByLongest = added.sorted(by: { $0.parentPosts.count > $1.parentPosts.count })

        var onScreenIds = onScreen.flatMap {
            if $0.isRepost {
                return [$0.id] + [$0.firstQuoteId]
            }
            else {
                return [$0.id] + $0.parentPosts.map { $0.id }
            }
        }

        var newRenderedPosts = [VPost]()
        for post in newSortedByLongest {
            if post.isRepost && post.firstQuoteId != nil && onScreenIds.contains(post.firstQuoteId!) {
                // Reposted post already on screen
                continue
            }
            guard !onScreenIds.contains(post.id) else { continue } // Post is already in screen
            
            guard !post.isRepost else {
                // Render a repost, but track firstQuoteId instead of .id in renderedIds
                if let firstQuoteId = post.firstQuoteId {
                    onScreenIds.append(firstQuoteId)
                    onScreenIds.append(post.id)
                    newRenderedPosts.append(post)
                }
                continue
            }
            
            guard post.parentPosts.count > 0 else {
                // Render a root post, that has no parents
                onScreenIds.append(post.id)
                newRenderedPosts.append(post)
                continue
            }
            // render thread, truncated
            var truncatedPost = post
            if let replyToId = post.parentPosts.last?.id { // always keep at least replyingTo
                truncatedPost.parentPosts = post.parentPosts.filter { $0.id == replyToId || !onScreenIds.contains($0.id) }
            }
            truncatedPost.isTruncated = post.parentPosts.count > truncatedPost.parentPosts.count
            truncatedPost.threadPostsCount = 1 + truncatedPost.parentPosts.count
            onScreenIds.append(contentsOf: [truncatedPost.id] + truncatedPost.parentPosts.map { $0.id })
            newRenderedPosts.append(truncatedPost)
        }
        return newRenderedPosts
            .sorted(by: { $0.parentPosts.first?.created_at ?? $0.created_at > $1.parentPosts.first?.created_at ?? $1.created_at })
    }
    
    var lvmState:LVMState
    var lvmCounter = LVMCounter()
    
    init(pubkey:String, pubkeys:Set<String>, listId:String) {
        self.lvmState = LVMState()
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        self.listId = listId
        self.lvmState.listId = listId
        super.init()
        
        let ctx = DataProvider.shared().viewContext
        var ls:ListState?
        ls = ListState.fetchListState(pubkey, listId: listId, context: ctx)
        
        if (ls == nil) {
            ls = ListState(context: ctx)
            ls!.listId = listId
            ls!.pubkey = pubkey
            ls!.updatedAt = Date.now
            do { try ctx.save() }
            catch { print("could not save new listState") }
        }
        
        let lastAppeared = ls!.lastAppearedId != nil
        ? (try? Event.fetchEvent(id: ls!.lastAppearedId!, context: ctx))
        : nil
        
        let lastRead = ls!.mostRecentAppearedId != nil
        ? (try? Event.fetchEvent(id: ls!.mostRecentAppearedId!, context: ctx))
        : nil
        
        self.listStateObjectId = ls!.objectID
        self.lastRead = lastRead
        self.lastAppeared = lastAppeared
        if (lastAppeared != nil) {
            self.lvmState.state = .AWAITING_RESTORED_FETCH
            self.lvmState.restoreScrollTo = self.lastAppeared
            self.lvmState.restoreScrollToAnchor = ls?.lastAppearedAtAnchor ?? "BOTTOM"
//            print("🟢🟢 lastAppeared.id on init: \(self.lastAppeared?.id ?? "")")
        }
        self.performFetch()
        self.fetchFeedTimer?.invalidate()
        self.fetchFeedTimer = Timer.scheduledTimer(withTimeInterval: FETCH_FEED_INTERVAL, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.fetchFeedTimerNextTick()
        }
        lvmState.viewIsVisible = (UserDefaults.standard.string(forKey: "selected_subtab") ?? "Unknown") == listId
        addSubscriptions()
    }
    
    func changeLVM(pubkey:String, pubkeys:Set<String>, listId:String) {
        self.lvmState.state = .AWAITING_FIRST_FETCH
        self.unrenderedEvents = []
        self.lvmState.vPostLeafs = []
        self.lvmState.listId = listId
        
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        self.listId = listId
        
        let ctx = DataProvider.shared().viewContext
        var ls = ListState.fetchListState(pubkey, listId: listId, context: ctx)
        ThreadWarning.which("changeLVM \(listId) ")
        if (ls == nil) {
            ls = ListState(context: ctx)
            ls!.listId = listId
            ls!.pubkey = pubkey
            ls!.updatedAt = Date.now
            do { try ctx.save() }
            catch { print("could not save new listState") }
        }
        
        let lastAppeared = ls!.lastAppearedId != nil
        ? (try? Event.fetchEvent(id: ls!.lastAppearedId!, context: ctx))
        : nil
        
        let lastRead = ls!.mostRecentAppearedId != nil
        ? (try? Event.fetchEvent(id: ls!.mostRecentAppearedId!, context: ctx))
        : nil
        
        self.listStateObjectId = ls!.objectID
        self.lastRead = lastRead
        self.lastAppeared = lastAppeared
        let anchor = ls?.lastAppearedAtAnchor ?? "BOTTOM"
        
        if (lastAppeared != nil) {
            self.state = .AWAITING_RESTORED_FETCH
            self.lvmState.restoreScrollTo = self.lastAppeared
            self.lvmState.restoreScrollToAnchor = anchor
        }
        self.performFetch()
        
        self.fetchFeedTimer?.invalidate()
        self.fetchFeedTimer = Timer.scheduledTimer(withTimeInterval: FETCH_FEED_INTERVAL, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.fetchFeedTimerNextTick()
        }
        lvmState.viewIsVisible = (UserDefaults.standard.string(forKey: "selected_subtab") ?? "Unknown") == listId
    }
    
    func changeFollowers(pubkeys:Set<String>) {
        self.pubkeys = pubkeys
        self.frc = nil
        performFetch()
    }
    
    // MARK: STEP 0: FETCH FROM RELAYS
    func fetchFeedTimerNextTick() {
        guard self.viewIsVisible else { return }
        guard !Importer.shared.isImporting else { print("⏳ Still importing, new fetch skipped."); return }
        
        if (ot.isOnboarding && self.pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
            fetchEvents(pubkeys: Set(ot.followingKeys), amount: 100)
            ot.didFillTimeline = true
            //            firstTimeCompleted = true
            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: "firstTimeCompleted")
            }
        }
        else if (!ot.isOnboarding) {
            let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 4)  // 4 hours  ago
            DispatchQueue.main.async {
                let cutOffPoint = min(self.lastAppeared?.created_at ?? hoursAgo, hoursAgo) // 8 hours ago or longer until lastAppeared Event
                
                // THIS SUBSCRIPTION WILL STAY ACTIVE:
                fetchEvents(pubkeys: self.pubkeys, subscriptionId: self.id)
                
                // THIS ONE IS TO CATCH UP, WILL CLOSE AFTER EOSE:
                if (!self.didCatchup) {
                    let f = TimeCompactor(ifZero: nil, style: .short, roundSmallToWhole: true)
                    let ago =  f.string(from: Double(Date.now.timeIntervalSince(Date(timeIntervalSince1970: Double(cutOffPoint)))) as NSNumber)!
                    fetchEvents(pubkeys: self.pubkeys, amount: 5000, since: cutOffPoint, subscriptionId: "\(self.id)-CATCHUP-\(ago)")
                    self.didCatchup = true
                }
//                 cutOff doesnt work well, since hits with some time ago limit (500)?
//                fetchEvents(pubkeys: self.pubkeys, subscriptionId: self.id)
            }
        }
    }
}


extension LVM {
    func addSubscriptions() {
        keepListStateSaved()
        requestFooterCounters()
        updatePostFeed()
        trackLastAppeared()
        processNewEventsInBg()
        keepFilteringMuted()
    }
    
    func keepFilteringMuted() {
        receiveNotification(.muteListUpdated)
            .sink { notification in
                self.lvmState.vPostLeafs = self.lvmState.vPostLeafs.filter(notMuted)
            }
            .store(in: &subscriptions)
    }
    
    func processNewEventsInBg() {
        unrenderedEventsSubject
           .sink { posts in
               self.processPostsInBackground(posts)
           }
           .store(in: &subscriptions)
    }
        
    func trackLastAppeared() {
        lastAppearedSubject
            .throttle(for: 0.05, scheduler: RunLoop.main, latest: true)
            .compactMap { $0 }
            .sink { [weak self] event in
                guard let self = self else { return }
                // TRACK ANCHOR
                if let previous = self.lastAppeared {
                    self.lastAppearedAnchor = event.created_at > previous.created_at ? "BOTTOM" : "TOP"
                }

                self.lastAppearedId = event.id // So dont need to mangle contexts if we just need an id (for saving ListState)
                
//                // TRACK MOST RECENT READ
//                if let recent = self.lastRead, event.created_at > recent.created_at {
//                    self.lastRead = event
//                }
//                else if self.lastRead == nil {
//                    self.lastRead = event
//                }
                
                // unread should only go down, not up
                // only way to go up is when new posts are added.
                if self.itemsAfterLastAppeared < self.lvmCounter.count {
                    self.lvmCounter.count = self.itemsAfterLastAppeared
                    self.lastRead = event
                }
                else if self.lastRead == nil {
                    self.lastRead = event
                }
            }
            .store(in: &subscriptions)
    }
    
    // 1 2 3 [4] 5 6 7 8 9 10
    // 0 1 2 [3] 4 5 6 7 8 9
    // Old version, without threads
//    var itemsAfterLastAppeared:Int {
//        guard let lastAppearedIndex = self.lastAppearedIndex else { return self.lvmState.vPosts.count }
//        return max(0,((self.lvmState.vPosts.count - lastAppearedIndex) - 1))
//    }
    
    // With threads. cannot simply count, need to use the thread count value
    var itemsAfterLastAppeared:Int {
        guard let lastAppearedIndex = self.lastAppearedIndex else {
//            return threadCount(self.lvmState.vPostLeafs) // all is unread
            // if all is unread, we start at top. if we start at top we set counter to 0
            return 0
        }
        let postsAfterLastAppeared = self.lvmState.vPostLeafs.prefix(lastAppearedIndex)
        let count = threadCount(Array(postsAfterLastAppeared)) // TODO: Performance, can use ArraySlice somehow? swift-algorithms?
        return max(0,count) // cant go negative
    }
    
    func keepListStateSaved() {
        lastAppearedSubject
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: false)
        //            .debounce(for: .seconds(1), scheduler: DispatchQueue.global())
        //            .throttle(for: .seconds(5), scheduler: DispatchQueue.global(), latest: false)
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                let context = DataProvider.shared().container.newBackgroundContext()
                context.perform {
                    guard let listStateObjectId = self.listStateObjectId else { return }
                    guard let listState = context.object(with: listStateObjectId) as? ListState else { return }
                    listState.lastAppearedId = self.lastAppearedId
                    listState.mostRecentAppearedId = self.lastReadId
                    listState.lastAppearedAtAnchor = self.lastAppearedAnchor
                    listState.updatedAt = Date.now
//                    listState.unreadCount = Int64(self.lvmCounter.unreadCounterNew)
                    do {
                        try context.save()
                    }
                    catch {
                        print("🔴🔴 Error saving list state \(self.id) \(listState.pubkey)")
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    func requestFooterCounters() {
        // AFTER 1 SEC OF STOP SCROLLING, WE WANT TO FETCH #E AND P (HERE)
        //        $lastAppeared
        lastAppearedSubject
            .filter({ _ in
                self.lvmState.vPostLeafs.count > 0 // Don't do anything if there is nothing on screen yet!
            })
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)
        //            .debounce(for: .seconds(1), scheduler: DispatchQueue.global())
        //            .throttle(for: .seconds(5), scheduler: DispatchQueue.global(), latest: true)
        //            .receive(on: DispatchQueue.global())
            .sink { [weak self] event in
                guard let self = self else { return }
                guard let event = event else { return }
                // get 5 posts before or after
                if event.created_at > (self.lastAppeared?.created_at ?? 0) {
                    // get before
                    if let indexOfPost = self.unrenderedEvents.firstIndex(of: event) {
                        let five = [
                            self.unrenderedEvents[safe: indexOfPost],
                            self.unrenderedEvents[safe: indexOfPost - 1],
                            self.unrenderedEvents[safe: indexOfPost - 2],
                            self.unrenderedEvents[safe: indexOfPost - 3],
                            self.unrenderedEvents[safe: indexOfPost - 4]
                        ]
                        self.requestForJustAppeared(five.compactMap { $0 })
                    }
                }
                else {
                    // get after
                    if let indexOfPost = self.unrenderedEvents.firstIndex(of: event) {
                        let five = [
                            self.unrenderedEvents[safe: indexOfPost],
                            self.unrenderedEvents[safe: indexOfPost + 1],
                            self.unrenderedEvents[safe: indexOfPost + 2],
                            self.unrenderedEvents[safe: indexOfPost + 3],
                            self.unrenderedEvents[safe: indexOfPost + 4]
                        ]
                        self.requestForJustAppeared(five.compactMap { $0 })
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    func scrollToEnd() {
        state = .AWAITING_SCROLL
        sendNotification(.shouldScrollToRecent)
        self.lvmCounter.count = 0
        if (self.lastAppeared != self.lvmState.vPostLeafs.last?.event) {
            self.lastAppeared = self.lvmState.vPostLeafs.last?.event
        }
        let context = DataProvider.shared().container.newBackgroundContext()
        context.perform {
            guard let listStateObjectId = self.listStateObjectId else { return }
            guard let listState = context.object(with: listStateObjectId) as? ListState else { return }
            listState.lastAppearedId = self.lastAppearedId
            listState.mostRecentAppearedId = self.lastReadId
            listState.lastAppearedAtAnchor = "BOTTOM"
            listState.updatedAt = Date.now
//            listState.unreadCount = 0
            
            // TODO: ALso implement cutoff, if 1000 posts on screen, --> .suffix 100. PROBLEM IS SCROLL OFFSET GLITCH
            do {
                try context.save()
            }
            catch {
                print("🔴🔴 Error saving list state \(self.id) \(listState.pubkey)")
            }
        }
    }
    
    func scrollABit() {
        sendNotification(.scrollABit)
    }
    
    func didReachEnd() {
        guard state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
        guard state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
        guard state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we
        
        self.lvmCounter.count = 0
    }
    
    func requestForJustAppeared(_ events:[Event]) {
        guard self.viewIsVisible else { return }
        let ids = ids(events)
        let contacts = events.compactMap {
            $0.isRepost
                ? $0.firstQuote?.contact
                : $0.contact
        }
        let shouldVerifyContacts = contacts.filter { NIP05.shouldVerify($0) }
        
//        ThreadWarning.which("requestForJustAppeared on \(self.id)")
        fetchStuffForLastAddedNotes(ids: ids)
        //            fetchMissingReplyToContacts(events: events) // TODO: FIXME
        
        // TODO: FIX BROKEN
//        let context = DataProvider.shared().container.newBackgroundContext()
//        context.perform {
        NIP05.verifyBatch(contacts: shouldVerifyContacts, context: DataProvider.shared().viewContext)
//        }
    }
    
    // TODO: WE NEED TO USE THIS.. JUST MOVED FROM ListView TO LVM but not updated yet
    func fetchMissingReplyToContacts(events:[Event]) {
        // PLAN
        // FOR EVERY EVENT
        //   TAKE P's. IF P IS NOT IN EVENT.CONTACTS, ADD IT
        // FINALLY, EVERY MISSING OR EMPTY CONTACT
        //  sp.fetch!
        let context = DataProvider.shared().container.newBackgroundContext()
        context.perform {
            for event in events {
                let pubkeys = Array(Set(event.pTags()))
                if pubkeys.count > 0 {
                    let contacts = Contact.fetchByPubkeys(pubkeys, context: context)
                    //                event.objectWillChange.send()
                    // dit moet op main queue?
                    //                ThreadWarning.which("Event.addToContacts( 💖💖💖")
                    event.addToContacts(NSSet(array: contacts))
                }
            }
            // TODO: FIXEN
            // TODO, bij importer, replyTo p in event.replyToPTag for speed up
            let pubkeys = Array(Set(events.flatMap { TagsHelpers($0.tags()).pTags().map{ $0.pubkey } }))
            let contacts = Contact.fetchByPubkeys(pubkeys, context: context)
            let missingPubkeys = pubkeys.filter {
                contacts.map { $0.pubkey }.firstIndex(of: $0) == nil
            }
            let emptyContactPubkeys = pubkeys
                .compactMap { pubkey in
                    contacts.first(where: { $0.pubkey == pubkey })
                }
                .filter { $0.metadata_created_at == 0 }
                .map { $0.pubkey }
            
            guard (missingPubkeys + emptyContactPubkeys).count > 0 else { return }
            //        ThreadWarning.which("SocketPool.shared.sendMessag 💖💖💖")
            SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingPubkeys + emptyContactPubkeys )))
        }
    }
}

extension LVM: NSFetchedResultsControllerDelegate {
    
    // MARK: FROM DB TO SCREEN STEP 1: FETCH REQUEST
    func performFetch() {
        self.frc = NSFetchedResultsController(fetchRequest: Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: self.lastAppeared?.created_at ?? 0), managedObjectContext: DataProvider.shared().viewContext, sectionNameKeyPath: nil, cacheName: nil) // TODO: Try cache?
        frc?.delegate = self
        
        if viewIsVisible {
            do {
                try self.frc?.performFetch()
                guard let posts = self.frc?.fetchedObjects else { return }
                // self.contentChangedSubject.send(posts) // Disabled, no debounce/throttle on first fetch
                self.setUnorderedEvents(events: posts)
            } catch {
                print("🔴🔴🔴 failed to fetch items")
            }
        }
    }
    
    // MARK: FROM DB TO SCREEN STEP 2: FIRST FILTER PASS, GETTING PARENTS AND LIMIT, NOT ON SCREEN YET
    func setUnorderedEvents(events:[Event]) {
        switch (self.state) {
            case .AWAITING_FIRST_FETCH: // Show last X (FORCED CUTOFF)
                self.unrenderedEvents = events.filter(onlyRootOrReplyingToFollower)
                    .prefix(LVM_MAX_VISIBLE)
                    .map {
                        $0.parentEvents = Event.getParentEvents($0)
                        return $0
                    }
                self.lvmState.state = .COMPLETED_FIRST_FETCH
                
            case .AWAITING_RESTORED_FETCH: // Show last read, until end
                // show last 100 if LR is within it
                // else show all
                let lastAppearedIndex = self.lastAppeared != nil ? self.unrenderedEvents.firstIndex(where: { $0.id == self.lastAppearedId }) ?? -1 : -1
                
                if (lastAppearedIndex == -1) { // LAST APPEARED NOT IN EVENTS (FORCED CUTOFF)
                    self.unrenderedEvents = events.filter(onlyRootOrReplyingToFollower)
                        .prefix(LVM_MAX_VISIBLE)
                        .map {
                            $0.parentEvents = Event.getParentEvents($0)
                            return $0
                        }
//                        .sorted(by: { $0.created_at < $1.created_at } )
                    self.state = .COMPLETED_FIRST_FETCH // POST NOT IN LIST, SO DONT RESTORE SCROLL.
                }
                if (lastAppearedIndex < LVM_MAX_VISIBLE) {
                    self.state = .AWAITING_RESTORE_SCROLL // POST IS IN LIST, SO WE CAN RESTORE SCROLL. (FORCED CUTOFF)
                    self.unrenderedEvents = events.filter(onlyRootOrReplyingToFollower)
                        .prefix(LVM_MAX_VISIBLE)
                        .map {
                            $0.parentEvents = Event.getParentEvents($0)
                            return $0
                        }
//                        .sorted(by: { $0.created_at < $1.created_at } )
                }
                else {
                    self.state = .AWAITING_RESTORE_SCROLL // POST IN LIST, BUT OUTSIDE MAX VISIBLE.. TODO: HANDLE THIS. NO CUTOFF NOW
                    self.unrenderedEvents = events.filter(onlyRootOrReplyingToFollower)
                        .map {
                            $0.parentEvents = Event.getParentEvents($0)
                            return $0
                        }
//                        .sorted(by: { $0.created_at < $1.created_at } )
                }
//                self.updateUnreadCount()
                
            default:
                let lastCreatedAt = self.lvmState.vPostLeafs.last?.created_at ?? 0 // SHOULD CHECK ONLY LEAFS BECAUSE ROOTS CAN BE VERY OLD
                self.unrenderedEvents = events
                    .filter { $0.created_at > lastCreatedAt } // skip all older than first on screen (check LEAFS only)
                    .filter(onlyRootOrReplyingToFollower)
//                    .sorted(by: { $0.created_at < $1.created_at } )
                    .suffix(LVM_MAX_VISIBLE * 2)
                    .map {
                        $0.parentEvents = Event.getParentEvents($0)
                        return $0
                    }
//                self.updateUnreadCount()
                return
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let posts = controller.fetchedObjects as? [Event] else { return }
        self.contentChangedSubject.send(posts)
    }
    
    func updatePostFeed() {
        contentChangedSubject
            .debounce(for: .seconds(2.5), scheduler: RunLoop.main)
            .throttle(for: .seconds(10), scheduler: RunLoop.main, latest: true)
            .sink { events in
                self.setUnorderedEvents(events: events)
            }
            .store(in: &subscriptions)
    }
    
    func updateUnreadCount() {
        guard let lastReadId = self.lastReadId else {
            self.lvmCounter.count = 0 //threadCount(lvmState.vPosts)
            return
        }
        if let index = lvmState.vPostLeafs.firstIndex(where: { $0.id == lastReadId }) {
            let postsAfterLastRead = lvmState.vPostLeafs.suffix(from: index + 1)
            self.lvmCounter.count = threadCount(Array(postsAfterLastRead))
        }
        else {
            self.lvmCounter.count = 0 //threadCount(lvmState.vPosts)
        }
    }
    
    func onlyRootOrReplyingToFollower(_ event:Event) -> Bool {
        // TODO: Add setting to show replies to all...
        return true
//        if let replyToPubkey = event.replyTo?.pubkey {
//            if pubkeys.contains(replyToPubkey) {
//                return true
//            }
//        }
//        return event.replyToId == nil
    }
}

func notMuted(_ vPost:VPost) -> Bool {
    let mutedRootIds = NosturState.shared.account?.mutedRootIds_ ?? []
    return !mutedRootIds.contains(vPost.id) && !mutedRootIds.contains(vPost.event.replyToRootId ?? "NIL")
}

extension Event {
    static func postsByPubkeys(_ pubkeys:Set<String>, lastAppearedCreatedAt:Int64 = 0) -> NSFetchRequest<Event> {
        
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8) // 8 hours ago
        
        // Take oldest timestamp: 8 hours ago OR lastAppearedCreatedAt
        // if we don't have lastAppearedCreatedAt. Take 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo)
        
        // get 15 events before lastAppearedCreatedAt (or 8 hours ago, if we dont have it)
        let frBefore = Event.fetchRequest()
        frBefore.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        frBefore.fetchLimit = 15 //TODO: need this even?
        frBefore.predicate = NSPredicate(format: "created_at <= %i AND kind IN {1,6} AND pubkey IN %@", cutOffPoint,  pubkeys)
        
        let newFirstEvent = try? DataProvider.shared().viewContext.fetch(frBefore).last
        
        let newCutOffPoint = newFirstEvent != nil ? newFirstEvent!.created_at : cutOffPoint
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        //        fr.fetchLimit = 500 //TODO: need this even?
        fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", newCutOffPoint,  pubkeys)
        return fr
    }
}

func threadCount(_ vPosts:[VPost]) -> Int {
    vPosts.reduce(0) { partialResult, vPost in
        (partialResult + vPost.threadPostsCount)
    }
}
