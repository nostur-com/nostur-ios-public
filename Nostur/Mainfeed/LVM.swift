//
//  ListViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import Foundation
import CoreData
import Combine

let LVM_MAX_VISIBLE:Int = 20

// LVM handles the main feed and other lists
// Posts are loaded from local database andprocessed in background,
// turning any Event (from database) into a NRPost (for view)
// The posts are in .nrPostLeafs and any update to .nrPostLeafs is reflected in SmoothList
// Uses InstantFeed() to go from start-up to posts on screen as fast as possible

// 

class LVM: NSObject, ObservableObject {
        
    @Published var state:LVM.LIST_STATE = .INIT
    @Published var nrPostLeafs:[NRPost] = [] {
        didSet {
            if state != .READY { state = .READY }
            leafsAndParentIdsOnScreen = self.getAllObjectIds(nrPostLeafs)
            leafIdsOnScreen = Set(nrPostLeafs.map { $0.id })
            
            // Pre-fetch next page.
            // Don't prefetch again unless the last post on screen has changed (this happens when a page is added during infinite scroll):
            // Don't prefetch again if the posts on screen are less than before (posts get removed from bottom, when new ones are added to top):
            if oldValue.count < nrPostLeafs.count, let oldLastId = oldValue.last?.id, let currentLastId = nrPostLeafs.last?.id, oldLastId != currentLastId {
                L.lvm.info("📖 \(self.nrPostLeafs.count) posts loaded. prefetching next page")
                self.throttledCommand.send {
                    self.fetchNextPage()
                }
            }
        }
    }
    var performingLocalOlderFetch = false
    var leafsAndParentIdsOnScreen:Set<String> = [] // Should always be in sync with nrPostLeafs
    var leafIdsOnScreen:Set<String> = []
    var onScreenSeen:Set<NRPostID> = []
    var alreadySkipped = false
    var danglingObjectIds:Set<NRPostID> = [] // posts that are transformed, but somehow not on screen. either we put on on screen or not, dont transform over and over again, so for some reason these are not on screen, dont know why. keep track here and dont transform again
    
    let ot:NewOnboardingTracker = .shared
    
    let FETCH_FEED_INTERVAL = 9.0
    var id:String // "Following", "Explore", "List-0xb893daf22106244b"
    var uuid = UUID().uuidString
    var name:String = "" // for debugging
    
    var listStateObjectId:NSManagedObjectID?
    var pubkey:String?
    var pubkeys:Set<String> {
        didSet {
            L.lvm.info("\(self.id) \(self.name) - pubkeys.count \(oldValue.count) -> \(self.pubkeys.count)")
        }
    }
    @Published var hideReplies = false {
        didSet {
            guard oldValue != hideReplies else { return }
            nrPostLeafs = []
            leafIdsOnScreen = []
            leafsAndParentIdsOnScreen = []
            self.performLocalFetch()
            self.saveListState()
        }
    }
    
    // for performance, .map .prefix(10) can maybe cause microhang with many pubkeys
    var pubkeysPrefixString:String {
        "[" + pubkeys.map {  "\"" +  $0.prefix(10) + "\"" }.joined(separator: ",") + "]"
    }
    
    var viewIsVisible:Bool {
        if id.prefix(5) == "List-" {
            return selectedSubTab == "List" && selectedListId == id
        }
        return selectedSubTab == id
    }
    
    // @AppStorage things
    var selectedSubTab = "" {
        didSet {
            if oldValue != selectedSubTab && viewIsVisible {
                self.didAppear()
            }
        }
    }
    var selectedListId = "" {
        didSet {
            if oldValue != selectedListId && viewIsVisible {
                self.didAppear()
            }
        }
    }
    
    var restoreScrollToId:String? = nil
    var initialIndex:Int = 0 // derived from restoreScrollToId's index
    
    func didAppear() {
        guard instantFinished else {
            startInstantFeed()
            return
        }
        L.lvm.info("🟢🟢 \(self.id) \(self.pubkey?.short ?? "") didAppear")
        self.restoreSubscription()
        
        
        // TODO: Provide a setting to enable this again, instead of InstantFeed()... maybe for Lists only
//        if nrPostLeafs.count == 0 {
//            if (self.restoreLeafs != nil) {
//                self.performLocalRestoreFetch()
//            }
//            else {
//                self.performLocalFetch()
//            }
//        }
    }
    
    func nextTickNow() {
        self.configureTimer()
        fetchFeedTimerNextTick()
    }
    
    enum LIST_STATE:String {
        case INIT = "INIT"
        case READY = "READY"
    }
    
    private var fetchFeedTimer: Timer?
    
    var throttledCommand = PassthroughSubject<() -> (), Never>()
    var lastAppearedIdSubject = CurrentValueSubject<String?, Never>(nil) // Need it for debounce etc
    var lastAppearedIndex:Int? {
        lastAppearedIdSubject.value != nil
        ? nrPostLeafs.firstIndex(where: { $0.id == self.lastAppearedIdSubject.value! })
        : nil
    }
    var lastReadId:String? // so we dont have to fetch from different context by objectId if we want to save ListState in background
    var lastReadIdIndex:Int? { lastReadId != nil ? nrPostLeafs.firstIndex(where: { $0.id == self.lastReadId! }) : nil }
    
    private var subscriptions = Set<AnyCancellable>()
    public func cleanUp() {
        self.subscriptions.removeAll()
    }
    
    var postsAppearedSubject = PassthroughSubject<[NRPostID], Never>()
    var startRenderingSubject = PassthroughSubject<[Event], Never>()
    var startRenderingOlderSubject = PassthroughSubject<[Event], Never>()
    var didCatchup = false
    var backlog = Backlog(auto: true)
    
    private func getAllObjectIds(_ nrPosts:[NRPost]) -> Set<NRPostID> {
        return nrPosts.reduce(Set<NRPostID>()) { partialResult, nrPost in
            if nrPost.isRepost, let firstPost = nrPost.firstQuote {
                // for repost add post + reposted post
                return partialResult.union(Set([nrPost.id, firstPost.id]))
            } else {
                return partialResult.union(Set([nrPost.id] + nrPost.parentPosts.map { $0.id }))
            }
        }
    }
    
    private func getAllEventIds(_ events:[Event]) -> Set<String> {
        return events.reduce(Set<String>()) { partialResult, event in
            if event.isRepost, let firstQuote = event.firstQuote_ {
                // for repost add post + reposted post
                return partialResult.union(Set([event.id, firstQuote.id]))
            }
            else {
                return partialResult.union(Set([event.id] + event.parentEvents.map { $0.id }))
            }
        }
    }
    
