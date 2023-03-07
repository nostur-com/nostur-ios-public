//
//  PostList.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2023.
//
import SwiftUI
import CoreData
import Combine


struct PostListContainer: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    let id:String
    
    @State var state:PostListModel?
    
    var body: some View {
        VStack {
            if state != nil {
                ZStack {
                    PostList(pubkey: ns.account!.publicKey, pubkeys: ns.followingPublicKeys, context: viewContext, state:state!)
                    NewNoteButton(showingNewNote: $showingNewNote)
                    VStack {
                        Spacer()
                        PostListUnreadCounter(state:state!)
                    }
                }
                .sheet(isPresented: $showingNewNote) {
                    NewNote(noteCancellationId: $noteCancellationId)
                }
            }
        }
        .onAppear {
            guard let account = ns.account else { return }
            self.state = PostListModel.fromDb(pubkey: account.publicKey, listId: id, context: viewContext)
        }
        .onChange(of: ns.activeAccountPublicKey) { newValue in
            self.state = PostListModel.fromDb(pubkey: ns.account!.publicKey, listId: id, context: viewContext)
        }
    }
}

struct PostList: View {
    @Environment(\.managedObjectContext) var viewContext
    let nav:NavigationModel = .shared
    let FETCH_LIMIT = 250
    let MAX = 100
    let state:PostListModel
    let ot:OnboardingTracker = .shared
    let pubkeys:Set<String>
    @Namespace var END_OF_LIST
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false))
    var posts:FetchedResults<Event>
    var postsNewestAtBottom:[Event] {
        posts.sorted(by: { $0.created_at < $1.created_at } )
    }
    
    @AppStorage("firstTimeCompleted") var firstTimeCompleted = false
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @State var isViewDisplayed = false
    @State var visiblePosts:[Event]?
    @State var didRestoreState = false // NEED SO USER INITIATED .onAppear is not overwritten by other .onAppear (init, restore)
    let pubkey:String
    let timelineRunLoop = Timer.publish(every: 3, tolerance: 1, on: .main, in: .common).autoconnect()
    let lastAppearedCreatedAtPlusHours:Int64
    
    init(pubkey:String, pubkeys:Set<String>, context:NSManagedObjectContext, state:PostListModel) {
        print("🧨🧨🧨🧨🧨🧨🧨🧨 INIT PostList \(state.id) \(state.listState.pubkey)  🧨🧨🧨🧨🧨🧨🧨🧨")
        UIScrollView.appearance().bounces = false // Needed to not mess up detection of scroll direction
        self.state = state
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        if let lastAppeared = state.lastAppeared {
            let r1 = Event.fetchRequest()
            r1.predicate = NSPredicate(format: "id == %@", lastAppeared.id)
            r1.fetchLimit = 1
            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            
            // get .created_at of lastAppearedId. OR now if nil
            let lastAppearedCreatedAt = (try? context.fetch(r1).first?.created_at) ?? Int64(Date.now.timeIntervalSince1970)

            // then fetch posts 8 hours before .created_at, or before now if nil
            self.lastAppearedCreatedAtPlusHours = lastAppearedCreatedAt - (3600 * 8)
            
                
                                                 
            let r2 = Event.fetchRequest()
            r2.predicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", self.lastAppearedCreatedAtPlusHours, pubkeys)
            r2.fetchLimit = FETCH_LIMIT
            r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            _posts = FetchRequest(fetchRequest: r2)
        }
        else {
            let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8)
            self.lastAppearedCreatedAtPlusHours = hoursAgo
                                                    
            let r2 = Event.fetchRequest()
            r2.predicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", hoursAgo, pubkeys)
            r2.fetchLimit = FETCH_LIMIT
            r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            _posts = FetchRequest(fetchRequest: r2)
        }
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
//            Text("haa")
            if let visiblePosts {
                ScrollViewReader { proxy in
                    List {
                        ForEach(visiblePosts) { post in
                            NoteRowView(event: post)
                                .listRowInsets(EdgeInsets())
                                .onBecomingVisible {
                                    guard didRestoreState else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                    state.setLastAppeared.send(post)
                                    state.updateUnreadCount.send(visiblePosts)
                                }
                            .id(post.id)
                            .onTapGesture {
                                nav.navigateTo(post)
                            }
                        }
                        Rectangle().frame(width: 100,height: 0).id(END_OF_LIST)
                    }
//                    .id(pubkey)
                    .listStyle(.plain)
                    .onAppear {
                        guard !didRestoreState else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
                        if let lastAppeared = state.lastAppeared {
                                proxy.scrollTo(lastAppeared.id, anchor: state.lastAppearedAtAnchor == "TOP" ? .top : .bottom)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            didRestoreState = true
                        }
                    }
                    //crash..
//                    .onReceive(receiveNotification(.shouldScrollToLast)) { _ in
//                        proxy.scrollTo(END_OF_LIST)
//                    }
//                    .onChange(of: pubkey) { newState in
//                        setVisiblePosts()
//                        print("🔥🔥🔥 state pubkey \(newState.listState.pubkey)")
//                        if let lastAppeared = newState.lastAppeared {
//                            proxy.scrollTo(lastAppeared.id, anchor: newState.lastAppearedAtAnchor == "TOP" ? .top : .bottom)
//                        }
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                            didRestoreState = true
//                        }
////                        if let lastAppeared = state.lastAppeared {
////                            let r1 = Event.fetchRequest()
////                            r1.predicate = NSPredicate(format: "id == %@", lastAppeared.id)
////                            r1.fetchLimit = 1
////                            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
////
////                            // get .created_at of lastAppearedId. OR now if nil
////                            let lastAppearedCreatedAt = (try? viewContext.fetch(r1).first?.created_at) ?? Int64(Date.now.timeIntervalSince1970)
////
////                            // then fetch posts 8 hours before .created_at, or before now if nil
////                            let lastAppearedCreatedAtPlusHours = lastAppearedCreatedAt - (3600 * 8)
////
////                            posts.nsPredicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", lastAppearedCreatedAtPlusHours, pubkeys)
////                        }
////                        else {
////                            let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8)
////                            let lastAppearedCreatedAtPlusHours = hoursAgo
////                            posts.nsPredicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", hoursAgo, pubkeys)
////                        }
////
////                        if let lastAppeared = state.lastAppeared {
////                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
////                                proxy.scrollTo(lastAppeared.id, anchor: state.lastAppearedAtAnchor == "TOP" ? .top : .bottom)
////                            }
////                        }
////                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
////                            didRestoreState = true
////                        }
//                    }
                }
            }
        }
        .onAppear {
            isViewDisplayed = true
            
            if (ot.isOnboarding && pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
                fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
                ot.didFillTimeline = true
                firstTimeCompleted = true
            }
            
            guard !didRestoreState else { return } // Only restore state once (so not again at like nav to post and back)
            setVisiblePosts()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                restoreUnreadCount()
            }
        }
        .onDisappear {
            isViewDisplayed = false
        }
        .onReceive(timelineRunLoop) { time in
            guard isViewDisplayed else { return }
            guard selectedSubTab == state.id else { return } // Alternative for isViewDisplayed (because opacity 1 : 0)
            guard !Importer.shared.isImporting else { print("⏳ Still importing, new fetch skipped."); return }
            
            if (ot.isOnboarding && pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
                fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
                ot.didFillTimeline = true
                firstTimeCompleted = true
            }
            else if (!ot.isOnboarding) {
                let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8)  // 8 hours  ago
                if (visiblePosts == nil) {
                    fetchEvents(pubkeys: pubkeys, since: hoursAgo, subscriptionId: state.id)
                }
                else {
                    // Start from first event, but not more than 8 hours ago...
                    // Else it will load 1000 posts on timeline and Core data has some bug with fetchlimit
                    fetchEvents(pubkeys: pubkeys, since: lastAppearedCreatedAtPlusHours < hoursAgo ? hoursAgo : lastAppearedCreatedAtPlusHours, subscriptionId: state.id)
                }
            }
            
        }
        .onChange(of: postsNewestAtBottom.last) { newestPost in
            setVisiblePostsOnChange()
        }
