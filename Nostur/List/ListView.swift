//
//  ListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

struct ListViewContainer: View, Equatable {
    static func == (lhs: ListViewContainer, rhs: ListViewContainer) -> Bool {
        lhs.pubkey == rhs.pubkey
        && lhs.pubkeys.count == rhs.pubkeys.count
        && lhs.listId == rhs.listId
    }
    
    @EnvironmentObject var ns:NosturState
    @StateObject var vm:LVM
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    let listId:String
    let listType:ListView.ListType
    @State var pubkey:String = ""
    @State var pubkeys:Set<String> = []
    
    init(pubkey:String, pubkeys:Set<String>, listId: String, listType: ListView.ListType) {
        self.listId = listId
        self.listType = listType
        let lvm = LVM(pubkey: pubkey, pubkeys: pubkeys, listId: listId)
        self._vm = StateObject(wrappedValue: lvm)
        self.showingNewNote = showingNewNote
        self.noteCancellationId = noteCancellationId
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        
    }
    
    var body: some View {
        let _ = print("🔴🔴🔴🔴 ListViewContainer 🔴🔴🔴🔴")
        let _ = Self._printChanges()
        ZStack {
            ListView(vm:vm, vmState:vm.lvmState)
            ListUnreadCounter(vm:vm, vmCounter: vm.lvmCounter)
            NewNoteButton(showingNewNote: $showingNewNote)
                .sheet(isPresented: $showingNewNote) {
                    NewNote(noteCancellationId: $noteCancellationId)
                }
        }
        .onChange(of: ns.activeAccountPublicKey) { newPubkey in
            print("🟣🟣🟣🟣🟣🟣🟣🟣 ACCOUNT CHANGED 🟣🟣🟣🟣🟣🟣🟣")
            print("🟣🟣🟣🟣🟣🟣🟣🟣 following: \(ns.followingPublicKeys.count) 🟣🟣🟣🟣🟣🟣🟣")
            print("🟣🟣🟣🟣🟣🟣🟣🟣 explore: \(ns.explorePubkeys.count) 🟣🟣🟣🟣🟣🟣🟣")
            pubkey = newPubkey
            pubkeys =  listType == .account ? ns.followingPublicKeys : ns.explorePubkeys
            
            vm.changeLVM(pubkey:newPubkey,
                         pubkeys: listType == .account ? ns.followingPublicKeys : ns.explorePubkeys,
                         listId: listId)
            vm.performFetch()
        }
        .onChange(of: ns.followingPublicKeys) { pubkeys in
            guard listType == .account else { return }
            vm.changeFollowers(pubkeys:pubkeys)
        }
        .onChange(of: ns.explorePubkeys) { pubkeys in
            guard listType == .explore else { return }
            vm.changeFollowers(pubkeys:pubkeys)
        }
    }
}

struct ListView: View {
    enum ListType {
        case account
        case explore
        case list
    }
    //    @AppStorage("firstTimeCompleted") var firstTimeCompleted = false // TODO: FIND SOLUTION FOR THIS
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @EnvironmentObject var ns:NosturState
    @Namespace var END_OF_LIST
    @State var scrollResetId = 0
//    let vPosts:[VPost]
    let vm:LVM
    @ObservedObject var vmState:LVMState
    
//    @State var lastAppeared:Event? // For local rendering (border)
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
//            Text("posts: \(vmState.vPosts.count)")
//            Text("state: \(vmState.state.rawValue)")
//                .onTapGesture {
//                    vm.state = .COMPLETED_RESTORED_FETCH_WITH_SCROLL
//                }
            //            if ((selectedSubTab != "Explore") && (ns.account?.follows?.count ?? 0) == 0) && ((ns.account?.publicKey ?? "NOACCOUNT") != NosturState.GUEST_ACCOUNT_PUBKEY) {
            //                Text("You are not following anyone yet, visit the explore tab and follow some people")
            //                    .multilineTextAlignment(.center)
            //                    .padding(/*@START_MENU_TOKEN@*/.all, 30.0/*@END_MENU_TOKEN@*/)
            //
            //                Button {
            //                    selectedSubTab = "Explore"
            //                } label: {
            //                    Text("Explore")
            //                }.buttonStyle(.borderedProminent)
            //            }
            
            //            Text("State: \(vm.state.rawValue)").lineLimit(1) // TODO: FIXME
            //            Text("[Dev] Results: \(vm.posts.count) || LA: \(vm.lastAppearedIndex) || MRR: \(vm.mostRecentReadIndex)")
            //            Text("vm.id: \(vm.id)")
            //            Text("vm.listState.listId: \(vm.listState.listId)")
            //            Text("Following: \(vm.pubkeys.count.description)")
            //            Text("Explore: \(ns.explorePubkeys.count.description)")
            
