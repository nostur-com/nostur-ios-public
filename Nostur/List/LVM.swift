//
//  ListViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import Foundation
import CoreData
import Combine

let LVM_MAX_VISIBLE = 150 // Will only be ignored if last appeared is older


class LVMState: ObservableObject {
    let privateContext:NSManagedObjectContext
    let transformer:VPostTransformer
    
    @Published var viewIsVisible = true
    @Published var restoreScrollTo:Event? = nil // @TODO: Maybe doesn't need to be @Published?
    @Published var restoreScrollToAnchor = "BOTTOM"  // @TODO: Maybe doesn't need to be @Published?
    @Published var events:[Event] = [] // events.count and vPosts.count should be equal! So .prefix BEFORE setting events, not after. (For unreadIndex etc)
    @Published var vPosts:[VPost] = [] // events.count and vPosts.count should be equal! So .prefix BEFORE setting events, not after. (For unreadIndex etc)
    @Published var state:LVM.LIST_STATE = .AWAITING_FIRST_FETCH {
        didSet {
            ThreadWarning.which("STATE: \(oldValue) -> \(state) ---  vPosts: \(vPosts.count) visible: \(viewIsVisible)")
        }
    }
    
    var subscriptions = Set<AnyCancellable>()
    
    init(privateContext:NSManagedObjectContext) {
        
        self.privateContext = privateContext
        self.transformer = VPostTransformer(privateContext)
        
        let firstEvent = $events
            .first()
            .eraseToAnyPublisher()
        
        let throttledLatestEvent = $events
            .throttle(for: .seconds(5), scheduler: DispatchQueue.main, latest: true)
            .dropFirst() // Drop the initial event that will be emitted by the firstEvent publisher
            .eraseToAnyPublisher()
        
        let combined = Publishers.Merge(firstEvent, throttledLatestEvent)

        combined
            .sink { posts in
                self.processPostsInBackground(posts)
            }
            .store(in: &subscriptions)
        

    }
    
    private func processPostsInBackground(_ events:[Event]) {
        privateContext.perform { [unowned self] in
            
            var currentVPosts = self.vPosts
            var newVPosts:[VPost] = []
            
            for event in events {
                guard let privateEvent = try? privateContext.existingObject(with: event.objectID) as? Event else { continue }
                
                if let existingVPostIndex = currentVPosts.firstIndex(where: { $0.id == privateEvent.id } ) {
                    let newVPostData = self.transformer.vPostData(privateEvent)
                    currentVPosts[existingVPostIndex].plainText = newVPostData.plainText
                    currentVPosts[existingVPostIndex].renderedText = newVPostData.renderedText
                    currentVPosts[existingVPostIndex].replyingToUsernamesMarkDown = newVPostData.replyingToUsernamesMarkDown
                    currentVPosts[existingVPostIndex].imageUrls = newVPostData.imageUrls
                    currentVPosts[existingVPostIndex].displayName = newVPostData.displayName
                }
                else {
                    let newVPostData = self.transformer.vPostData(privateEvent) // need to get event from bg instead?
                    let newVPost = VPost(
                        id: privateEvent.id,
                        event: event, // Main context event here? not privateEvent, right?
                        created_at: privateEvent.created_at,
                        npub: newVPostData.npub,
                        note1: newVPostData.note1,
                        plainText: newVPostData.plainText,
                        renderedText: newVPostData.renderedText,
                        imageUrls: newVPostData.imageUrls,
                        displayName: newVPostData.displayName)
                    newVPosts.append(newVPost)
                }
            }
            
            // newVPosts also has has items from BEFORE, that were removed with .prefix. from vPosts so handle it again
            let last = newVPosts
            // post added to the end should not be older than the first one already on screen...
                .filter { $0.created_at > (currentVPosts.first?.created_at ?? 0) }
                .suffix(LVM_MAX_VISIBLE)
        
            DispatchQueue.main.async {
                self.vPosts = currentVPosts + last
            }
            
            
//            var updatedPosts: [VPost] = []
//
//                    for event in events {
//                        // Get the corresponding post in the private context
//                        guard let privateEvent = try? privateContext.existingObject(with: event.objectID) as? Event,
//                              let plainText = privatePost.plainText else { continue }
//                        let processedText = parseText(plainText)
//                        // Update the post object with the processed text
//                        privatePost.content = processedText
//                        updatedPosts.append(privatePost)
//                    }
//
//                    DispatchQueue.main.async {
//                        self.processedPosts = updatedPosts
//                    }
//            
//            guard let privatePost = try? privateContext.existingObject(with: post.objectID) as? Post,
//                              let plainText = privatePost.plainText else { continue }
//            let newPosts = posts
////                            .sorted(by: { $0.created_at < $1.created_at } ) //make lastIndex newest
//                .map(VPostTransformer.shared.toVPost)
//            let result = updatePosts(postsOnScreen: self.vPosts, postsFromCoreData: newPosts)
//            DispatchQueue.main.async {
//                self.vPosts = result.updatedPosts
//            }
//            if (result.newPostsCount > 0 || result.updatedPostsCount > 0) {
//                ThreadWarning.which("self.vPosts.append() Added \(result.newPostsCount) new and replaced \(result.updatedPostsCount) on (self.id)")
////                    self.updateUnreadCount()
//            }
        }
    }
}