    func getRestoreScrollIndex(_ nrPostLeafs:[NRPost], lastAppearedId:String? = nil) -> Int? {
        if let lastAppearedId {
            if let index = nrPostLeafs.firstIndex(where: { $0.id == lastAppearedId }) {
                L.lvm.info("🟢🟢🟢 \(self.id) \(self.pubkey?.short ?? "") should scroll to leaf index: \(index)")
                if index+1 < nrPostLeafs.count {
                    return index+1
                }
                return index
            }
            // or maybe the leaf is now a parent?
            else if let index = nrPostLeafs.firstIndex(where: { $0.parentPosts.map { $0.id }.contains(lastAppearedId) }) {
                L.lvm.info("🟢🟢🟢 \(self.id) \(self.pubkey?.short ?? "") should scroll to leaf-to-parent index: \(index)")
                if index+1 < nrPostLeafs.count {
                    return index+1
                }
                return index
            }
            else {
                L.lvm.info("🟢🟢🟢 \(self.id) \(self.pubkey?.short ?? "") dunno where to scroll to 1")
                return nil
            }
        }
        else {
            return nil
        }
    }
    
    // MARK: FROM DB TO SCREEN STEP 3:
    private func processPostsInBackground(_ events:[Event], older:Bool = false) { // events are from viewContext
        let taskId = UUID().uuidString
        L.lvm.notice("\(self.id) \(self.name)/\(self.pubkey?.short ?? "") Start transforming \(events.count) events - \(taskId)")
        let context = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ? DataProvider.shared().viewContext : DataProvider.shared().bg
        
        // onScreenIds includes leafs and parents, so all posts.
        let leafsAndParentIdsOnScreen = leafsAndParentIdsOnScreen
        let leafIdsOnScreen = leafIdsOnScreen
        let currentNRPostLeafs = self.nrPostLeafs // viewContext. First (0) is newest
        
        context.perform { [weak self] in
            guard let self = self else { return }

            var newNRPostLeafs:[NRPost] = []
            var transformedObjectIds = Set<NRPostID>()
            for event in events {
//                guard !danglingObjectIds.contains(event.objectID) else { continue } // Skip if the post is already on screen
                guard !leafsAndParentIdsOnScreen.contains(event.id) else {
                    if let existingNRPost = currentNRPostLeafs.first(where: { $0.id == event.id }) {
                        newNRPostLeafs.append(existingNRPost)
                    }
                    continue
                } // Skip if the post is already on screen

                let newNRPostLeaf = NRPost(event: event, withParents: hideReplies ? false : true, withRepliesCount: true)
                transformedObjectIds.insert(newNRPostLeaf.id)
                newNRPostLeafs.append(newNRPostLeaf)
            }
            
            let added = newNRPostLeafs
//                .filter(notMuted) // TODO: ADD BACK NOT MUTED IN RIGHT CONTEXT / THREAD

            guard !transformedObjectIds.isEmpty else {
                DispatchQueue.main.async {
                    self.performingLocalOlderFetch = false
                }
                return
            }
            L.lvm.notice("\(self.id) \(self.name)/\(self.pubkey?.short ?? "") Transformed \(transformedObjectIds.count) posts - \(taskId)")

            if currentNRPostLeafs.isEmpty {
                let leafThreads = self.renderLeafs(added, onScreenSeen:self.onScreenSeen) // Transforms seperate posts into threads, .id for each thread is leaf.id
                
                let (danglers, newLeafThreads) = extractDanglingReplies(leafThreads)
                if !danglers.isEmpty {
                    L.og.info("🟪🟠🟠 processPostsInBackground: \(danglers.count) replies without replyTo. Fetching...")
                    fetchParents(danglers, older:older)
                }
                                
                DispatchQueue.main.async {
                    self.initialIndex = self.getRestoreScrollIndex(newLeafThreads, lastAppearedId: self.restoreScrollToId) ?? 0
                    L.sl.info("⭐️ LVM.initialIndex: \(self.name) \(self.initialIndex) - \(taskId)")
                    self.nrPostLeafs = newLeafThreads
                }
            }
            else {
                let newLeafThreadsWithMissingParents = self.renderNewLeafs(added, onScreen:currentNRPostLeafs, onScreenSeen: self.onScreenSeen)
                
                let (danglers, newLeafThreads) = extractDanglingReplies(newLeafThreadsWithMissingParents)
//                self.needsReplyTo.append(contentsOf: danglers)
                if !danglers.isEmpty {
                    L.og.info("🟠🟠 processPostsInBackground: \(danglers.count) replies without replyTo. Fetching...")
                    fetchParents(danglers, older:older)
                }
                putNewThreadsOnScreen(newLeafThreads, leafIdsOnScreen:leafIdsOnScreen, currentNRPostLeafs: currentNRPostLeafs, older:older)
            }
        }
    }
    
    func safeInsert(_ nrPosts:[NRPost], older:Bool = false) -> [NRPost] {
        let leafIdsOnScreen = Set(self.nrPostLeafs.map { $0.id })
        let onlyNew = nrPosts
            .filter { !leafIdsOnScreen.contains($0.id) }
            .uniqued(on: { $0.id })
        
        if older {
            // ADD TO THE END (OLDER POSTS, NEXT PAGE)
            performingLocalOlderFetch = false
            self.nrPostLeafs = self.nrPostLeafs + onlyNew
        }
        else {
            // ADD TO THE TOP, NEW POSTS.
            
            let nrPostLeafsWithNew = onlyNew + self.nrPostLeafs
            
            // IF AT TOP, TRUNCATE:
            
            let dropCount = max(0, nrPostLeafsWithNew.count - LVM_MAX_VISIBLE) // Drop any above LVM_MAX_VISIBLE
            if self.isAtTop && dropCount > 5 { // No need to drop all the time, do in batches of 5, or 10? // Data race in Nostur.LVM.isAtTop.setter : Swift.Bool at 0x112b87480 (Thread 1)
                let nrPostLeafsWithNewTruncated = nrPostLeafsWithNew.dropLast(dropCount)
                self.nrPostLeafs = Array(nrPostLeafsWithNewTruncated)
                L.lvm.info("\(self.id) \(self.name) safeInsert() dropped \(dropCount) from end ");
            }
            else {
                if !Set(nrPostLeafsWithNew.map{ $0.id }).subtracting(Set(self.nrPostLeafs.map { $0.id })).isEmpty {
                    self.nrPostLeafs = nrPostLeafsWithNew
                }
                else {
                    L.lvm.debug("\(self.id) \(self.name) safeInsert() no new items in Set. skipped ");
                }
            }
        }
        return onlyNew
    }
    
    var isAtTop = true
    
