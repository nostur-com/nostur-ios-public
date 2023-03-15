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
//    @State var isViewDisplayed = false
    let ot:OnboardingTracker = .shared
    let timelineRunLoop = Timer.publish(every: 3, tolerance: 1, on: .main, in: .common).autoconnect()
    @AppStorage("firstTimeCompleted") var firstTimeCompleted = false
    
    @State var scrollResetId = 1
    
    var body: some View {
        VStack {
            
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
            
            Text("State: \(vm.state.rawValue)").lineLimit(1).onTapGesture {
                vm.testDropFirst()
            }
//            Text("[Dev] Results: \(vm.posts.count) || LA: \(vm.lastAppearedIndex) || MRR: \(vm.mostRecentReadIndex)")
//            Text("unreadCountSubject: \(vm.unreadCountSubject.value)")
//            Text("vm.id: \(vm.id)")
//            Text("vm.listState.listId: \(vm.listState.listId)")
//            Text("Following: \(vm.pubkeys.count.description)")
//            Text("Following: \(ns.explorePubkeys.count.description)")
            
            if vm.vPosts.count != 0 {
                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach(vm.vPosts) { vPost in
                                NoteRow(vPost:vPost)
                                    .id(vPost.id)
                                    .listRowInsets(EdgeInsets())
                                    .onBecomingVisible {
                                        guard vm.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                        guard vm.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                        guard vm.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                        vm.lastAppearedSubject.send(vPost)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button {
                                            ns.toggleBookmark(vPost)
                                        } label: {
                                            Image(systemName: "bookmark")
                                        }
                                        .tint(.orange)

                                    }
                            }
                        }
                        Section {
                            HStack {
                                Spacer()
                                Rectangle().frame(width: 300, height: 1)
                                Spacer()
                            }
                            .id(END_OF_LIST)
                            .onBecomingVisible {
                                guard vm.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                guard vm.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                guard vm.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we
                                
                                vm.didReachEnd()
                            }
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    .id(scrollResetId)
                    .listStyle(.plain)
                    .onReceive(receiveNotification(.shouldScrollToLast)) { _ in
//                        withAnimation {
//                            proxy.scrollTo(vm.posts.last)
//                        }
                        scrollResetId += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                    proxy.scrollTo(END_OF_LIST)
                                    vm.state = .SCROLLED_TO_END
                            }
                        }
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
//                            vm.state = .SCROLLED_TO_END
//                        }
                    }
                    .onAppear { restoreScrollPosition(vm: vm, proxy: proxy) }
                    .onChange(of: vm) { newValue in
                        newValue.state = .SWITCHING_ACCOUNT
                        restoreScrollPosition(vm: newValue, proxy: proxy)
                    }
                }
            }
        }
        .onAppear {
            vm.viewIsVisibleSubject.send(true)
//            isViewDisplayed = true
            
            if (ot.isOnboarding && vm.pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
                fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
                ot.didFillTimeline = true
                firstTimeCompleted = true
            }
        }
        .onDisappear {
            vm.viewIsVisibleSubject.send(false)
//            isViewDisplayed = false
        }
        .onChange(of: selectedSubTab, perform: { newValue in
            vm.selectedSubTabSubject.send(newValue) // Listen for changes in ViewModel too much code, here just 1 line.. soo
        })
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
        else {
            vm.state = .COMPLETED_FIRST_FETCH
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