            if vmState.vPosts.count > 0 {
                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach(vmState.vPosts) { vPost in
                                NoteRow(vPost:vPost)
                                    .id(vPost.id)
                                    .listRowInsets(EdgeInsets())
                                    .onBecomingVisible {
                                        guard vmState.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                        guard vmState.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                        guard vmState.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
//                                        lastAppeared = vPost.event
                                        vm.lastAppearedSubject.send(vPost.event)
//                                        vm.onPostAppeared(vPost.event)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button { ns.toggleBookmark(vPost.event) //TODO:FIXME
                                        } label: { Image(systemName: "bookmark") }.tint(.orange)

                                    }
//                                    .border(lastAppeared?.id == vPost.id ? .green : .white)
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
                                vm.didReachEnd()
                            }
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    .id(scrollResetId)
                    .listStyle(.plain)
                    .onAppear {
                        guard vmState.state == .AWAITING_RESTORE_SCROLL else { return }
                        print ("🟢🟢 List (count>0) onAppear -- restoreToScrollPos")
                        restoreScrollPosition(proxy: proxy)
                    }
                    .onReceive(receiveNotification(.shouldScrollToLast)) { _ in
                        guard vmState.viewIsVisible else { return }
                        scrollResetId += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(END_OF_LIST)
                                vmState.state = .SCROLLED_TO_END
                            }
                        }
                    }
//                    .onChange(of: vm.vPosts.count, perform: { newCount in
//                        guard vm.viewIsVisible else { return }
//                        guard vm.state == .AWAITING_SCROLL else { return }
//                        guard vPosts.count == 0 && newCount > 0 else { return } // FIRST LOAD. FROM 0 TO >0
//
//                        restoreScrollPosition(proxy: proxy)
//                    })
                    //                .onChange(of: vm.pubkey) { newValue in // TODO: FIXME
                    //                    vm.state = .SWITCHING_ACCOUNT
                    //                    print("🟢🟢 SWITCHING ACCOUNT TO: \(newValue)")
                    //                    restoreScrollPosition(proxy: proxy)
                    //                }
                }
                .onChange(of: selectedSubTab) { selectedTab in
                    vmState.viewIsVisible = selectedTab == vm.id
                }
            }
            else {
                CenteredProgressView()
            }
        }
        .onAppear {
            vmState.viewIsVisible = selectedSubTab == vm.id
        }
        .onDisappear {
            vmState.viewIsVisible = false
        }
    }
    
    func restoreScrollPosition(proxy:ScrollViewProxy) {
        print("🟢🟢 restoreScrollPosition:  \(vmState.state.rawValue) ")
//        guard vm.state == .AWAITING_RESTORE_SCROLL || vm.state == .SWITCHING_ACCOUNT else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
        guard vmState.state == .AWAITING_RESTORE_SCROLL else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
        if let lastAppeared = self.vmState.restoreScrollTo {
            print("🟢🟢🟢 proxy.scrollTo \(lastAppeared.id)  --- \(vmState.vPosts.count)  ")
            proxy.scrollTo(lastAppeared.id, anchor: .center) // self.vmState.restoreScrollToAnchor
            vmState.state = .COMPLETED_RESTORED_FETCH_WITH_SCROLL
            
//            // TODO: DO WE STILL NEED THESE DELAYS?? LETS TEST...
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                print("🟢🟢🟢🟢")
//                //                proxy.scrollTo(lastAppeared.id, anchor: vm.lastAppearedAnchorSubject.value == "TOP" ? .top : .bottom)
//
//                if (vmState.vPosts.map { $0.id } .contains(lastAppeared.id)) {
//                    proxy.scrollTo(lastAppeared.id, anchor: .bottom)
//                }
//                else {
//                    print("🔴🔴🔴🔴 YO WHERE IS THE POST YO I CANT SCROLL ON \(vm.id)")
//                    print("🔴🔴🔴🔴 LOOKING FOR \(lastAppeared.id), vPosts: \(vmState.vPosts.count) ")
//                }
//
//            }
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
//                print("🟢🟢🟢🟢🟢")
//                vmState.state = .COMPLETED_RESTORED_FETCH_WITH_SCROLL
//            }
        }
        else {
            print("🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢")
            vmState.state = .COMPLETED_FIRST_FETCH
        }
    }
}

