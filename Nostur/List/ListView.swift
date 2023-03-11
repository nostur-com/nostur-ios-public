//
//  ListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

struct ListView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Namespace var END_OF_LIST
    let nav:NavigationModel = .shared
    @EnvironmentObject var ns:NosturState
    @ObservedObject var vm:ListViewModel
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @State var isViewDisplayed = false
    let ot:OnboardingTracker = .shared
    let timelineRunLoop = Timer.publish(every: 3, tolerance: 1, on: .main, in: .common).autoconnect()
    @AppStorage("firstTimeCompleted") var firstTimeCompleted = false
    
    @State private var scrollPosition: CGPoint = .zero
    
    var body: some View {
        VStack {
//            Text("State: \(vm.state.rawValue)").lineLimit(1).onTapGesture {
//                vm.testDropFirst()
//            }
//            Text("[Dev] Results: \(vm.posts.count) || LA: \(vm.lastAppearedIndex) || MRR: \(vm.mostRecentReadIndex)")
//            Text("unreadCountSubject: \(vm.unreadCountSubject.value)")
//            Text("vm.id: \(vm.id)")
//            Text("vm.listState.listId: \(vm.listState.listId)")
//            Text("Following: \(vm.pubkeys.count.description)")
//            Text("Following: \(ns.explorePubkeys.count.description)")
            if vm.posts.count != 0 {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack {
                            ForEach(vm.posts) { post in
                                NoteRowView(event: post)
                                    .onBecomingVisible {
                                        guard vm.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                        guard vm.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                        guard vm.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                        vm.lastAppearedSubject.send(post)
                                    }
//                                    .border(vm.posts.firstIndex(of: post) == vm.lastAppearedIndex ? .green : .clear)
                                    .id(post.id)
                                    .onTapGesture { nav.navigateTo(post) }
                                Divider()
                            }
                        }
                        Rectangle().frame(width: 300, height: 1)
                            .id(END_OF_LIST)
                            .onBecomingVisible {
                                vm.didReachEnd()
                            }
                    }
                    .onReceive(receiveNotification(.shouldScrollToLast)) { _ in
                        withAnimation { proxy.scrollTo(END_OF_LIST) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            vm.state = .SCROLLED_TO_END
                        }
                    }
                    .onAppear { restoreScrollPosition(vm: vm, proxy: proxy) }
                    .onChange(of: vm) { newValue in
                        newValue.state = .SWITCHING_ACCOUNT
                        restoreScrollPosition(vm: newValue, proxy: proxy)
                    }
                }
            }
            
            if ((selectedSubTab != "Explore") && (ns.account?.follows?.count ?? 0) == 0) && ((ns.account?.publicKey ?? "NOACCOUNT") != NosturState.GUEST_ACCOUNT_PUBKEY) {
                Text("You are not following anyone yet, visit the explore tab and follow some people")
                    .multilineTextAlignment(.center)
                    .padding(/*@START_MENU_TOKEN@*/.all, 30.0/*@END_MENU_TOKEN@*/)
                    
                Button {
                    selectedSubTab = "Explore"
                } label: {
                    Text("Explore")
                }.buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            isViewDisplayed = true
            
            if (ot.isOnboarding && vm.pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
                fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
                ot.didFillTimeline = true
                firstTimeCompleted = true
            }
        }
        .onDisappear {
            isViewDisplayed = false
        }
        .onReceive(timelineRunLoop) { time in
            guard isViewDisplayed else { return }
            guard selectedSubTab == vm.id else { return } // Alternative for isViewDisplayed (because opacity 1 : 0)
            guard !Importer.shared.isImporting else { print("⏳ Still importing, new fetch skipped."); return }
            
            if (ot.isOnboarding && vm.pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
                fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
                ot.didFillTimeline = true
                firstTimeCompleted = true
            }
            else if (!ot.isOnboarding) {
                let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 4)  // 4 hours  ago
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
//                print("🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣🟣 put back after fixes" )
                let cutOffPoint = min(vm.lastAppeared?.created_at ?? hoursAgo, hoursAgo) // 8 hours ago or longer until lastAppeared Event
                fetchEvents(pubkeys: vm.pubkeys, since: cutOffPoint, subscriptionId: vm.id)
            }
            
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
    
    func restoreScrollPosition(vm:ListViewModel, proxy:ScrollViewProxy) {
        guard vm.state == .AWAITING_SCROLL || vm.state == .SWITCHING_ACCOUNT else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
        if let lastAppeared = vm.lastAppeared {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                proxy.scrollTo(lastAppeared.id, anchor: vm.lastAppearedAnchorSubject.value == "TOP" ? .top : .bottom)
                proxy.scrollTo(lastAppeared.id, anchor: .bottom)
                
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                vm.state = .COMPLETED_RESTORED_FETCH_WITH_SCROLL
            }
            
        }
    }
    enum ListType {
        case account
        case explore
        case list
    }
}

struct ListViewContainer: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @State var vm:ListViewModel?
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    let listId:String
    let listType:ListView.ListType
    
    var body: some View {
        if listType == .account {
            if (vm != nil && ns.account != nil) {
                ZStack {
                    ListView(vm: vm!)
                    ListUnreadCounter(vm: vm!)
                    NewNoteButton(showingNewNote: $showingNewNote)
                        .sheet(isPresented: $showingNewNote) {
                            NewNote(noteCancellationId: $noteCancellationId)
                        }
                }
                .onChange(of: ns.followingPublicKeys) { newValue in
                    vm = ListViewModel.fromDB(pubkey: ns.account!.publicKey, listId: "Following", pubkeys: newValue, context: viewContext)
                }
            }
            else {
                CenteredProgressView()
                    .onAppear {
                        vm = ListViewModel.fromDB(pubkey: ns.account!.publicKey, listId: "Following", pubkeys: ns.followingPublicKeys, context: viewContext)
                    }
            }
        }
        else if listType == .explore {
            if (vm != nil && ns.explorePubkeys.count > 1) {
                ZStack {
                    ListView(vm: vm!)
                    ListUnreadCounter(vm: vm!)
                    NewNoteButton(showingNewNote: $showingNewNote)
                        .sheet(isPresented: $showingNewNote) {
                            NewNote(noteCancellationId: $noteCancellationId)
                        }
                }
            }
            else {
                CenteredProgressView()
                    .onAppear {
                        if (ns.explorePubkeys.count > 1) {
                            vm = ListViewModel.fromDB(pubkey: ns.account!.publicKey, listId: "Explore", pubkeys: ns.explorePubkeys, context: viewContext)
                        }
                        else {
                            let message = ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: NosturState.EXPLORER_PUBKEY))
                            SocketPool.shared.sendMessage(message)
                        }
                    }
                    .onChange(of: ns.explorePubkeys) { newValue in
                        if (newValue.count > 1) {
                            vm = ListViewModel.fromDB(pubkey: ns.account!.publicKey, listId: "Explore", pubkeys: newValue, context: viewContext)
                        }
                    }
            }
        }
    }
}

struct ListView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ListViewContainer(listId: "Following", listType: .account)
                .withPreviewEnvironment()
        }
            
    }
}