    func putNewThreadsOnScreen(_ newLeafThreadsWithDuplicates:[NRPost], leafIdsOnScreen:Set<String>, currentNRPostLeafs:[NRPost], older:Bool = false) {
        let newLeafThreads = newLeafThreadsWithDuplicates.filter { !leafIdsOnScreen.contains($0.id) }
        let diff = newLeafThreadsWithDuplicates.count - newLeafThreads.count
        if diff > 0 {
            L.lvm.debug("\(self.id) \(self.name)/\(self.pubkey?.short ?? "") putNewThreadsOnScreen: skipped \(diff) duplicates")
        }
        
        // leafs+parents count
        let addedCount = newLeafThreads.reduce(0, { partialResult, nrPost in
            return partialResult + nrPost.threadPostsCount
        })
        
        DispatchQueue.main.async {
            let inserted = self.safeInsert(newLeafThreads, older: older)
            self.fetchAllMissingPs(inserted)
        }
        
        guard !older else { return }
        DispatchQueue.main.async {
            if !self.isAtTop || !SettingsStore.shared.autoScroll {
                self.lvmCounter.count += addedCount
            }
        }
        
    }
    
    func fetchAllMissingPs(_ posts:[NRPost]) {
        DispatchQueue.global().async {
            let missingPs = posts.reduce([Ptag]()) { partialResult, nrPost in
                return partialResult + nrPost.missingPs
            }
            QueuedFetcher.shared.enqueue(pTags: missingPs)
        }
    }
    
    func fetchParents(_ danglers:[NRPost], older:Bool = false) {
        danglers.forEach { nrPost in
            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "LVM.001")
        }
        
        let danglingFetchTask = ReqTask(
            reqCommand: { [weak self] (taskId) in
                guard let self = self else { return }
                L.lvm.info("😈😈 reqCommand: \(self.id) \(self.name)/\(self.pubkey?.short ?? "") - \(taskId) - dng: \(danglers.count)")
                let danglerIds = danglers.compactMap { $0.replyToId }
                if !danglerIds.isEmpty {
                    req(RM.getEvents(ids: danglerIds, subscriptionId: taskId))
                }
            },
            processResponseCommand: { [weak self] (taskId, _) in
                guard let self = self else { return }
                L.lvm.info("😈😈 processResponseCommand: \(self.id) \(self.name)/\(self.pubkey?.short ?? "") - \(taskId) dng: \(danglers.count)")
                let lastCreatedAt = self.nrPostLeafs.last?.created_at ?? 0 // SHOULD CHECK ONLY LEAFS BECAUSE ROOTS CAN BE VERY OLD
                DataProvider.shared().bg.perform { [weak self] in
                    guard let self = self else { return }
                    let danglingEvents = danglers.map { $0.event }
                    if older {
                        self.setOlderEvents(events: self.filterMutedWords(danglingEvents))
                    }
                    else {
                        self.setUnorderedEvents(events: self.filterMutedWords(danglingEvents), lastCreatedAt:lastCreatedAt)
                    }
                }
            },
            timeoutCommand: { [weak self] (taskId) in
                guard let self = self else { return }
                L.lvm.info("😈😈 timeoutCommand: \(self.id) \(self.name)/\(self.pubkey?.short ?? "") - \(taskId) dng: \(danglers.count)")
                for d in danglers {
                    L.lvm.info("😈😈 timeoutCommand dng id: \(d.id)")
                }
                
                DispatchQueue.main.async {
                    self.putNewThreadsOnScreen(danglers, leafIdsOnScreen: self.leafIdsOnScreen, currentNRPostLeafs: self.nrPostLeafs, older: older)
                }
            })

        DispatchQueue.main.async {
            self.backlog.add(danglingFetchTask)
        }
        danglingFetchTask.fetch()
    }
    
    func extractDanglingReplies(_ newLeafThreads:[NRPost]) -> (danglers:[NRPost], threads:[NRPost]) {
        var danglers:[NRPost] = []
        var threads:[NRPost] = []
        newLeafThreads.forEach { nrPost in
            if nrPost.replyToId != nil && nrPost.parentPosts.isEmpty {
                danglers.append(nrPost)
            }
            else {
                threads.append(nrPost)
            }
        }
        return (danglers:danglers, threads:threads)
    }
    
    func leafThreadsToFlatNRPosts(_ leafThreads:[NRPost]) -> [NRPost] {
        return leafThreads.flatMap { nrPost in
            [nrPost] + nrPost.parentPosts
        }
    }
    
    func fetchRelated(_ recentNRPosts:ArraySlice<NRPost>) {
        let ids = recentNRPosts.map { $0.id }.compactMap { $0 }
        recentNRPosts.map { $0.event }.forEach { event in
            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "LVM.002")
        }
        req(RM.getEventReferences(ids: ids, subscriptionId: "RELATED-"+UUID().uuidString))
        L.lvm.info("\(self.id) \(self.name)/\(self.pubkey?.short ?? "") Skip render and fetch related of \(ids.joined(separator: ",")) first.")
    }
    
    func renderLeafs(_ nrPosts:[NRPost], onScreenSeen:Set<String>) -> [NRPost] {
        let sortedByLongest = nrPosts.sorted(by: { $0.parentPosts.count > $1.parentPosts.count })

        var renderedIds = [String]()
        var renderedPosts = [NRPost]()
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
            
            guard !post.parentPosts.isEmpty else {
                // Render a root post, that has no parents
                renderedIds.append(post.id)
                renderedPosts.append(post)
                continue
            }
            // render thread, truncated
            let truncatedPost = post
            // structure is: parentPosts: [root, reply, reply, reply, replyTo] post: ThisPost
            if let replyTo = post.parentPosts.last {
                // always keep at least 1 parent (replyTo)
                truncatedPost.parentPosts = post.parentPosts.dropLast(1).filter { !renderedIds.contains($0.id) && !onScreenSeen.contains($0.id) } + [replyTo]
            }
            truncatedPost.threadPostsCount = 1 + truncatedPost.parentPosts.count
            truncatedPost.isTruncated = post.parentPosts.count > truncatedPost.parentPosts.count
            renderedIds.append(contentsOf: [truncatedPost.id] + truncatedPost.parentPosts.map { $0.id })
            renderedPosts.append(truncatedPost)
        }
        return renderedPosts
            .sorted(by: { $0.created_at > $1.created_at })