//@MainActor
class LVM: NSObject, ObservableObject {
    let ot:OnboardingTracker = .shared
    
    let FETCH_FEED_INTERVAL = 3.0
    var listStateObjectId:NSManagedObjectID?
    var pubkey:String
    var pubkeys:Set<String>
    private let viewContext: NSManagedObjectContext

    var unreadCount:Int {
        get { lvmCounter.unreadCount }
        set { lvmCounter.unreadCount = newValue }
    }
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
    
    var previousLastAppearedEvent:Event?
    
    var listId:String
    var id:String { listId }
    
    var contentChangedSubject = CurrentValueSubject<[Event], Never>([]) // Need it for debounce etc
    var lastAppearedSubject = CurrentValueSubject<Event?, Never>(nil) // Need it for debounce etc
    var lastAppeared:Event? {
        get { lastAppearedSubject.value }
        set { lastAppearedSubject.send(newValue) }
    }
    var lastAppearedId:String? // so we dont have to fetch from different context by objectId if we want to save ListState in background
    var lastAppearedAnchor = "BOTTOM"
    var mostRecentRead:Event? {
        didSet {
            mostRecentReadId = mostRecentRead?.id
        }
    }
    var mostRecentReadId:String? // so we dont have to fetch from different context by objectId if we want to save ListState in background
    var lastAppearedIndex:Int { lastAppeared != nil ? lvmState.events.firstIndex(of: lastAppeared!) ?? -1 : -1 }
    var mostRecentReadIndex:Int { mostRecentRead != nil ? lvmState.events.firstIndex(of: mostRecentRead!) ?? -1 : -1 }
    private var subscriptions = Set<AnyCancellable>()
    
    var lvmState:LVMState
    var lvmCounter = LVMCounter()
    
    let privateContext:NSManagedObjectContext
    
    init(pubkey:String, pubkeys:Set<String>, listId:String) {
        self.viewContext = DataProvider.shared().viewContext
        self.privateContext = DataProvider.shared().bg
        self.lvmState = LVMState(privateContext: self.privateContext)
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        self.listId = listId
        super.init()
        
        let ctx = viewContext
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
        
        let mostRecent = ls!.mostRecentAppearedId != nil
            ? (try? Event.fetchEvent(id: ls!.mostRecentAppearedId!, context: ctx))
            : nil
        
        self.listStateObjectId = ls!.objectID
        self.mostRecentRead = mostRecent
        self.lastAppeared = lastAppeared
        if (lastAppeared != nil) {
            self.lvmState.state = .AWAITING_RESTORED_FETCH
            self.lvmState.restoreScrollTo = self.lastAppeared
            self.lvmState.restoreScrollToAnchor = ls?.lastAppearedAtAnchor ?? "BOTTOM"
            print("🟢🟢 lastAppeared.id on init: \(self.lastAppeared?.id ?? "")")
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
        self.lvmState.vPosts = []

        self.pubkey = pubkey
        self.pubkeys = pubkeys
        self.listId = listId
        
        let ctx = viewContext
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
        
        let mostRecent = ls!.mostRecentAppearedId != nil
            ? (try? Event.fetchEvent(id: ls!.mostRecentAppearedId!, context: ctx))
            : nil
        
        self.listStateObjectId = ls!.objectID
        self.mostRecentRead = mostRecent
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
        performFetch()
    }
    
    func fetchFeedTimerNextTick() {
        guard self.viewIsVisible else { return }
        guard !Importer.shared.isImporting else { print("⏳ Still importing, new fetch skipped."); return }
        
        if (ot.isOnboarding && self.pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
            fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
            ot.didFillTimeline = true
//            firstTimeCompleted = true
            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: "firstTimeCompleted")
            }
        }
        else if (!ot.isOnboarding) {
            let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 4)  // 4 hours  ago
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
            DispatchQueue.main.async {
                let cutOffPoint = min(self.lastAppeared?.created_at ?? hoursAgo, hoursAgo) // 8 hours ago or longer until lastAppeared Event
                fetchEvents(pubkeys: self.pubkeys, since: cutOffPoint, subscriptionId: self.id)
            }
        }
    }
    
    func performFetch() {
        self.frc = NSFetchedResultsController(fetchRequest: Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: self.lastAppeared?.created_at ?? 0), managedObjectContext: viewContext, sectionNameKeyPath: nil, cacheName: nil) // TODO: Try cache?
        frc?.delegate = self
    
        
        if viewIsVisible {
            do {
                try self.frc?.performFetch()
                guard let posts = self.frc?.fetchedObjects else { return }
                self.contentChangedSubject.send(posts)
            } catch {
                print("🔴🔴🔴 failed to fetch items")
            }
        }
    }
}