//        onChange(of: pubkey) { newValue in
//            visiblePosts = []
//            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//                setVisiblePosts()
//            }
//        }
    }
    
    func setVisiblePosts() {
        // @TODO: BECAUSE SCROLL GLITCHES: Only remove prefix items when scrolled at bottom, so we can rescroll after removing prefix, so UI doesnt snap!
        guard state.lastAppeared != nil else {
            visiblePosts = postsNewestAtBottom.suffix(MAX) // IF FIRST TIME, SHOW LAST 100
            return
        }

        // GET INDEX OF LAST APPEARED POST, PREFIX AND SUFFIX MAX/2
        guard let lastAppearedIndex = posts.firstIndex(where: { $0.id == state.lastAppeared!.id }) else {
            visiblePosts = postsNewestAtBottom.suffix(MAX) // IF NOT FOUND, SHOW LAST 100
            return
        }
        let startIndex = max(lastAppearedIndex - MAX/2, 0)                  // [MAX/2] BEFORE
//        let endIndex = min(lastAppearedIndex + MAX/2, posts.count - 1)      // [MAX/2] AFTER
        let endIndex = postsNewestAtBottom.count - 1                                      // INFINITE AFTER
        visiblePosts = Array(postsNewestAtBottom[startIndex...endIndex])
        state.unreadCount.send(visiblePosts?.count ?? 0) // werkt niet???
        // uhmm dit hierboven allemaal hier doen?
        // of send(visisibleposts) en dan daar doen?
    }
    
    func setVisiblePostsOnChange() {
        // @TODO: BECAUSE SCROLL GLITCHES: Only remove prefix items when scrolled at bottom, so we can rescroll after removing prefix, so UI doesnt snap!

        
        let oldestPostOnScreen = visiblePosts?.first
        let oldestPostOnScreenNewIndex = oldestPostOnScreen != nil
                        ? (postsNewestAtBottom.firstIndex(where: { $0.id == oldestPostOnScreen!.id }) ?? 0)
                        : 0

        let startIndex = max(oldestPostOnScreenNewIndex, 0)
        let endIndex = postsNewestAtBottom.count - 1 
        visiblePosts = Array(postsNewestAtBottom[startIndex...endIndex])

//        state.unreadCount.send(visiblePosts?.count ?? 0) // Waarom werkt dit niet??
        state.updateUnreadCount.send(visiblePosts ?? [])
        // uhmm dit hierboven allemaal hier doen?
        // of send(visisibleposts) en dan daar doen?
    }
    
    func restoreUnreadCount() {
//        guard let mostRecentAppeared = state.mostRecentAppeared else { return }
        guard let visiblePosts = self.visiblePosts else { return }
        
//        let lastAppearedIndex = visiblePosts.map { $0.id }.firstIndex(of: mostRecentAppeared.id) ?? 0
        
//        state.unreadCount.send(visiblePosts.count - lastAppearedIndex - 1) // Werkt niet?
        state.updateUnreadCount.send(visiblePosts)
        // uhmm dit hierboven allemaal hier doen?
        // of send(visisibleposts) en dan daar doen?
    }
}

struct PostList_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PostListContainer(id:"Following")
        }
        .withPreviewEnvironment()
    }
}