//            .sorted(by: { $0.parentPosts.first?.created_at ?? $0.created_at > $1.parentPosts.first?.created_at ?? $1.created_at })
    }
    
    func renderNewLeafs(_ nrPosts:[NRPost], onScreen:[NRPost], onScreenSeen:Set<String>) -> [NRPost] {
        let onScreenLeafIds = onScreen.map { $0.id }
        let onScreenAllIds = onScreen.flatMap { [$0.id] + $0.parentPosts.map { $0.id } }
        
        
        // First do same as first fetch
        let nrPostLeafs = self.renderLeafs(nrPosts, onScreenSeen: onScreenSeen)
        
        
        // Then remove everything that is already on screen
        let onlyNewLeafs = nrPostLeafs.filter { !onScreenLeafIds.contains($0.id) }
        
        // Then from new replies in threads we already have, only keep the leaf and 1 parent
        let oldThreadsRemoved = onlyNewLeafs.map {
            // render thread, truncated
            let post = $0
            let truncatedPost = post
            // structure is: parentPosts: [root, reply, reply, reply, replyTo] post: ThisPost
            if let replyTo = post.parentPosts.last {
                // always keep at least 1 parent (replyTo)
                truncatedPost.parentPosts = post.parentPosts.dropLast(1).filter { !onScreenAllIds.contains($0.id) } + [replyTo]
            }
            truncatedPost.threadPostsCount = 1 + truncatedPost.parentPosts.count
            truncatedPost.isTruncated = post.parentPosts.count > truncatedPost.parentPosts.count
            return truncatedPost
        }
        
        return oldThreadsRemoved
            .sorted(by: { $0.created_at > $1.created_at })
    }
    
    var lvmCounter = LVMCounter()
    var restoreLeafs:String?
    
    var instantFeed = InstantFeed()
    
    init(pubkey:String? = nil, pubkeys:Set<String>, listId:String, name:String = "") {
        self.name = name
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        self.id = listId
        super.init()
        
        let ctx = DataProvider.shared().viewContext
        let bg = DataProvider.shared().bg
        var ls:ListState?
        if let pubkey {
            ls = ListState.fetchListState(pubkey, listId: listId, context: ctx)
        }
        else {
            ls = ListState.fetchListState(listId: listId, context: ctx)
        }
        
        if (ls == nil) {
            bg.perform { [weak self] in
                guard let self = self else { return }
                ls = ListState(context: bg)
                ls!.listId = listId
                ls!.pubkey = pubkey
                ls!.updatedAt = Date.now
                do { try bg.save() }
                catch { L.lvm.error("\(self.id) \(self.name)/\(self.pubkey?.short ?? "") could not save new listState") }
                self.listStateObjectId = ls!.objectID
            }
        }
        else {
            self.listStateObjectId = ls!.objectID
            self.lastReadId = ls!.mostRecentAppearedId
            self.lastAppearedIdSubject.send(ls!.lastAppearedId)
            self.restoreLeafs = ls!.leafs
            self.hideReplies = ls!.hideReplies
        }
        
        if (self.restoreLeafs != nil) {
//            self.restoreScrollToId = ls!.lastAppearedId
//            self.performLocalRestoreFetch()
        }
        else {
//            self.performLocalFetch()
        }
        
//        self.configureTimer()
        
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            let d = UserDefaults(suiteName: "preview_user_defaults")!
            selectedSubTab = (d.string(forKey: "selected_subtab") ?? "Unknown")
            selectedListId = (d.string(forKey: "selected_listId") ?? "Unknown")
        }
        else {
            selectedSubTab = (UserDefaults.standard.string(forKey: "selected_subtab") ?? "Unknown")
            selectedListId = (UserDefaults.standard.string(forKey: "selected_listId") ?? "Unknown")
        }
        addSubscriptions()
//        fetchFeedTimerNextTick()
     
        
        if viewIsVisible {
            startInstantFeed()
        }
    }
    
    func startInstantFeed() {
        guard !instantFinished else { return }
        let completeInstantFeed = { [weak self] events in
            guard let self = self else { return }
            self.startRenderingSubject.send(events)
            
            if (!instantFinished) {
                self.performLocalFetchAfterImport()
            }
//            fetchFeedTimerNextTick()
            instantFinished = true
        }
        if id == "Following", let pubkey {
            instantFeed.start(pubkey, onComplete: completeInstantFeed)
        }
        else {
            instantFeed.start(pubkeys, onComplete: completeInstantFeed)
        }
    }
    
    var instantFinished = false {
        didSet {
            if instantFinished {
                L.og.notice("🟪 instantFinished")
                // if nothing on screen, fetch from local
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if self.nrPostLeafs.isEmpty {
                        self.performLocalFetch()
                    }
                }
                self.configureTimer()
            }
        }
    }
    
    func configureTimer() {
        self.fetchFeedTimer?.invalidate()
        self.fetchFeedTimer = Timer.scheduledTimer(withTimeInterval: FETCH_FEED_INTERVAL, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.fetchFeedTimerNextTick()
        }
        self.fetchFeedTimer?.tolerance = 2.0
    }
    
    deinit {
        L.lvm.info("⭐️ LVM.deinit \(self.id) \(self.name)/\(self.pubkey?.short ?? "")")
        self.fetchFeedTimer?.invalidate()
    }
    
//    // FETCHES NOTHING, BUT AFTER THAT IS REALTIME FOR NEW EVENTS
//    private func wtfFetch(subscriptionId:String) {
//        guard pubkeys.count > 0 else { return }
//        let now = NTimestamp(date: Date.now)
//        req(RM.getFollowingEvents(pubkeysString: self.pubkeysPrefixString, limit:10, subscriptionId: subscriptionId, until: now))
//    }
    
    // FETCHES NOTHING, BUT AFTER THAT IS REALTIME FOR NEW EVENTS
    private func fetchRealtimeSinceNow(subscriptionId:String) {
        guard !pubkeys.isEmpty else { return }
        guard self.pubkeysPrefixString != "" else { return }
        let now = NTimestamp(date: Date.now)
        req(RM.getFollowingEvents(pubkeysString: self.pubkeysPrefixString, subscriptionId: subscriptionId, since: now), activeSubscriptionId: subscriptionId)
    }
    
    // FETCHES ALL NEW, UNTIL NOW
    private func fetchNewestUntilNow(subscriptionId:String) {
        let now = NTimestamp(date: Date.now)
        guard !pubkeys.isEmpty else { return }
        guard self.pubkeysPrefixString != "" else { return }
        req(RM.getFollowingEvents(pubkeysString: self.pubkeysPrefixString, subscriptionId: "CATCHUP-" + subscriptionId, until: now))
    }
    
    private func fetchNewerSince(subscriptionId:String, since: NTimestamp) {
        guard !pubkeys.isEmpty else { return }
        guard self.pubkeysPrefixString != "" else { return }
        req(RM.getFollowingEvents(pubkeysString: self.pubkeysPrefixString, subscriptionId: "RESUME-" + subscriptionId, since: since))
    }
    
    private func fetchNextPage() {
        guard !pubkeys.isEmpty else { return }
        guard self.pubkeysPrefixString != "" else { return }
        guard let last = self.nrPostLeafs.last else { return }
        let until = NTimestamp(date: last.createdAt)
        req(RM.getFollowingEvents(pubkeysString: self.pubkeysPrefixString,
                                  limit: 100,
                                  subscriptionId: "PAGE-" + UUID().uuidString,
                                  until: until))
    }
    
    // MARK: STEP 0: FETCH FROM RELAYS
    func fetchFeedTimerNextTick() {
        guard self.viewIsVisible else {
//            print("🏎️🏎️ NOT VISIBLE \(self.subscriptionId)")
            return
        }
        let isImporting = DataProvider.shared().bg.performAndWait {
            return Importer.shared.isImporting
        }
        guard !isImporting else { L.lvm.info("\(self.id) \(self.name) ⏳ Still importing, new fetch skipped."); return }
        
        if !UserDefaults.standard.bool(forKey: "firstTimeCompleted") {
            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: "firstTimeCompleted")
            }
        }
        
        fetchRealtimeSinceNow(subscriptionId: self.id) // Subscription should stay active
        
        if nrPostLeafs.isEmpty { // Nothing on screen
            // Dont need anymore because InstantFeed()?:
//            fetchNewestUntilNow(subscriptionId: self.id) // This one closes after EOSE
//            fetchProfiles(pubkeys: self.pubkeys, subscriptionId: "Profiles")
        }
        else { // Already on screen, app probably returned from from background
            // Catch up?
            let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 4)  // 4 hours  ago

            // Continue from first (newest) on screen?
            let since = (self.nrPostLeafs.first?.created_at ?? hoursAgo) - (60 * 5) // (take 5 minutes earlier to not mis out of sync posts)
            let ago = Date(timeIntervalSince1970: Double(since)).agoString

            DispatchQueue.main.async {
                if (!self.didCatchup) {
                    // THIS ONE IS TO CATCH UP, WILL CLOSE AFTER EOSE:
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(8)) { [weak self] in
                        guard let self = self else { return }
                        self.fetchNewerSince(subscriptionId: "\(self.id)-\(ago)", since:NTimestamp(timestamp: Int(since))) // This one closes after EOSE
                        fetchProfiles(pubkeys: self.pubkeys, subscriptionId: "Profiles")
                    }
                    self.didCatchup = true
                }
            }
        }
    }
}


