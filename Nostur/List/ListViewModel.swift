//
//  ListViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import Foundation
import CoreData
import Combine

//@MainActor
class ListViewModel: NSObject, ObservableObject {
    let ot:OnboardingTracker = .shared
    
    let MAX_VISIBLE = 100 // Will only be ignored if last appeared is older
    let FETCH_FEED_INTERVAL = 3.0
    let listState:ListState
    let pubkey:String
    @Published var pubkeys:Set<String>
    private let context: NSManagedObjectContext
    private let bg: NSManagedObjectContext
    private let vTransformer: VTransformer
    
    @Published var vPosts = [VPost]()
    
    var posts:[Event] = [] {
        didSet {
            let vPosts = self.posts.map(self.vTransformer.eventToVPost)
            DispatchQueue.main.async {
                self.setVPosts(posts: vPosts)
            }
        }
    }
    
    func setVPosts(posts:[VPost]) {
        vPosts = posts
    }
    
    @Published var state:LIST_STATE = .AWAITING_FIRST_FETCH {
        didSet {
            print("🟢🟢 STATE: \(oldValue) -> \(state)")
        }
    }
    var frc:NSFetchedResultsController<Event>?
    
    enum LIST_STATE:String {
        // Never fetched before, no known last read
        case AWAITING_FIRST_FETCH = "AWAITING_FIRST_FETCH"
        // Should restore scroll after fetch
        case AWAITING_RESTORED_FETCH = "AWAITING_RESTORED_FETCH"
        // we fetched
        case COMPLETED_FIRST_FETCH = "COMPLETED_FIRST_FETCH"
        case AWAITING_SCROLL = "AWAITING_SCROLL"
        case COMPLETED_RESTORED_FETCH_WITH_SCROLL = "COMPLETED_RESTORED_FETCH_WITH_SCROLL"
        case SCROLLED_TO_END = "SCROLLED_TO_END"
        case SWITCHING_ACCOUNT = "SWITCHING_ACCOUNT"
    }
    
    private var fetchFeedTimer: Timer?
    
    var previousLastAppearedEvent:VPost?
    let lastAppearedSubject:CurrentValueSubject<VPost?, Never>
    let lastAppearedAnchorSubject:CurrentValueSubject<String, Never>
    let mostRecentReadSubject:CurrentValueSubject<VPost?, Never>
    let unreadCountSubject = CurrentValueSubject<Int, Never>(0)
//    let setVPostsYoo = PassthroughSubject<[VPost], Never>()
//    let transFormPostsyodd = PassthroughSubject<[Event], Never>()
    let viewIsVisibleSubject = CurrentValueSubject<Bool, Never>(false)
    let selectedSubTabSubject = CurrentValueSubject<String?, Never>(nil)
    
    private var subscriptions = Set<AnyCancellable>()
    
    var id:String { listState.listId }
    
    static func fromDB(pubkey:String, listId:String, pubkeys:Set<String>, context:NSManagedObjectContext) -> ListViewModel {
        var listState:ListState?
        
        listState = ListState.fetchListState(pubkey, listId: listId, context: context)
        
        if (listState == nil) {
            listState = ListState(context: context)
            listState!.listId = listId
            listState!.pubkey = pubkey
            listState!.updatedAt = Date.now
            do {
                try context.save()
            }
            catch {
                print("could not save new listState")
            }
        }
        
        let lastAppeared = listState!.lastAppearedId != nil
            ? (try? Event.fetchEvent(id: listState!.lastAppearedId!, context: context))
            : nil
        
        let mostRecent = listState!.mostRecentAppearedId != nil
            ? (try? Event.fetchEvent(id: listState!.mostRecentAppearedId!, context: context))
            : nil
        
        let model = ListViewModel(listState:listState!, pubkey:pubkey, pubkeys:pubkeys, context: context, lastAppeared:lastAppeared, mostRecent: mostRecent, anchor:listState!.lastAppearedAtAnchor)
        
        model.performFetch()
        return model
    }
    
