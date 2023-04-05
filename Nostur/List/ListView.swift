//
//  ListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

struct ListView: View {
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @EnvironmentObject var ns:NosturState
    @Namespace var END_OF_LIST
    @State var scrollResetId = 0

    let vm:LVM
    @ObservedObject var vmState:LVMState
    
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollViewReader { proxy in
            if vmState.vPosts.count > 0 {
//                Text("vPosts: \(vmState.vPosts.count) | threadValue: \(vmState.vPosts.reduce(0, { $0 + $1.threadPostsCount } ) )")
                ScrollView {
                    LazyVStack {
                        ForEach(vmState.vPosts) { vPost in
                            PostOrThread(vPost: vPost)
                                .padding(5)
                                .background(
                                    Rectangle().foregroundColor(Color.systemBackground)
                                        .shadow(color: Color.gray.opacity(0.4), radius: 5, x: 0, y: 0)
                                        .padding(5)
                                )
                            //                                NoteRow(vPost:vPost)
                            //                                    .equatable()
                                .id(vPost.id)
                                .onBecomingVisible {
                                    guard vmState.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                    guard vmState.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                    guard vmState.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                                    //                                        lastAppearedId = vPost.id
                                    vm.lastAppearedSubject.send(vPost.event)
                                    //                                        vm.onPostAppeared(vPost.event)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button { ns.toggleBookmark(vPost.event)
                                    } label: { Image(systemName: "bookmark") }.tint(.orange)
                                    
                                }
                            //                                    .border(lastAppeared?.id == vPost.id ? .green : .white)
                        }
                    }
                    VStack {
                        ZStack {
                            HStack {
                                Spacer()
                                Rectangle().frame(width: 300, height: 1)
                                    .id(END_OF_LIST)
                                    .onBecomingVisible {
                                        vm.didReachEnd()
                                    }
                                Spacer()
                            }
                            ProcessingStatus()
                        }
                        .frame(height: 70)
                    }
                    .frame(height: 70)
                    .fixedSize()
                }
//                .padding(.top, 1)
                .onAppear {
                    guard vmState.state == .AWAITING_RESTORE_SCROLL else { return }
                    print ("🟢🟢 List (count>0) onAppear -- restoreToScrollPos")
                    restoreScrollPosition(proxy: proxy)
                }
                .onAppear {
                    // FIRST FETCH?? DONT KNOW WHERE TO RESTORE?? JUST GO TO NEWEST!
                    guard vmState.state == .COMPLETED_FIRST_FETCH else { return }
                    guard vmState.viewIsVisible else { return }
                    //                    scrollResetId += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            if let last = vmState.vPosts.last {
                                proxy.scrollTo(last.id)
                                //                                proxy.scrollTo(END_OF_LIST)
                                vmState.state = .SCROLLED_TO_END
                            }
                        }
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToLast)) { _ in
                    guard vmState.viewIsVisible else { return }
                    //                        scrollResetId += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            if let last = vmState.vPosts.last {
                                proxy.scrollTo(last.id)
                                vmState.state = .SCROLLED_TO_END
                            }
                            else {
                                proxy.scrollTo(END_OF_LIST)
                                vmState.state = .SCROLLED_TO_END
                            }
                        }
                    }
                }
                .onChange(of: selectedSubTab) { selectedTab in
                    vmState.viewIsVisible = selectedTab == vm.id
                }
            }
            else {
                if (selectedSubTab == "Following" && ns.followingPublicKeys.count <= 1) {
                    Text("You are not following anyone yet, visit the explore tab and follow some people")
                        .multilineTextAlignment(.center)
                        .padding(.all, 30.0)
                    
                    Button {
                        selectedSubTab = "Explore"
                    } label: {
                        Text("Explore")
                    }.buttonStyle(.borderedProminent)
                }
                else {
                    CenteredProgressView()
                }
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