extension LVM {
    
    func restoreSubscription() {
        guard instantFinished else {
            L.lvm.debug("🏎️🏎️ \(self.id) \(self.name)/\(self.pubkey?.short ?? "") instantFinished=false, not restoring subscription! \(self.selectedSubTab) and selectedListId: \(self.selectedListId)")
            return } // TODO: maybe do instant thing again if too much time in between relaunch
        self.didCatchup = false
        // Always try to restore timer
        self.configureTimer()
        
        guard viewIsVisible else {
            L.lvm.debug("🏎️🏎️ \(self.id) \(self.name)/\(self.pubkey?.short ?? "") NOT VISIBLE, NOT RESTORING. current selectedSubTab: \(self.selectedSubTab) and selectedListId: \(self.selectedListId)")
            return
        }
        
        L.lvm.info("🏎️🏎️ \(self.id) \(self.name)/\(self.pubkey?.short ?? "") restoreSubscription")
        fetchRealtimeSinceNow(subscriptionId: self.id)
        
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 4)  // 4 hours  ago

        // Continue from first (newest) on screen?
        let since = (self.nrPostLeafs.first?.created_at ?? hoursAgo) - (60 * 5) // (take 5 minutes earlier to not mis out of sync posts)
        let ago = Date(timeIntervalSince1970: Double(since)).agoString