extension LVM {
    func addSubscriptions() {
        keepListStateSaved()
        requestFooterCounters()
//        onlyFetchItemsWhenVisible()
        updatePostFeed()
    }
    
    func updatePostFeed() {
        contentChangedSubject
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .throttle(for: .seconds(4), scheduler: RunLoop.main, latest: true)
//            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.global())
//            .throttle(for: .seconds(4), scheduler: DispatchQueue.global(), latest: false)
            .sink { events in
                self.sendToView(events: events)
            }
            .store(in: &subscriptions)
    }
    
//    func onlyFetchItemsWhenVisible() {
//        lvmState.$viewIsVisible
//            .removeDuplicates() // Dont trigger if the visibility is updated but the same.. (double set by different views/subviews
//            .sink { isVisible in
//                print("🟢🟢 \(self.id): isVisible:\(isVisible)")
//                if (isVisible) {
//                    print("🟢🟢 Activating FRC: \(self.id) 🟢🟢")
//                    self.frc?.delegate = self
//                    do {
//                        try self.frc?.performFetch()
//                        guard let posts = self.frc?.fetchedObjects else { return }
//                        self.contentChangedSubject.send(posts)
//                    } catch {
//                        print("🔴🔴🔴 failed to fetch items")
//                    }
//                }
//                else {
//                    print("🟢🟢 Deactivating FRC:\(self.id) 🟣🟣")
//                    self.frc?.delegate = nil
//                }
//            }
//            .store(in: &subscriptions)
//    }
    
    // can be old or new, depending on scroll back or not
    func onPostAppeared(_ event:Event) {
        // TRACK ANCHOR
        if let previous = lastAppeared {
            lastAppearedAnchor = event.created_at > previous.created_at ? "BOTTOM" : "TOP"
        }
        lastAppeared = event
        lastAppearedId = event.id // So dont need to mangle contexts if we just need an id (for saving ListState)
        print("🟢🟢 lastAppearedId set to: \(self.lastAppearedId ?? "")")
        
        // TRACK MOST RECENT READ
        if let recent = mostRecentRead, event.created_at > recent.created_at {
            mostRecentRead = event
        }
        else if mostRecentRead == nil {
            mostRecentRead = event
        }
        
        // TRACK UNREAD COUNT // TODO: NEED TO DO THIS IN BACKGROUND MAYBE? OR NOT
        if let mostRecentRead {
//            DispatchQueue.global().async {
            let mostRecentReadIndex = self.lvmState.events.map { $0.id }.firstIndex(of: mostRecentRead.id) ?? 0
            let unreadCount = max((self.lvmState.events.count - mostRecentReadIndex - 1), 0)
//                DispatchQueue.main.async {
                    self.unreadCount = unreadCount
//                }
//            }
        }
    }
    
    func keepListStateSaved() {
//        $lastAppeared
        lastAppearedSubject
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: false)
//            .debounce(for: .seconds(1), scheduler: DispatchQueue.global())
//            .throttle(for: .seconds(5), scheduler: DispatchQueue.global(), latest: false)
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
//                guard self.state != .AWAITING_RESTORED_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
//                guard self.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
//                guard self.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
//                guard self.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                
                
