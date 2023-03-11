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
    let type:PostListContainer.PostListType
    
    enum PostListType {
        case account
        case explore
        case list
    }
    
    @State var state:PostListModel?
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    
    var body: some View {
        VStack {
            if state != nil && ns.account != nil {
                
                if (type == .explore) {
                    if (ns.rawExplorePubkeys.count == 0) {
                        CenteredProgressView()
                            .onAppear {
                                let message = ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: NosturState.EXPLORER_PUBKEY))
                                SocketPool.shared.sendMessage(message)
                            }
                    }
                    else {
                        ZStack {
                            PostList(pubkey: ns.account!.publicKey, pubkeys: ns.explorePubkeys, context: viewContext, state:state!)
                            NewNoteButton(showingNewNote: $showingNewNote)
                                .sheet(isPresented: $showingNewNote) {
                                    NewNote(noteCancellationId: $noteCancellationId)
                                }
                            VStack {
                                Spacer()
                                PostListUnreadCounter(state:state!)
                            }
                        }
                    }
                }
                else {
                    if ((ns.account?.follows?.count ?? 0) == 0) {
                        Text("You are not following anyone yet, visit the explore tab and follow some people")
                            .multilineTextAlignment(.center)
                            .padding(/*@START_MENU_TOKEN@*/.all, 30.0/*@END_MENU_TOKEN@*/)
                            
                        Button {
                            selectedSubTab = "Explore"
                        } label: {
                            Text("Explore")
                        }.buttonStyle(.borderedProminent)
                    }
                    else {
                        ZStack {
                            PostList(pubkey: ns.account!.publicKey, pubkeys: ns.followingPublicKeys, context: viewContext, state:state!)
                            NewNoteButton(showingNewNote: $showingNewNote)
                                .sheet(isPresented: $showingNewNote) {
                                    NewNote(noteCancellationId: $noteCancellationId)
                                }
                            VStack {
                                Spacer()
                                PostListUnreadCounter(state:state!)
                            }
                        }
                    }
                }
            }
            else {
                CenteredProgressView()
            }
        }
        .onAppear {
            guard let account = ns.account else { return }
            let pubkey = type == .explore ? NosturState.EXPLORER_PUBKEY : account.publicKey
            self.state = PostListModel.fromDb(pubkey: pubkey, listId: id, context: viewContext)
        }
        .onChange(of: ns.activeAccountPublicKey) { activeAccountPublicKey in
            let pubkey = type == .explore ? NosturState.EXPLORER_PUBKEY : activeAccountPublicKey
            self.state = PostListModel.fromDb(pubkey: pubkey, listId: id, context: viewContext)
        }
    }
}

struct PostList: View, Identifiable {
    @Environment(\.managedObjectContext) var viewContext
    let nav:NavigationModel = .shared
    let FETCH_LIMIT = 500
    let MAX = 100
    @ObservedObject var state:PostListModel
    @EnvironmentObject var ns:NosturState
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
//    @State var visiblePosts:[Event]?
    @State var didRestoreState = false // NEED SO USER INITIATED .onAppear is not overwritten by other .onAppear (init, restore)
    let pubkey:String
    let timelineRunLoop = Timer.publish(every: 3, tolerance: 1, on: .main, in: .common).autoconnect()
    @State var cutOffPoint:Int64 = 0
    var id:String {
        state.listState.listId
    }
    
    init(pubkey:String, pubkeys:Set<String>, context:NSManagedObjectContext, state:PostListModel) {
        print("🧨🧨🧨🧨🧨🧨🧨🧨 INIT PostList \(state.id) \(state.listState.pubkey)  🧨🧨🧨🧨🧨🧨🧨🧨")
        UIScrollView.appearance().bounces = false // Needed to not mess up detection of scroll direction
        self.state = state
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        
        let startEmpty = Event.fetchRequest()
        startEmpty.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        startEmpty.predicate = NSPredicate(value: false)
        startEmpty.fetchLimit = FETCH_LIMIT
        _posts = FetchRequest(fetchRequest: startEmpty)
    }
    
    let STYLE = "LAZYVSTACK" //
    
    var visiblePosts:[Event] {
        self.state.visiblePostsSubject.value
    }
    