        DispatchQueue.main.async {
            if (!self.didCatchup) {
                // THIS ONE IS TO CATCH UP, WILL CLOSE AFTER EOSE:
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(8)) { [weak self] in
                    guard let self = self else { return }
                    self.fetchNewerSince(subscriptionId: "\(self.id)-\(ago)", since:NTimestamp(timestamp: Int(since))) // This one closes after EOSE
                        fetchProfiles(pubkeys: self.pubkeys, subscriptionId: "Profiles")
                    L.lvm.info("🏎️🏎️ \(self.id) \(self.name)/\(self.pubkey?.short ?? "") restoreSubscription + 8 seconds fetchNewerSince()")
                }
                self.didCatchup = true
            }
        }
    }
    
    func addSubscriptions() {
        keepListStateSaved()
        trackLastAppeared()
        processNewEventsInBg()
        keepFilteringMuted()
        showOwnNewPostsImmediately()
        trackPubkeysChanged()
        renderFromLocalIfWeHaveNothingNewAndScreenIsEmpty()
        trackTabVisibility()
        loadMoreWhenNearBottom()
        throttledCommands()
        fetchCountsForVisibleIndexPaths()
        fetchNIP05ForVisibleIndexPaths()
    }
    
    func fetchNIP05ForVisibleIndexPaths() {
        postsAppearedSubject
            .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] nrPostIds in
                guard let self = self else { return }
                
                DataProvider.shared().bg.perform { [weak self] in
                    guard let self = self else { return }
                    let contacts = self.nrPostLeafs
                        .filter { nrPostIds.contains($0.id) }
                        .compactMap {
                            if $0.isRepost {
                                return $0.firstQuote?.event.contact
                            }
                            return $0.event.contact
                        }
                        .filter { $0.nip05 != nil && !$0.nip05veried }
                    
                    guard !contacts.isEmpty else { return }
                    
                    L.fetching.info("☑️ Checking nip05 for \(contacts.count) contacts")
                    for contact in contacts {
                        EventRelationsQueue.shared.addAwaitingContact(contact)
                        NIP05Verifier.shared.verify(contact)
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    func fetchCountsForVisibleIndexPaths() {
        postsAppearedSubject
            .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] nrPostIds in
                guard let self = self else { return }
                guard SettingsStore.shared.fetchCounts else { return }
                
                let events = self.nrPostLeafs
                    .filter { nrPostIds.contains($0.id) }
                    .compactMap {
                        if $0.isRepost {
                            return $0.firstQuote?.event
                        }
                        return $0.event
                    }
                
                guard !events.isEmpty else { return }
                
                DataProvider.shared().bg.perform {
                    for event in events {
                        EventRelationsQueue.shared.addAwaitingEvent(event)
                    }
                    let eventIds = events.map { $0.id }
                    L.fetching.info("🔢 Fetching counts for \(eventIds.count) posts")
                    fetchStuffForLastAddedNotes(ids: eventIds)
                }
                
            
            }
            .store(in: &subscriptions)
    }
    
    func throttledCommands() {
        throttledCommand
            .throttle(for: .seconds(1.5), scheduler: RunLoop.main, latest: true)
            .sink { command in
                L.lvm.info("🪡🪡 Running throttled command")
                command()
            }
            .store(in: &subscriptions)
    }
    
    func trackTabVisibility() {
        // Listen for changes on user setting:
        NotificationCenter.default
                .publisher(for: UserDefaults.didChangeNotification)
                .compactMap { _ in UserDefaults.standard.string(forKey: "selected_subtab") }
                .assign(to: \.selectedSubTab, on: self)
                .store(in: &subscriptions)
        
        NotificationCenter.default
                .publisher(for: UserDefaults.didChangeNotification)
                .compactMap { _ in UserDefaults.standard.string(forKey: "selected_listId") }
                .assign(to: \.selectedListId, on: self)
                .store(in: &subscriptions)
    }
    
    func performLocalFetchAfterImport() {
        receiveNotification(.newEventsInDatabase)
            .throttle(for: .seconds(2.5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                guard let self = self else { return }
                guard instantFinished else { return }
                L.lvm.info("\(self.id) \(self.name)/\(self.pubkey?.short ?? "") performLocalFetchAfterImport \(self.uuid)")
                self.performLocalFetch()
            }
            .store(in: &subscriptions)
    }
    
    func renderFromLocalIfWeHaveNothingNewAndScreenIsEmpty() {
        receiveNotification(.noNewEventsInDatabase)
            .throttle(for: .seconds(2.5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                guard let self = self else { return }
                guard self.viewIsVisible else { return }
                guard self.nrPostLeafs.isEmpty else { return }
                L.lvm.info("\(self.id) \(self.name)/\(self.pubkey?.short ?? "") renderFromLocalIfWeHaveNothingNew")
                self.performLocalFetch()
            }
            .store(in: &subscriptions)
    }
    
    func trackPubkeysChanged() {
        receiveNotification(.followersChanged)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard self.id == "Following" else { return }
                SocketPool.shared.allowNewFollowingSubscriptions()
                let pubkeys = notification.object as! Set<String>
                self.pubkeys = pubkeys
                self.performLocalFetch(refreshInBackground: true)
            }
            .store(in: &subscriptions)
        
        receiveNotification(.explorePubkeysChanged)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard self.id == "Explore" else { return }
                let pubkeys = notification.object as! Set<String>
                self.pubkeys = pubkeys
                self.performLocalFetch()
            }
            .store(in: &subscriptions)
        
        receiveNotification(.listPubkeysChanged)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let newPubkeyInfo = notification.object as! NewPubkeysForList
                guard newPubkeyInfo.subscriptionId == self.id else { return }
                L.og.info("LVM .listPubkeysChanged \(self.pubkeys.count) -> \(newPubkeyInfo.pubkeys.count)")
                self.pubkeys = newPubkeyInfo.pubkeys
                instantFinished = false
                nrPostLeafs = []
                leafIdsOnScreen = []
                leafsAndParentIdsOnScreen = []
                startInstantFeed()
            }
            .store(in: &subscriptions)
        
    }
    
    func showOwnNewPostsImmediately() {
        receiveNotification(.newPostSaved)
            .sink { [weak self] notification in
                guard self?.id == "Following" else { return }
                let event = notification.object as! Event
                
                let context = DataProvider.shared().bg
                context.perform { [weak self] in
                    guard let self = self else { return }
                    EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "LVM.showOwnNewPostsImmediately")
                    let newNRPostLeaf = NRPost(event: event, withParents: true, withRepliesCount: true)
                    DispatchQueue.main.async {
                        self.nrPostLeafs.insert(newNRPostLeaf, at: 0)
                        self.lvmCounter.count = self.isAtTop && SettingsStore.shared.autoScroll ? 0 : (self.lvmCounter.count + 1)
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    func keepFilteringMuted() {
        receiveNotification(.muteListUpdated)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.nrPostLeafs = self.nrPostLeafs.filter(notMuted)
            }
            .store(in: &subscriptions)
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let blockedPubkeys = notification.object as! [String]
                self.nrPostLeafs = self.nrPostLeafs.filter({ !blockedPubkeys.contains($0.pubkey) })
            }
            .store(in: &subscriptions)
        
        receiveNotification(.mutedWordsChanged)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let words = notification.object as! [String]
                self.nrPostLeafs = self.nrPostLeafs.filter { notMutedWords(in: $0.event.noteText, mutedWords: words) }
            }
            .store(in: &subscriptions)
    }
    
    func processNewEventsInBg() {
        startRenderingSubject
           .removeDuplicates()
           .sink { [weak self] posts in
               self?.processPostsInBackground(posts)
           }
           .store(in: &subscriptions)
        
        startRenderingOlderSubject
           .removeDuplicates()
           .receive(on: RunLoop.main)
           .sink { [weak self] posts in
               self?.processPostsInBackground(posts, older: true)
           }
           .store(in: &subscriptions)
    }
        
    func trackLastAppeared() {
        lastAppearedIdSubject
//            .throttle(for: 0.05, scheduler: RunLoop.main, latest: false)
            .compactMap { $0 }
            .sink { [weak self] eventId in
                guard let self = self else { return }
                guard self.lastAppearedIndex != nil else { return }
                guard !self.nrPostLeafs.isEmpty else { return }
                
//                print("COUNTER . new lastAppearedId. Index is: \(self.lastAppearedIndex) ")

                
                // unread should only go down, not up
                // only way to go up is when new posts are added.
                if self.itemsAfterLastAppeared < self.lvmCounter.count {
//                if self.itemsAfterLastAppeared != 0 && self.itemsAfterLastAppeared < self.lvmCounter.count {
//                    print("COUNTER A: \(self.lvmCounter.count)")
                    self.lvmCounter.count = self.itemsAfterLastAppeared
//                    print("COUNTER AA: \(self.lvmCounter.count)")
                    self.lastReadId = eventId
                }
                else if self.lastReadId == nil {
                    self.lastReadId = eventId
                }
                
                // Put onScreenSeen, so when when a new leaf for a long thread is inserted at top, it won't show all the parents you already seen again
                DataProvider.shared().bg.perform { [weak self] in
                    guard let self = self else { return }
                    self.onScreenSeen.insert(eventId)
                }
            }
            .store(in: &subscriptions)
    }
    
    func loadMoreWhenNearBottom() {
        lastAppearedIdSubject
//            .throttle(for: 0.05, scheduler: RunLoop.main, latest: false)
            .compactMap { $0 }
            .sink { [weak self] eventId in
                guard let self = self else { return }
                guard let lastAppeareadIndex = self.lastAppearedIndex else { return }
                guard !self.nrPostLeafs.isEmpty else { return }
                
                if lastAppeareadIndex > (self.nrPostLeafs.count-15) {
                    L.lvm.info("📖 Appeared: \(lastAppeareadIndex)/\(self.nrPostLeafs.count) - loading more from local")
                    self.performLocalOlderFetch()
                }
            }
            .store(in: &subscriptions)
    }
    
    // 1 2 3 [4] 5 6 7 8 9 10
    // 0 1 2 [3] 4 5 6 7 8 9
    // Old version, without threads