                self.privateContext.perform {
                    guard let listStateObjectId = self.listStateObjectId else { return }
                    guard let listState = self.privateContext.object(with: listStateObjectId) as? ListState else { return }
                    listState.lastAppearedId = self.lastAppearedId
                    listState.mostRecentAppearedId = self.mostRecentReadId
                    listState.lastAppearedAtAnchor = self.lastAppearedAnchor
                    listState.updatedAt = Date.now
                    listState.unreadCount = Int64(self.unreadCount)
                    do {
                        try self.privateContext.save()
                        ThreadWarning.which("🟢🟢💾 keepListStateSaved on: \(self.id) vPosts: \(self.lvmState.events.count) visible: \(self.viewIsVisible) - lastAppeardId: \(self.lastAppearedId ?? "")")
                        
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
                self.lvmState.vPosts.count > 0 // Don't do anything if there is nothing on screen yet!
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
                    if let indexOfPost = self.lvmState.events.firstIndex(of: event) {
                        let five = [
                            self.lvmState.events[safe: indexOfPost],
                            self.lvmState.events[safe: indexOfPost - 1],
                            self.lvmState.events[safe: indexOfPost - 2],
                            self.lvmState.events[safe: indexOfPost - 3],
                            self.lvmState.events[safe: indexOfPost - 4]
                        ]
                        self.requestForJustAppeared(five.compactMap { $0 })
                    }
                }
                else {
                    // get after
                    if let indexOfPost = self.lvmState.events.firstIndex(of: event) {
                        let five = [
                            self.lvmState.events[safe: indexOfPost],
                            self.lvmState.events[safe: indexOfPost + 1],
                            self.lvmState.events[safe: indexOfPost + 2],
                            self.lvmState.events[safe: indexOfPost + 3],
                            self.lvmState.events[safe: indexOfPost + 4]
                        ]
                        self.requestForJustAppeared(five.compactMap { $0 })
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    func scrollToEnd() {
        state = .AWAITING_SCROLL
        sendNotification(.shouldScrollToLast)
        self.unreadCount = 0
        if (self.lastAppeared != self.lvmState.events.last) {
            self.lastAppeared = self.lvmState.events.last
        }
        self.privateContext.perform {
            guard let listStateObjectId = self.listStateObjectId else { return }
            guard let listState = self.privateContext.object(with: listStateObjectId) as? ListState else { return }
            listState.lastAppearedId = self.lastAppearedId
            listState.mostRecentAppearedId = self.mostRecentReadId
            listState.lastAppearedAtAnchor = "BOTTOM"
            listState.updatedAt = Date.now
            listState.unreadCount = 0
            
            // TODO: ALso implement cutoff, if 1000 posts on screen, --> .suffix 100. PROBLEM IS SCROLL OFFSET GLITCH
            do {
                try self.privateContext.save()
                ThreadWarning.which("🟢🟢💾 keepListStateSaved on: \(self.id) vPosts: \(self.lvmState.events.count) visible: \(self.viewIsVisible) - lastAppeardId: \(self.lastAppearedId ?? "")")
            }
            catch {
                print("🔴🔴 Error saving list state \(self.id) \(listState.pubkey)")
            }
        }
    }
    
    func didReachEnd() {
        guard state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
        guard state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
        guard state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we

        self.unreadCount = 0
//        sendNotification(.updateUnreadCount, self.unreadCount)
    }
    
    func updateUnreadCount() {
        let mostRecentReadIndex = self.lvmState.events.firstIndex(where: { $0.id == self.mostRecentReadId }) ?? 0
        
//        DispatchQueue.main.async {
            self.unreadCount = max((self.lvmState.events.count - mostRecentReadIndex - 1),0)
//        }
    }
    
    func requestForJustAppeared(_ events:[Event]) {
//        return // TODO: FIXME
        guard self.viewIsVisible else { return }
        let ids = ids(events)
        let contacts = events.compactMap { $0.contact }
        let shouldVerifyContacts = contacts.filter { NIP05.shouldVerify($0) }

//        Task {
            ThreadWarning.which("requestForJustAppeared on \(self.id)")
            fetchStuffForLastAddedNotes(ids: ids)
//            fetchMissingReplyToContacts(events: events) // TODO: FIXME
            NIP05.verifyBatch(contacts: shouldVerifyContacts, context: self.privateContext)
//        }
    }
    
    // TODO: WE NEED TO USE THIS.. JUST MOVED FROM ListView TO LVM but not updated yet
    func fetchMissingReplyToContacts(events:[Event]) {
        // PLAN
        // FOR EVERY EVENT
        //   TAKE P's. IF P IS NOT IN EVENT.CONTACTS, ADD IT
        // FINALLY, EVERY MISSING OR EMPTY CONTACT
        //  sp.fetch!
        
        for event in events {
            let pubkeys = Array(Set(event.pTags()))
            if pubkeys.count > 0 {
                let contacts = Contact.fetchByPubkeys(pubkeys, context: self.privateContext)
//                event.objectWillChange.send()
                // dit moet op main queue?
//                ThreadWarning.which("Event.addToContacts( 💖💖💖")
                event.addToContacts(NSSet(array: contacts))
            }
        }
        // TODO: FIXEN
        // TODO, bij importer, replyTo p in event.replyToPTag for speed up
        let pubkeys = Array(Set(events.flatMap { TagsHelpers($0.tags()).pTags().map{ $0.pubkey } }))
        let contacts = Contact.fetchByPubkeys(pubkeys, context: self.privateContext)
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

extension LVM: NSFetchedResultsControllerDelegate {
    
    func sendToView(events:[Event]) {
            switch (self.state) {
                case .AWAITING_FIRST_FETCH: // Show last X (FORCED CUTOFF)
                    self.lvmState.events = events
                        .prefix(LVM_MAX_VISIBLE)
                        .sorted(by: { $0.created_at < $1.created_at } )
                        
                    self.lvmState.state = .COMPLETED_FIRST_FETCH
                    
                case .AWAITING_RESTORED_FETCH: // Show last read, until end
                    // show last 100 if LR is within it
                    // else show all
                    let lastAppearedIndex = self.lastAppeared != nil ? self.lvmState.events.firstIndex(where: { $0.id == self.lastAppearedId }) ?? -1 : -1
                    
                    if (lastAppearedIndex == -1) { // LAST APPEARED NOT IN EVENTS (FORCED CUTOFF)
                        self.lvmState.events = events
                            .prefix(LVM_MAX_VISIBLE)
                            .sorted(by: { $0.created_at < $1.created_at } )
                            self.state = .COMPLETED_FIRST_FETCH // POST NOT IN LIST, SO DONT RESTORE SCROLL.
                    }
                    if (lastAppearedIndex < LVM_MAX_VISIBLE) {
                        self.lvmState.state = .AWAITING_RESTORE_SCROLL // POST IS IN LIST, SO WE CAN RESTORE SCROLL. (FORCED CUTOFF)
                        self.lvmState.events = events
                            .prefix(LVM_MAX_VISIBLE)
                            .sorted(by: { $0.created_at < $1.created_at } )
                    }
                    else {
                        self.lvmState.state = .AWAITING_RESTORE_SCROLL // POST IN LIST, BUT OUTSIDE MAX VISIBLE.. TODO: HANDLE THIS. NO CUTOFF NOW
                        self.lvmState.events = events
                            .sorted(by: { $0.created_at < $1.created_at } )
                    }
//                    self.updateUnreadCount()
                
                default:
                    // NEW PLAN
                    // 1. UPDATE EXISTING vPosts (changes)
                    // 2. APPEND NEW vPosts at end (new)
                    
                    // STEPS
                    // GET LAST POST ON SCREEN. (SHOULD BE NEW BUT CAN BE OLD)
                    // PUT ALL FETCHED NOT ON SCREEN AFTER LAST POST
                    // REFRESH ALL ON SCREEN IF IN FETCHED
                    // DONT PUT TOO OLD FROM FETCHED ON SCREEN AFTER LAST POST ON SCREEN
                    
                    // FROM CHATGPT 4:
                    self.lvmState.events = events
                        .sorted(by: { $0.created_at < $1.created_at } )
                    return
                    
//    //            case .COMPLETED_RESTORED_FETCH_WITH_SCROLL, .SCROLLED_TO_END, .SWITCHING_ACCOUNT:
//                    // deduplicate, add new posts (can be older also..)
//                    let onScreen = Set(self.vPosts) // lastIndex is newest
//                    let newPosts = posts
//                            .sorted(by: { $0.created_at < $1.created_at } ) //make lastIndex newest
//                            .map(self.vTransformer.eventToVPost)
//                    // not older than .first or .count - 100
//
//                    // newPosts also has has items from BEFORE, that were removed with .prefix. so handle it
//                    let last100 = newPosts.suffix(100)
//                    let notTooOldCreatedAt = last100.first?.created_at ?? 0
//                    let newListWithoutTooOld = Set(newPosts.filter { $0.created_at > notTooOldCreatedAt })
//
//                    let newListWithoutOnScreen = newListWithoutTooOld.subtracting(onScreen)
//                    let newListWithoutOnScreenSorted = newListWithoutOnScreen.sorted(by: { $0.created_at < $1.created_at } )
//                    // TODO: can we speed up, optimize above 5 lines??
//                    if (newListWithoutOnScreenSorted.count > 0) {
//                        self.vPosts.append(contentsOf: newListWithoutOnScreenSorted)
//                        ThreadWarning.which("self.vPosts.append() Added \(newListWithoutOnScreenSorted.count) new to \(self.id)")
//                        self.updateUnreadCount()
//                    }
            }
//        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let posts = controller.fetchedObjects as? [Event] else { return }
        self.contentChangedSubject.send(posts)
    }
}


extension Event {
    static func postsByPubkeys(_ pubkeys:Set<String>, lastAppearedCreatedAt:Int64 = 0) -> NSFetchRequest<Event> {
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8) // 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo) // 8 hours ago or longer until lastAppeared Event
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
//        fr.fetchLimit = 500 //TODO: need this even?
        fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", cutOffPoint,  pubkeys)
        return fr
    }
}



func updatePosts(postsOnScreen: [VPost], postsFromCoreData: [VPost], maxNewPosts: Int = 100) -> (updatedPosts: [VPost], newPostsCount: Int, updatedPostsCount: Int) {
    
    var newPostsOnScreen = postsOnScreen // first put the existing posts in our final result
    var postsAddedToTheEnd = [VPost]() // create an empty array that will hold all the things appended to the end
    var replacedCount = 0
    
    for fetchedPost in postsFromCoreData {
        // If a post from core data is on screen, get the index, and replace it
        if let index = newPostsOnScreen.firstIndex(where: { $0.id == fetchedPost.id }) {
            if newPostsOnScreen[index].hashValue != fetchedPost.hashValue {
                newPostsOnScreen[index] = fetchedPost
                replacedCount += 1
            }
        }
        else {
            postsAddedToTheEnd.append(fetchedPost)
        }
    }
    
    postsAddedToTheEnd
        .sort { $0.event.created_at < $1.event.created_at }
    
    
    // postsAddedToTheEnd also has has items from BEFORE, that were removed with .prefix. from postsOnScreen so handle it again
    let last = postsAddedToTheEnd
    // post added to the end should not be older than the first one already on screen...
        .filter { $0.event.created_at > (postsOnScreen.first?.event.created_at ?? 0) }
        .suffix(maxNewPosts)
//        .suffix(max(0,maxNewPosts - replacedCount))
//    let notTooOldCreatedAt = last100.first?.created_at ?? 0
//    let postsAddedToTheEndNotToOld = last100.filter { $0.created_at > notTooOldCreatedAt }
    
//    let numberOfNewPosts = min(postsAddedToTheEndNotToOld.count, maxNewPosts)
    newPostsOnScreen.append(contentsOf: last)
//    newPostsOnScreen.append(contentsOf: postsAddedToTheEndNotToOld.suffix(numberOfNewPosts))
    
    return (newPostsOnScreen, last.count, replacedCount)
    
//    var updatedPosts = posts
//    var newPosts = [VPost]()
//
//
//    for changedPost in changedPosts {
//        if let index = updatedPosts.firstIndex(of: changedPost) {
//            // This is an updated post
//            updatedPosts[index] = changedPost
//        } else {
//            // This is a new post
//            newPosts.append(changedPost)
//        }
//    }
//
//    // Sort the new posts by createdAt in descending order (latest first)
//    newPosts.sort { $0.created_at < $1.created_at }
//
//    // Append the latest new posts to the end of updatedPosts, limited by maxNewPosts
//    let numberOfNewPosts = min(newPosts.count, maxNewPosts)
//    updatedPosts.append(contentsOf: newPosts.prefix(numberOfNewPosts))
//
//    return (updatedPosts, numberOfNewPosts)
}