    init(listState:ListState, pubkey:String, pubkeys:Set<String>, context: NSManagedObjectContext, lastAppeared:Event?, mostRecent:Event?, anchor:String) {
        self.bg = EventsProvider.shared.container.newBackgroundContext() // TODO: how Fix for Preview???
        self.bg.automaticallyMergesChangesFromParent = true
        self.bg.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.bg.undoManager = nil
        self.listState = listState
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        self.context = context
        self.previousLastAppearedEvent = lastAppeared?.toVPost(pubkey: pubkey, context: bg)
        self.lastAppearedSubject = CurrentValueSubject<VPost?, Never>(lastAppeared?.toVPost(pubkey: pubkey, context: bg))
        self.lastAppearedAnchorSubject = CurrentValueSubject<String, Never>(anchor)
        self.mostRecentReadSubject = CurrentValueSubject<VPost?, Never>(mostRecent?.toVPost(pubkey: pubkey, context: bg))
        if (lastAppeared != nil) {
            state = .AWAITING_RESTORED_FETCH
        }
        self.vTransformer = VTransformer(pubkey:pubkey, context: bg)
        self.fetchFeedTimer?.invalidate()
        super.init()
        self.fetchFeedTimer = Timer.scheduledTimer(withTimeInterval: FETCH_FEED_INTERVAL, repeats: true) { [weak self] _ in
            self?.fetchFeedTimerNextTick()
        }
        addSubscriptions()
    }
    
    func fetchFeedTimerNextTick() {
        guard self.viewIsVisible else { return }
        guard !Importer.shared.isImporting else { print("⏳ Still importing, new fetch skipped."); return }
        
        if (ot.isOnboarding && self.pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
            fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
            ot.didFillTimeline = true
//            firstTimeCompleted = true
            UserDefaults.standard.set(true, forKey: "firstTimeCompleted")
        }
        else if (!ot.isOnboarding) {
            let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 4)  // 4 hours  ago
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
            let cutOffPoint = min(self.lastAppeared?.created_at ?? hoursAgo, hoursAgo) // 8 hours ago or longer until lastAppeared Event
            fetchEvents(pubkeys: self.pubkeys, since: cutOffPoint, subscriptionId: self.id)
        }
    }
    
    func performFetch() {
        self.frc = NSFetchedResultsController(fetchRequest: Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: self.lastAppearedSubject.value?.created_at ?? 0), managedObjectContext: bg, sectionNameKeyPath: nil, cacheName: nil) // TODO: Try cache?
        frc?.delegate = self
        
            
            self.bg.perform {
                do {
                    try self.frc?.performFetch()
                    guard let posts = self.frc?.fetchedObjects else { return }
                    self.contentChanged(posts:posts)
                } catch {
                    print("🔴🔴🔴 failed to fetch items")
                }
            }
    }
}

extension ListViewModel {
    var lastAppeared:VPost? { self.lastAppearedSubject.value }
    var lastAppearedIndex:Int { lastAppeared != nil ? vPosts.firstIndex(of: lastAppeared!) ?? -1 : -1 }
    var mostRecentRead:VPost? { self.mostRecentReadSubject.value }
    var mostRecentReadIndex:Int { mostRecentRead != nil ? vPosts.firstIndex(of: mostRecentRead!) ?? -1 : -1 }
    var viewIsVisible:Bool { self.viewIsVisibleSubject.value }
}

extension ListViewModel {
    func addSubscriptions() {
        trackLastAppeared()
        trackMostRecentRead()
        keepListStateSaved()
        trackUnreadCount()
        requestFooterCounters()
        updateViewModel()
//        setVpostsYouu()
//        transFormPostsyo()
        trackSelectedSubtab()
    }
    