//    var itemsAfterLastAppeared:Int {
//        guard let lastAppearedIndex = self.lastAppearedIndex else { return self.nrPosts.count }
//        return max(0,((self.nrPosts.count - lastAppearedIndex) - 1))
//    }
    
    // With threads. cannot simply count, need to use the thread count value
    var itemsAfterLastAppeared:Int {
        guard let lastAppearedIndex = self.lastAppearedIndex else {
            return 0
        }
        let postsAfterLastAppeared = self.nrPostLeafs.prefix(lastAppearedIndex)
        let count = threadCount(Array(postsAfterLastAppeared))
        return max(0,count) // cant go negative
    }
    
    var itemsAfterLastRead:Int {
        guard let lastReadIndex = self.lastReadIdIndex else {
            return 0
        }
        let postsAfterLastRead = self.nrPostLeafs.prefix(lastReadIndex)
        let count = threadCount(Array(postsAfterLastRead))
        return max(0,count) // cant go negative
    }
    
    func keepListStateSaved() {
        lastAppearedIdSubject
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: false)
        //            .debounce(for: .seconds(1), scheduler: DispatchQueue.global())
        //            .throttle(for: .seconds(5), scheduler: DispatchQueue.global(), latest: false)
//            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.saveListState()
            }
            .store(in: &subscriptions)
    }
    
    func saveListState() {
        let context = DataProvider.shared().bg
        let lastAppearedId = self.lastAppearedIdSubject.value
        let lastReadId = self.lastReadId
        let leafs = self.nrPostLeafs.map { $0.id }.joined(separator: ",")
        context.perform { [weak self] in
            guard let self = self else { return }
            guard let listStateObjectId = self.listStateObjectId else { return }
            guard let listState = context.object(with: listStateObjectId) as? ListState else { return }
            listState.lastAppearedId = lastAppearedId
            listState.mostRecentAppearedId = lastReadId
            listState.updatedAt = Date.now
            listState.leafs = leafs
            listState.hideReplies = hideReplies
            L.lvm.debug("\(self.id) \(self.name)/\(self.pubkey?.short ?? "") saveListState. lastAppearedId: \(lastAppearedId?.description.prefix(11) ?? "??") (index: \(self.lastAppearedIndex?.description ?? "??"))")
            do {
                try context.save()
            }
            catch {
                L.lvm.error("🔴🔴 \(self.id) \(self.name)/\(self.pubkey?.short ?? "") Error saving list state \(self.id) \(listState.pubkey ?? "")")
            }
        }
    }
}

extension LVM {
    
    // MARK: FROM DB TO SCREEN STEP 1: FETCH REQUEST
    func performLocalFetch(refreshInBackground:Bool = false) {
        let mostRecentEvent:Event? = self.nrPostLeafs.first?.event
        let visibleOrInRefreshInBackground = self.viewIsVisible || refreshInBackground
        guard visibleOrInRefreshInBackground else {
            L.lvm.debug("\(self.id) \(self.name)/\(self.pubkey?.short ?? "") performLocalFetch cancelled - view is not visible")
            return
        }
        let ctx = DataProvider.shared().bg
        let lastCreatedAt = self.nrPostLeafs.last?.created_at ?? 0 // SHOULD CHECK ONLY LEAFS BECAUSE ROOTS CAN BE VERY OLD
        ctx.perform { [weak self] in
            guard let self = self else { return }
            L.lvm.info("🏎️🏎️ \(self.id) \(self.name)/\(self.pubkey?.short ?? "") performLocalFetch LVM.id (\(self.uuid)")
            if let mostRecentEvent = mostRecentEvent {
                //            print("🟢🟢🟢🟢🟢🟢 from mostRecent \(mostRecent.id)")
                let fr = Event.postsByPubkeys(self.pubkeys, mostRecent: mostRecentEvent, hideReplies: self.hideReplies)
                
                
                guard let posts = try? ctx.fetch(fr) else { return }
                self.setUnorderedEvents(events: self.filterMutedWords(posts), lastCreatedAt:lastCreatedAt)
            }
            else {
//                print("🟢🟢🟢🟢🟢🟢 from lastAppearedCreatedAt \(self.lastAppeared?.created_at ?? 0)")
                let fr = Event.postsByPubkeys(self.pubkeys, lastAppearedCreatedAt: self.lastAppearedCreatedAt ?? 0, hideReplies: self.hideReplies)

                guard let posts = try? ctx.fetch(fr) else { return }
                self.setUnorderedEvents(events: self.filterMutedWords(posts), lastCreatedAt:lastCreatedAt)
            }
        }
    }
    
//    func performLocalRestoreFetch(refreshInBackground:Bool = false) {
//        let ctx = DataProvider.shared().bg
//        ctx.perform { [weak self] in
//            guard let self = self else { return }
//            if let leafs = self.restoreLeafs?.split(separator: ",") {
//                let fr = Event.fetchRequest()
//                fr.predicate = NSPredicate(format: "id IN %@", leafs)
//                if let events = try? ctx.fetch(fr) {
//
//
//                    let restoredPosts = leafs
//                        .compactMap({ leafId in
//                            return events.first { event in
//                                return event.id == leafId
//                            }
//                        })
//                        .map {
//                            $0.parentEvents = Event.getParentEvents($0)
//                            return $0
//                        }
//
//                    // don't load too many:
//                    // if restored posts > MAX.
//                    // and lastAppearedIndex < MAX-20 (so we can scroll at least 20 more back)
//                    // example 500 (RESTORED) > 250 (MAX), 77 (LAST APPEARED) < 230 (MAX - 20)
//                    // Then remove all after 250 (RESTORED.prefix(250))
//                    if restoredPosts.count > LVM_MAX_VISIBLE, let lastAppearedIndex = restoredPosts.firstIndex(where: { $0.id == self.lastAppearedIdSubject.value }), lastAppearedIndex < (LVM_MAX_VISIBLE-20)  {
////                        DispatchQueue.main.async {
////                            self.state = .AWAITING_RESTORE_SCROLL
////                        }
//                        self.startRenderingSubject.send(Array(restoredPosts.prefix(250)))
//                    }
//                    else {
////                        DispatchQueue.main.async {
////                            self.state = .AWAITING_RESTORE_SCROLL
////                        }
//                        self.startRenderingSubject.send(restoredPosts)
//                    }
//                }
//                self.performLocalFetch()
//            }
//            else {
//                self.performLocalFetch()
//            }
//        }
//    }
    
    
    func performLocalOlderFetch() {
        guard !performingLocalOlderFetch else { // Data race in Nostur.LVM.performingLocalOlderFetch.setter : Swift.Bool at 0x114481300
            L.og.debug("Already performingLocalOlderFetch, cancelled")
            // reset in 2 seconds just in case
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.performingLocalOlderFetch {
                    self.performingLocalOlderFetch = false
                }
            }
            return
        }
//        guard let oldestEvent = self.nrPostLeafs.last?.event else { L.og.debug("Empty screen, cancelled") ;return } // bug: sometimes last is not oldest (delayed receive?, slow relay?), so don't take last but actual oldest on screen:
        