    var lastAppeared:Event? {
        self.state.lastAppearedSubject.value
    }
    
    var mostRecentRead:Event? {
        self.state.mostRecentReadSubject.value
    }
    
    @AppStorage("devToggle") var devToggle:Bool = false
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            if 1 == 1 && devToggle {
                VStack {
                    Text(posts.nsPredicate?.description ?? "").lineLimit(1)
                        .onTapGesture {
                            setPredicate(state: state)
                        }
                    Text("[Dev] Results: \(posts.count)  || Visible:\(visiblePosts.count) || LA: \(lastAppeared != nil ? visiblePosts.firstIndex(of: lastAppeared!) ?? -1 : -1 ) || MRR: \(mostRecentRead != nil ? visiblePosts.firstIndex(of: mostRecentRead!) ?? -1 : -1 )")
                    Text(state.listState.pubkey.prefix(11).description)
                }
            }
            ScrollViewReader { proxy in
                VStack {
                    if (visiblePosts.count > 0) {
                        if (STYLE == "LAZYVSTACK") {
                            ScrollView {
                                LazyVStack {
                                    ForEach(visiblePosts) { post in
                                        NoteRowView(event: post)
                                            .onBecomingVisible {
                                                guard didRestoreState else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                                state.lastAppearedSubject.send(post)
//                                                state.updateUnreadCount.send(visiblePosts!)
                                            }
                                            .id(post.id)
                                            .onTapGesture {
                                                nav.navigateTo(post)
                                            }
                                        Divider()
                                    }
                                }
                                Rectangle().frame(width: 100,height: 0).id(END_OF_LIST)
                            }
                            .onReceive(receiveNotification(.shouldScrollToLast)) { _ in
                                withAnimation {
                                    proxy.scrollTo(END_OF_LIST)
                                }
                            }
                            .onAppear {
                                // ONLY SCROLL BACK TO RESTORE STATE IN THIS .onAppear!
                                // NOTHING ELSE!
                                guard !didRestoreState else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
                                
                                if let lastAppeared = state.lastAppearedSubject.value {
                                    proxy.scrollTo(lastAppeared.id, anchor: state.lastAppearedAnchorSubject.value == "TOP" ? .top : .bottom)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    didRestoreState = true
//                                    restoreUnreadCount()
                                }
                            }
                        }
                        else {
                            List {
                                ForEach(visiblePosts) { post in
                                    NoteRowView(event: post)
                                        .listRowInsets(EdgeInsets())
                                        .onBecomingVisible {
                                            guard didRestoreState else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                            state.lastAppearedSubject.send(post)
//                                            state.updateUnreadCount.send(visiblePosts!)
                                        }
                                        .id(post.id)
                                        .onTapGesture {
                                            nav.navigateTo(post)
                                        }
                                }
                                Rectangle().frame(width: 100,height: 0).id(END_OF_LIST)
                            }
                            .id(pubkey)
                            .listStyle(.plain)
                        }
                    }
                    else {
                        CenteredProgressView()
                    }
                }
                .onAppear {
                    return
                    // ONLY SET VISIBLE POSTS HERE, DONT SCROLL BACK HERE! TO IN OTHER .ONAPPEAR
                    guard !didRestoreState else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
                    setVisiblePosts()
                }
                .onChange(of: pubkey) { newPubkey in
                    return
                    didRestoreState = false
                    state.visiblePostsSubject.send([])
                    setVisiblePosts() // maybe someone do this here .send(newPosts)...
//                        print("🔥🔥🔥 state pubkey \(state.listState.pubkey)")
                    if let lastAppeared = state.lastAppearedSubject.value {
                        proxy.scrollTo(lastAppeared.id, anchor: state.lastAppearedAnchorSubject.value == "TOP" ? .top : .bottom)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        didRestoreState = true
                    }
                }
//                    .onChange(of: pubkey) { newPubkey in
//                        state.unreadCount.send(0)
//                        self.visiblePosts = []
//                        setVisiblePosts()
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                            restoreUnreadCount()
//                        }
////                        if (1==2) { // CRASHES PROBABLY APPLE BUG.
//                            if let lastAppeared = state.lastAppeared {
//                                proxy.scrollTo(lastAppeared.id, anchor: state.lastAppearedAtAnchor == "TOP" ? .top : .bottom)
//                            }
////                        }
//                    }
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
        .onAppear {
            isViewDisplayed = true
            
            if (ot.isOnboarding && pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
                fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
                ot.didFillTimeline = true
                firstTimeCompleted = true
            }
            
            guard !didRestoreState else { return } // Only restore state once (so not again at like nav to post and back)
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
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
                fetchEvents(pubkeys: pubkeys, since: cutOffPoint, subscriptionId: state.id)
            }
            
        }
        .onChange(of: postsNewestAtBottom.last) { newestPost in
            print("🟢🟢 2 onChange \(state.listState.listId)")
            setVisiblePostsOnChange()
        }
        .onReceive(receiveNotification(.requestForJustAppeared)) { notification in
//            print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//            print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//            print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//            return
//            guard 1 == 2 else { return } // Performance test
//            guard !isScrolling else { return }
            let events = notification.object as! [Event]
            
            let ids = ids(events)
            let contacts = events.compactMap { $0.contact }
            let shouldVerifyContacts = contacts.filter { NIP05.shouldVerify($0) }
//            Task.detached(priority: .userInitiated) {
            Task {
//                ThreadWarning.which(".onReceive(receiveNotification(.requestForJustAppeared)")
                print("🟠🟠 fetching for ids justAppeared")
                fetchStuffForLastAddedNotes(ids: ids)
                fetchMissingReplyToContacts(events: events)
                NIP05.verifyBatch(contacts: shouldVerifyContacts, context: viewContext)
            }
        }
        .onAppear {
            guard !didRestoreState else { return }
            print("🟢🟢 1 \(state.listState.listId)")
            print("PUBKEYS: \(pubkey) \(state.listState.listId)")
            setPredicate(state:state)
            
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//
//            }
        }
        .onChange(of: state) { newState in
            print("🟢🟢 3 \(newState.listState.listId)")
            print("PUBKEYS: \(pubkey) \(state.listState.listId)")
            setPredicate(state:newState)
//            setVisiblePosts()
        }
        .onChange(of: ns.explorePubkeys) { explorePubkeys in
            print("🟢🟢 4 \(state.listState.listId)")
            print("PUBKEYS: \(pubkey) \(state.listState.listId) \(explorePubkeys.count)")
            setPredicate(state:state)
//            setVisiblePosts()
        }
    }
    
    func setPredicate(state:PostListModel) {
        print("🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢")
        posts.nsPredicate = NSPredicate(value: false)
        DispatchQueue.main.asyncAfter(deadline: .now() +  0.5) {
            let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8) // 8 hours ago
            if let lastAppeared = state.lastAppearedSubject.value {
                let r1 = Event.fetchRequest()
                r1.predicate = NSPredicate(format: "id == %@", lastAppeared.id)
                r1.fetchLimit = 1
                r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
                
                
                // get .created_at of lastAppearedId. OR now if nil
                let lastAppearedCreatedAt = (try? viewContext.fetch(r1).first?.created_at) ?? Int64(Date.now.timeIntervalSince1970)
                
                cutOffPoint = min(lastAppearedCreatedAt, hoursAgo) // 8 hours ago or longer until lastAppeared Event
                posts.sortDescriptors = [SortDescriptor(\Event.created_at, order: .reverse)]
                posts.nsPredicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", cutOffPoint,  pubkeys)
                print("🟢🟢 0.1 setPredicate \(pubkeys.count) ")
            }
            else {
                cutOffPoint = hoursAgo
                posts.nsPredicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", cutOffPoint, pubkeys)
                print("🟢🟢 0.2 setPredicate \(pubkeys.count) ")
            }
        }
    }
    
    func setVisiblePosts() {
        print("🟢🟢🟢🟢 yo you should not call me")
        return
        // @TODO: BECAUSE SCROLL GLITCHES: Only remove prefix items when scrolled at bottom, so we can rescroll after removing prefix, so UI doesnt snap!
        guard state.lastAppearedSubject.value != nil else {
            state.visiblePostsSubject.send(postsNewestAtBottom.suffix(MAX)) // IF FIRST TIME, SHOW LAST 100
            return
        }

        // GET INDEX OF LAST APPEARED POST, PREFIX AND SUFFIX MAX/2
        guard let lastAppearedIndex = posts.firstIndex(where: { $0.id == state.lastAppearedSubject.value!.id }) else {
            state.visiblePostsSubject.send(postsNewestAtBottom.suffix(MAX)) // IF NOT FOUND, SHOW LAST 100
            return
        }
        let startIndex = max(lastAppearedIndex - MAX/2, 0)                  // [MAX/2] BEFORE
//        let endIndex = min(lastAppearedIndex + MAX/2, posts.count - 1)      // [MAX/2] AFTER
        let endIndex = postsNewestAtBottom.count - 1                                      // INFINITE AFTER
        state.visiblePostsSubject.send(Array(postsNewestAtBottom[startIndex...endIndex]))
//        state.unreadCount.send(visiblePosts?.count ?? 0) // werkt niet???

//        state.updateUnreadCount.send(visiblePosts ?? [])
        // uhmm dit hierboven allemaal hier doen?
        // of send(visisibleposts) en dan daar doen?
    }
    
    func setVisiblePostsOnChange() {
        // @TODO: BECAUSE SCROLL GLITCHES: Only remove prefix items when scrolled at bottom, so we can rescroll after removing prefix, so UI doesnt snap!

        if (visiblePosts.count == 0) {
        // NOTHING ON SCREEN YET:
            if let lastAppeared {
                if let lastAppearedIndex = posts.firstIndex(where: { $0.id == lastAppeared.id }) {
                    if lastAppearedIndex > (posts.count - MAX) {
                        // INCREASE CUTOFF SO LAST APPEARED STILL GETS IN
                        state.visiblePostsSubject.send(postsNewestAtBottom)
                        print("🟢🟢 2.1 visiblePosts.count \(visiblePosts.count) \(state.listState.listId)")
                    }
                    else {
                        // NORMAL CUTOFF
                        state.visiblePostsSubject.send(postsNewestAtBottom.suffix(MAX))
                        print("🟢🟢 2.2 visiblePosts.count \(visiblePosts.count) \(state.listState.listId)")
                    }
                }
                else {
                    // DUNNO where lastappeared post is.
                    state.visiblePostsSubject.send(postsNewestAtBottom.suffix(MAX))
                }
            }
            else {
                // NORMAL CUTOFF
                state.visiblePostsSubject.send(postsNewestAtBottom.suffix(MAX))
                print("🟢🟢 2.2 visiblePosts.count \(visiblePosts.count) \(state.listState.listId)")
            }
        }
        else {
        // UPDATE WITH ALREADY POSTS ON SCREEN
            let oldestPostOnScreen = visiblePosts.first
            let oldestPostOnScreenNewIndex = oldestPostOnScreen != nil
                ? (postsNewestAtBottom.firstIndex(where: { $0.id == oldestPostOnScreen!.id }) ?? 0)
                : 0
            
            let startIndex = max(oldestPostOnScreenNewIndex, 0)
            let endIndex = postsNewestAtBottom.count - 1
            if postsNewestAtBottom.count > 0 {
                let send = Array(postsNewestAtBottom[startIndex...endIndex])
                state.visiblePostsSubject.send(send)
                print("🟢🟢 2.3 send.count \(send.count) \(state.listState.listId)")
            }
            else {
                state.visiblePostsSubject.send(postsNewestAtBottom)
                print("🟢🟢 2.4 send.count \(postsNewestAtBottom.count) \(state.listState.listId)")
            }
            
            
            
        }
            
            
//
//
//            guard state.lastAppearedSubject.value != nil else {
//                state.visiblePostsSubject.send(postsNewestAtBottom.suffix(MAX)) // IF FIRST TIME, SHOW LAST 100
//                print("🟢🟢 2.1 visiblePosts.count \(visiblePosts.count)")
//                return
//            }
//
//            // GET INDEX OF LAST APPEARED POST, PREFIX AND SUFFIX MAX/2
//            guard let lastAppearedIndex = posts.firstIndex(where: { $0.id == state.lastAppearedSubject.value!.id }) else {
//                state.visiblePostsSubject.send(postsNewestAtBottom.suffix(MAX)) // IF NOT FOUND, SHOW LAST 100
//                print("🟢🟢 2.2 visiblePosts.count \(visiblePosts.count)")
//                return
//            }
//            let startIndex = max(lastAppearedIndex - MAX/2, 0)                  // [MAX/2] BEFORE
//    //        let endIndex = min(lastAppearedIndex + MAX/2, posts.count - 1)      // [MAX/2] AFTER
//            let endIndex = postsNewestAtBottom.count - 1                                      // INFINITE AFTER
//            state.visiblePostsSubject.send(Array(postsNewestAtBottom[startIndex...endIndex]))
//            print("🟢🟢 2.3 visiblePosts.count \(visiblePosts.count)")
//        }
//        else {
//
//
//            let oldestPostOnScreen = visiblePosts.first
//            let oldestPostOnScreenNewIndex = oldestPostOnScreen != nil
//            ? (postsNewestAtBottom.firstIndex(where: { $0.id == oldestPostOnScreen!.id }) ?? 0)
//            : 0
//
//            let startIndex = max(oldestPostOnScreenNewIndex, 0)
//            let endIndex = postsNewestAtBottom.count - 1
//            guard postsNewestAtBottom.count > 0 else { return }
//            state.visiblePostsSubject.send(Array(postsNewestAtBottom[startIndex...endIndex]))
//            print("🟢🟢 4 visiblePosts.count \(visiblePosts.count)")
//        }
////        state.unreadCount.send(visiblePosts?.count ?? 0) // Waarom werkt dit niet??
//        state.updateUnreadCount.send(visiblePosts ?? [])
        // uhmm dit hierboven allemaal hier doen?
        // of send(visisibleposts) en dan daar doen?
    }
    
    func restoreUnreadCount() {
        return
//        guard let mostRecentAppeared = state.mostRecentAppeared else { return }
//        guard let visiblePosts = state.visiblePosts else { return }
        
//        let lastAppearedIndex = visiblePosts.map { $0.id }.firstIndex(of: mostRecentAppeared.id) ?? 0
        
//        state.unreadCount.send(visiblePosts.count - lastAppearedIndex - 1) // Werkt niet?
//        state.updateUnreadCount.send(visiblePosts)
        // uhmm dit hierboven allemaal hier doen?
        // of send(visisibleposts) en dan daar doen?
    }
    
    func fetchMissingReplyToContacts(events:[Event]) {
        // PLAN
        // FOR EVERY EVENT
        //   TAKE P's. IF P IS NOT IN EVENT.CONTACTS, ADD IT
        // FINALLY, EVERY MISSING OR EMPTY CONTACT
        //  sp.fetch!
        
        for event in events {
            let pubkeys = Array(Set(event.pTags()))
            if pubkeys.count > 0 {
                let contacts = Contact.fetchByPubkeys(pubkeys, context:viewContext)
//                event.objectWillChange.send()
                // dit moet op main queue?
//                ThreadWarning.which("Event.addToContacts( 💖💖💖")
                event.addToContacts(NSSet(array: contacts))
            }
        }
        // TODO: FIXEN
        // TODO, bij importer, replyTo p in event.replyToPTag for speed up
        let pubkeys = Array(Set(events.flatMap { TagsHelpers($0.tags()).pTags().map{ $0.pubkey } }))
        let contacts = Contact.fetchByPubkeys(pubkeys, context: viewContext)
        let missingPubkeys = pubkeys.filter {
            contacts.map { $0.pubkey }.firstIndex(of: $0) == nil
        }
        let emptyContactPubkeys = pubkeys
            .compactMap { pubkey in
                contacts.first(where: { $0.pubkey == pubkey })
            }
            .filter { $0.updated_at == 0 }
            .map { $0.pubkey }
        
        guard (missingPubkeys + emptyContactPubkeys).count > 0 else { return }
//        ThreadWarning.which("SocketPool.shared.sendMessag 💖💖💖")
        SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingPubkeys + emptyContactPubkeys )))
    
    }
}

struct PostList_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PostListContainer(id:"Following", type:.account)
        }
        .withPreviewEnvironment()
    }
}