    func trackSelectedSubtab() {
        selectedSubTabSubject
            .sink(receiveValue: { [weak self] tab in
                guard let self = self else { return }
                self.viewIsVisibleSubject.send(tab == self.id)
            })
            .store(in: &subscriptions)

    }
    
    func updateViewModel() {
//        return
        NotificationCenter.default.publisher(for: .viewNeedsUpdate)
//            .receive(on: DispatchQueue.global())
            .sink { [weak self] notification in
                guard let self = self else { return }
//                self.objectWillChange.send()
//                self.transFormPostsyodd.send(self.posts)
                self.bg.perform {
                    let vPosts = self.posts.map(self.vTransformer.eventToVPost)
                    DispatchQueue.main.async {
                        self.setVPosts(posts: vPosts)
                    }
                }
            }
        .store(in: &subscriptions)
    }
//
//    func transFormPostsyo() {
//        transFormPostsyodd
//            .sink { [weak self] posts in
//                guard let self = self else { return }
//
//                self.bg.perform {
//                    let vPosts = self.posts.map(self.vTransformer.eventToVPost)
//                    self.setVPostsYoo.send(vPosts)
//                }
//            }
//            .store(in: &subscriptions)
//    }
//
//    func setVpostsYouu() {
//        setVPostsYoo
//            .receive(on: RunLoop.main)
//            .sink { [weak self] vPosts in
//                guard let self = self else { return }
//                self.objectWillChange.send()
//                self.vPosts = vPosts
//            }
//            .store(in: &subscriptions)
//    }
    
    
    
    
    
    // can be old or new, depending on scroll back or not
    func trackLastAppeared() {
        // STORE MOST RECENT READ EVENT
        // + TRACK IF WE RESTORED YET
        lastAppearedSubject
//            .debounce(for: .seconds(0.1), scheduler: RunLoop.current)
//            .throttle(for: .seconds(3), scheduler: RunLoop.current, latest: true)
//            .compactMap { $0 }
            .sink(receiveValue: { [weak self] post in
                guard let self = self else { return }
//                guard self.state != .AWAITING_SCROLL else { return }
                guard let post = post else { return }
                guard let previous = self.previousLastAppearedEvent else {
                    // FIRST EVENT
                    self.previousLastAppearedEvent = post
                    return
                }
                // ALL OTHER EVENTS:
//                self.objectWillChange.send()
//                print(" --->>>> \(self.lastAppearedIndex)")
                self.lastAppearedAnchorSubject.send(post.created_at > previous.created_at ? "BOTTOM" : "TOP")
            })
            .store(in: &subscriptions)
    }
    
    // .created_at is always newest
    func trackMostRecentRead() {
        lastAppearedSubject
            .sink(receiveValue: { [weak self] post in
                guard let self = self else { return }
                guard let post = post else { return }
                                
                guard post.created_at > (self.mostRecentRead?.created_at ?? 0) else { return }
                self.objectWillChange.send()
                self.mostRecentReadSubject.send(post)
            })
            .store(in: &subscriptions)
    }
    
    func keepListStateSaved() {
        lastAppearedSubject
            .debounce(for: .seconds(1), scheduler: RunLoop.current)
            .throttle(for: .seconds(5), scheduler: RunLoop.current, latest: false)
            .sink { [weak self] _ in
                guard let self = self else { return }
                guard self.state != .AWAITING_RESTORED_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                guard self.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                guard self.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                guard self.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                
                self.listState.lastAppearedId = self.lastAppeared?.id
                self.listState.mostRecentAppearedId = self.mostRecentRead?.id
                self.listState.lastAppearedAtAnchor = self.lastAppearedAnchorSubject.value
                self.listState.updatedAt = Date.now
                self.listState.unreadCount = self.unreadCountSubject.value
                do {
                    try self.listState.managedObjectContext?.save()
//                    print ("🟢🟢💾 LIST STATE SAVED :D")
                }
                catch {
                    print("Error saving list state \(self.id) \(self.listState.pubkey)")
                }
            }
            .store(in: &subscriptions)
    }
    