        // Actual oldest:
        guard let oldestEvent = self.nrPostLeafs.max(by: { $0.createdAt > $1.createdAt })?.event else {
            L.og.debug("Empty screen, cancelled") ;return
        }
        
        performingLocalOlderFetch = true
        let ctx = DataProvider.shared().bg
        ctx.perform { [weak self] in
            guard let self = self else { return }
            L.lvm.info("🏎️🏎️ \(self.id) \(self.name)/\(self.pubkey?.short ?? "") performLocalOlderFetch LVM.id (\(self.uuid)")
            let fr = Event.postsByPubkeys(self.pubkeys, until: oldestEvent, hideReplies: self.hideReplies)
            guard let posts = try? ctx.fetch(fr) else {
                DispatchQueue.main.async {
                    self.performingLocalOlderFetch = false
                }
                return
            }
            self.setOlderEvents(events: self.filterMutedWords(posts))
        }
    }
    
    var lastAppearedCreatedAt:Int64? {
        guard let lastAppearedId = self.lastAppearedIdSubject.value else { return nil }
        return nrPostLeafs.first(where: { $0.id == lastAppearedId })?.created_at
    }
    
    func filterMutedWords(_ events:[Event]) -> [Event] {
        guard !NosturState.shared.mutedWords.isEmpty else { return events }
        return events
            .filter {
                notMutedWords(in: $0.noteText, mutedWords: NosturState.shared.mutedWords)
            }
    }
    
    // MARK: FROM DB TO SCREEN STEP 2: FIRST FILTER PASS, GETTING PARENTS AND LIMIT, NOT ON SCREEN YET
    func setUnorderedEvents(events:[Event], lastCreatedAt:Int64 = 0) {

        var newUnrenderedEvents:[Event]
        
        switch (self.state) {
            case .INIT: // Show last X (FORCED CUTOFF)
                newUnrenderedEvents = events.filter(onlyRootOrReplyingToFollower)
                    .prefix(LVM_MAX_VISIBLE)
                    .map {
                        $0.parentEvents = hideReplies ? [] : Event.getParentEvents($0, fixRelations: true)
                        _ = $0.replyTo__
                        return $0
                    }
                let newEventIds = getAllEventIds(newUnrenderedEvents)
                let newCount = newEventIds.subtracting(leafsAndParentIdsOnScreen).count
                if newCount > 0 {
                    self.startRenderingSubject.send(newUnrenderedEvents)
                }
                
            default:
                newUnrenderedEvents = events
                    .filter { $0.created_at > lastCreatedAt } // skip all older than first on screen (check LEAFS only)
                    .filter(onlyRootOrReplyingToFollower)
                    .map {
                        $0.parentEvents = hideReplies ? [] : Event.getParentEvents($0, fixRelations: true)
                        _ = $0.replyTo__
                        return $0
                    }

                let newEventIds = getAllEventIds(newUnrenderedEvents)
                let newCount = newEventIds.subtracting(leafsAndParentIdsOnScreen).count
                if newCount > 0 {
                    self.startRenderingSubject.send(newUnrenderedEvents)
                }
                
                return
        }
    }
    
    
    
    func setOlderEvents(events:[Event]) {
        
        var newUnrenderedEvents:[Event]
        
        newUnrenderedEvents = events
            .filter(onlyRootOrReplyingToFollower)
            .map {
                $0.parentEvents = Event.getParentEvents($0, fixRelations: true)
                return $0
            }

        let newEventIds = getAllEventIds(newUnrenderedEvents)
        let newCount = newEventIds.subtracting(leafsAndParentIdsOnScreen).count
        if newCount > 0 {
            self.startRenderingOlderSubject.send(newUnrenderedEvents)
        }
        else {
            DispatchQueue.main.async {
                self.performingLocalOlderFetch = false
            }
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

func notMutedWords(in text: String, mutedWords: [String]) -> Bool {
    return mutedWords.first(where: { text.localizedCaseInsensitiveContains($0) }) == nil
}

func notMuted(_ nrPost:NRPost) -> Bool {
    let mutedRootIds = NosturState.shared.account?.mutedRootIds_ ?? []
    return !mutedRootIds.contains(nrPost.id) && !mutedRootIds.contains(nrPost.replyToRootId ?? "NIL")
}

extension Event {
    
    static func postsByPubkeys(_ pubkeys:Set<String>, mostRecent:Event, hideReplies:Bool = false) -> NSFetchRequest<Event> {
        let cutOffPoint = mostRecent.created_at - (15 * 60)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = 15
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN {1,6,9802,30023} AND replyToId == nil AND flags != \"is_update\"", cutOffPoint,  pubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN {1,6,9802,30023} AND flags != \"is_update\"", cutOffPoint,  pubkeys)
        }
        return fr
    }
    
    
    static func postsByPubkeys(_ pubkeys:Set<String>, until:Event, hideReplies:Bool = false) -> NSFetchRequest<Event> {
        let cutOffPoint = until.created_at + (1 * 60)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = 15
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN {1,6,9802,30023} AND replyToId == nil AND flags != \"is_update\"", cutOffPoint,  pubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN {1,6,9802,30023} AND flags != \"is_update\"", cutOffPoint,  pubkeys)
        }
        return fr
    }
    
    static func postsByPubkeys(_ pubkeys:Set<String>, lastAppearedCreatedAt:Int64 = 0, hideReplies:Bool = false) -> NSFetchRequest<Event> {
        
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8) // 8 hours ago
        
        // Take oldest timestamp: 8 hours ago OR lastAppearedCreatedAt
        // if we don't have lastAppearedCreatedAt. Take 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo)
        
        // get 15 events before lastAppearedCreatedAt (or 8 hours ago, if we dont have it)
        let frBefore = Event.fetchRequest()
        frBefore.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        frBefore.fetchLimit = 15
        if hideReplies {
            frBefore.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN {1,6,9802,30023} AND replyToId == nil AND flags != \"is_update\"", cutOffPoint,  pubkeys)
        }
        else {
            frBefore.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN {1,6,9802,30023} AND flags != \"is_update\"", cutOffPoint,  pubkeys)
        }
        
        let ctx = DataProvider.shared().bg
        let newFirstEvent = ctx.performAndWait {
            return try? ctx.fetch(frBefore).last
        }
        
        let newCutOffPoint = newFirstEvent != nil ? newFirstEvent!.created_at : cutOffPoint
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = 15
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN {1,6,9802,30023} AND replyToId == nil AND flags != \"is_update\"", newCutOffPoint,  pubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN {1,6,9802,30023} AND flags != \"is_update\"", newCutOffPoint,  pubkeys)
        }
        return fr
    }
}

func threadCount(_ nrPosts:[NRPost]) -> Int {
    nrPosts.reduce(0) { partialResult, nrPost in
        (partialResult + nrPost.threadPostsCount)
    }
}

struct NewPubkeysForList {
    var subscriptionId:String
    var pubkeys:Set<String>
}