//struct ListViewBackup: View {
//    enum ListType {
//        case account
//        case explore
//        case list
//    }
//    //    @AppStorage("firstTimeCompleted") var firstTimeCompleted = false // TODO: FIND SOLUTION FOR THIS
//    //    @AppStorage("selected_subtab") var selectedSubTab = "Following"
//    @EnvironmentObject var ns:NosturState
//    @Namespace var END_OF_LIST
//    @State var scrollResetId = 0
//    let vPosts:[VPost]
//    @ObservedObject var vm:LVM
//
//    var body: some View {
//        let _ = Self._printChanges()
//        VStack {
//            Text("posts: \(vPosts.count)")
//            Text("state: \(vm.state.rawValue)")
//                .onTapGesture {
//                    vm.state = .COMPLETED_RESTORED_FETCH_WITH_SCROLL
//                }
//            //            if ((selectedSubTab != "Explore") && (ns.account?.follows?.count ?? 0) == 0) && ((ns.account?.publicKey ?? "NOACCOUNT") != NosturState.GUEST_ACCOUNT_PUBKEY) {
//            //                Text("You are not following anyone yet, visit the explore tab and follow some people")
//            //                    .multilineTextAlignment(.center)
//            //                    .padding(/*@START_MENU_TOKEN@*/.all, 30.0/*@END_MENU_TOKEN@*/)
//            //
//            //                Button {
//            //                    selectedSubTab = "Explore"
//            //                } label: {
//            //                    Text("Explore")
//            //                }.buttonStyle(.borderedProminent)
//            //            }
//
//            //            Text("State: \(vm.state.rawValue)").lineLimit(1) // TODO: FIXME
//            //            Text("[Dev] Results: \(vm.posts.count) || LA: \(vm.lastAppearedIndex) || MRR: \(vm.mostRecentReadIndex)")
//            //            Text("vm.id: \(vm.id)")
//            //            Text("vm.listState.listId: \(vm.listState.listId)")
//            //            Text("Following: \(vm.pubkeys.count.description)")
//            //            Text("Explore: \(ns.explorePubkeys.count.description)")
//
//            if vPosts.count > 0 {
//                ScrollViewReader { proxy in
//                    List {
//                        Section {
//                            ForEach(vPosts) { vPost in
//                                NoteRow(vPost:vPost)
//                                    .id(vPost.id)
//                                    .listRowInsets(EdgeInsets())
//                                    .onBecomingVisible { vm.onPostAppeared(vPost) }
//                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
//                                        Button { ns.toggleBookmark(vPost.event) //TODO:FIXME
//                                        } label: { Image(systemName: "bookmark") }.tint(.orange)
//
//                                    }
//                                    .border(vm.lastAppearedSubject.value?.id == vPost.id ? .green : .clear)
//                            }
//                        }
//                        Section {
//                            HStack {
//                                Spacer()
//                                Rectangle().frame(width: 300, height: 1)
//                                Spacer()
//                            }
//                            .id(END_OF_LIST)
//                            .onBecomingVisible {
//                                vm.didReachEnd()
//                            }
//                            .listRowInsets(EdgeInsets())
//                        }
//                    }
//                    .id(scrollResetId)
//                    .listStyle(.plain)
//                    .onAppear {
//                        guard vm.state == .AWAITING_RESTORE_SCROLL else { return }
//                        restoreScrollPosition(proxy: proxy)
//                    }
//                    //                .onReceive(receiveNotification(.shouldScrollToLast)) { _ in
//                    //                    guard vm.viewIsVisible else { return }
//                    //                    scrollResetId += 1
//                    //                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                    //                        withAnimation {
//                    //                            proxy.scrollTo(END_OF_LIST)
//                    //                            vm.state = .SCROLLED_TO_END
//                    //                        }
//                    //                    }
//                    //                }
//                    .onChange(of: vPosts.count, perform: { newCount in
//                        guard vm.viewIsVisible else { return }
//                        guard vm.state == .AWAITING_SCROLL else { return }
//                        guard vPosts.count == 0 && newCount > 0 else { return } // FIRST LOAD. FROM 0 TO >0
//
//                        restoreScrollPosition(proxy: proxy)
//                    })
//                    //                .onChange(of: vm.pubkey) { newValue in // TODO: FIXME
//                    //                    vm.state = .SWITCHING_ACCOUNT
//                    //                    print("🟢🟢 SWITCHING ACCOUNT TO: \(newValue)")
//                    //                    restoreScrollPosition(proxy: proxy)
//                    //                }
//                }
//            }
//            else {
//                CenteredProgressView()
//            }
//        }
//    }
//
//    func restoreScrollPosition(proxy:ScrollViewProxy) {
//        print("🟢🟢 restoreScrollPosition:  \(vm.state.rawValue) ")
//        guard vm.state == .AWAITING_RESTORE_SCROLL || vm.state == .SWITCHING_ACCOUNT else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
//        print("🟢🟢 restoreScrollPosition PASSED THE GUARD:  \(vm.state.rawValue) ")
//        if let lastAppeared = self.vm.lastAppeared {
//            print("🟢🟢🟢")
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                print("🟢🟢🟢🟢")
//                //                proxy.scrollTo(lastAppeared.id, anchor: vm.lastAppearedAnchorSubject.value == "TOP" ? .top : .bottom)
//
//                if (vPosts.map { $0.id } .contains(lastAppeared.id)) {
//                    proxy.scrollTo(lastAppeared.id, anchor: .bottom)
//                }
//                else {
//                    print("🔴🔴🔴🔴 YO WHERE IS THE POST YO I CANT SCROLL ON \(vm.id)")
//                    print("🔴🔴🔴🔴 LOOKING FOR \(lastAppeared.id), vPosts: \(vPosts.count) ")
//                }
//
//            }
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
//                print("🟢🟢🟢🟢🟢")
//                vm.state = .COMPLETED_RESTORED_FETCH_WITH_SCROLL
//            }
//        }
//        else {
//            print("🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢")
//            vm.state = .COMPLETED_FIRST_FETCH
//        }
//    }
//}