    func trackUnreadCount() {
        mostRecentReadSubject
            .sink(receiveValue: { [weak self] mostRecentPost in
                guard let self = self else { return }
                guard let mostRecentPost = mostRecentPost else { return }
                
                // SO TAKE TOTAL ON SCREEN (posts.count)
                // SUBSTRACT mostRecentPost index
                let mostRecentReadIndex = self.vPosts.map { $0.id }.firstIndex(of: mostRecentPost.id) ?? 0
                
                self.objectWillChange.send()
                self.unreadCountSubject.send(self.vPosts.count - mostRecentReadIndex - 1)
            })
            .store(in: &subscriptions)

    }
    
    func requestFooterCounters() {
        // AFTER 1 SEC OF STOP SCROLLING, WE WANT TO FETCH #E AND P (HERE)
        lastAppearedSubject
            .debounce(for: .seconds(1), scheduler: RunLoop.current)
            .throttle(for: .seconds(5), scheduler: RunLoop.current, latest: true)
            .sink { [weak self] post in
                guard let self = self else { return }
                guard let post = post else { return }
                // get 5 posts before or after
                print("🟢🟢 .requestForJustAppeared")
                if post.created_at > (self.lastAppearedSubject.value?.created_at ?? 0) {
                    // get before
                    if let indexOfPost = self.vPosts.firstIndex(of: post) {
                        let five = [
                            self.vPosts[safe: indexOfPost],
                            self.vPosts[safe: indexOfPost - 1],
                            self.vPosts[safe: indexOfPost - 2],
                            self.vPosts[safe: indexOfPost - 3],
                            self.vPosts[safe: indexOfPost - 4]
                        ]
                        sendNotification(.requestForJustAppeared, five.compactMap { $0 } )
                        self.requestForJustAppeared(five.compactMap { $0 })
                    }
                }
                else {
                    // get after
                    if let indexOfPost = self.vPosts.firstIndex(of: post) {
                        let five = [
                            self.vPosts[safe: indexOfPost],
                            self.vPosts[safe: indexOfPost + 1],
                            self.vPosts[safe: indexOfPost + 2],
                            self.vPosts[safe: indexOfPost + 3],
                            self.vPosts[safe: indexOfPost + 4]
                        ]
                        self.requestForJustAppeared(five.compactMap { $0 })
//                        sendNotification(.requestForJustAppeared, five.compactMap { $0 } )
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    func scrollToEnd() {
        state = .AWAITING_SCROLL
        sendNotification(.shouldScrollToLast)
        self.listState.lastAppearedId = self.posts.last?.id
        self.listState.mostRecentAppearedId = self.posts.last?.id
        self.listState.lastAppearedAtAnchor = "BOTTOM"
        self.listState.updatedAt = Date.now
        self.listState.unreadCount = 0
        self.unreadCountSubject.send(0)
        if (self.lastAppeared != self.vPosts.last) {
            self.lastAppearedSubject.send(self.vPosts.last)
        }
        
        // TODO: ALso implement cutoff, if 1000 posts on screen, --> .suffix 100. PROBLEM IS SCROLL OFFSET GLITCH
        do {
            try self.listState.managedObjectContext?.save()
        }
        catch {
            print("Error saving list state \(self.id) \(self.listState.pubkey)")
        }
    }
    
    func didReachEnd() {
        self.objectWillChange.send()
        self.unreadCountSubject.send(0)
    }
    
    func updateUnreadCount() {
        let mostRecentReadIndex = self.posts.map { $0.id }.firstIndex(of: self.mostRecentRead?.id) ?? 0
//        self.objectWillChange.send()
        self.unreadCountSubject.send(self.posts.count - mostRecentReadIndex - 1)
    }
    
    func requestForJustAppeared(_ vPosts:[VPost]) {
        guard self.viewIsVisible else { return }
        let ids = ids(vPosts)
        let vContacts = vPosts.compactMap { $0.vContact }
        let shouldVerifyContacts = vContacts.filter { NIP05.shouldVerify($0) }

        Task { // TODO: MOVE ALL THIS TO VIEWMODEL SOMEHOW..
//                ThreadWarning.which(".onReceive(receiveNotification(.requestForJustAppeared)")
            print("🟠🟠 fetching for ids justAppeared on \(self.id)")
            fetchStuffForLastAddedNotes(ids: ids)
//            fetchMissingReplyToContacts(events: events) // TODO: FIXME
            NIP05.verifyBatch(vContacts: shouldVerifyContacts, context: self.bg)
        }
    }
}

extension ListViewModel: NSFetchedResultsControllerDelegate {
    
    func testDropFirst() {
        self.posts = Array(self.posts.dropFirst(10))
    }
    
    func contentChanged(posts:[Event]) {
        switch (state) {
            case .AWAITING_FIRST_FETCH: // Show last 100
                self.posts = posts.prefix(MAX_VISIBLE).sorted(by: { $0.created_at < $1.created_at } )
                DispatchQueue.main.async {
                    self.state = .COMPLETED_FIRST_FETCH
                }
                
            case .AWAITING_RESTORED_FETCH: // Show last read, until end
                // show last 100 if LR is within it
                // else show all
                let lastAppearedIndex = self.lastAppearedSubject.value != nil ? vPosts.firstIndex(where: { $0.id == self.lastAppearedSubject.value!.id }) ?? -1 : -1
                
                if (lastAppearedIndex == -1) {
                    self.posts = posts.prefix(MAX_VISIBLE).sorted(by: { $0.created_at < $1.created_at } )
                    DispatchQueue.main.async {
                        self.state = .COMPLETED_FIRST_FETCH
                    }
                }
                if (lastAppearedIndex < MAX_VISIBLE) {
                    DispatchQueue.main.async {
                        self.state = .AWAITING_SCROLL
                    }
                    self.posts = posts.prefix(MAX_VISIBLE).sorted(by: { $0.created_at < $1.created_at } )
                }
                else {
                    DispatchQueue.main.async {
                        self.state = .AWAITING_SCROLL
                    }
                    self.posts = posts.sorted(by: { $0.created_at < $1.created_at } )
                }
                updateUnreadCount()
            
            default:
//            case .COMPLETED_RESTORED_FETCH_WITH_SCROLL, .SCROLLED_TO_END, .SWITCHING_ACCOUNT:
                // deduplicate, add new posts (can be older also..)
                let onScreen = Set(self.posts)
                // not older than .first or .count - 100
                
                // posts also has has items from BEFORE, that were removed with .prefix. so handle it
                let last100 = self.posts.suffix(100)
                let notTooOldCreatedAt = last100.first?.created_at ?? 0
                let newListWithoutTooOld = Set(posts.filter { $0.created_at > notTooOldCreatedAt })
                let newListWithoutOnScreen = newListWithoutTooOld.subtracting(onScreen)
                let newListWithoutOnScreenSorted = newListWithoutOnScreen.sorted(by: { $0.created_at < $1.created_at } )
                // TODO: can we speed up, optimize above 5 lines??
                if (newListWithoutOnScreenSorted.count > 0) {
                    self.posts.append(contentsOf: newListWithoutOnScreenSorted)
                    print("🟢🟢 Added \(newListWithoutOnScreenSorted.count) new")
                    updateUnreadCount()
                }
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let posts = controller.fetchedObjects as? [Event] else { return }
        contentChanged(posts: posts)
    }
}

extension Event {
    static func postsByPubkeys(_ pubkeys:Set<String>, lastAppearedCreatedAt:Int64 = 0) -> NSFetchRequest<Event> {
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8) // 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo) // 8 hours ago or longer until lastAppeared Event
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = 1000 //TODO: need this even?
        fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", cutOffPoint,  pubkeys)
        return fr
    }
}
