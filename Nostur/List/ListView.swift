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
    @State var scrollToTop = false
    @State var scrollToIndex:Int? = nil
    @State var lastAppearedId:String? = nil
    
    let vm:LVM
    @ObservedObject var vmState:LVMState
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            if vmState.vPostLeafs.count > 0 {
//                Text("\(vmState.state.rawValue) | vPosts: \(vmState.vPostLeafs.count) | threadValue: \(vmState.vPostLeafs.reduce(0, { $0 + $1.threadPostsCount } ) )")
                
                ZStack {
                    RagiSmoothList(
                        data: $vmState.vPosts,
                        listConfiguration: .init(separator: .init(isVisible: false)),
                        cellContent: { vPost in
                            makeCellContent(vPost: vPost)
                        }
                    )
                    .scrollToTop($scrollToTop)
                    .scrollToIndex($scrollToIndex)
                    .onRowAppeared { _, _, vPost in
                        guard vmState.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                        guard vmState.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                        guard vmState.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                        vm.lastAppearedSubject.send(vPost.event)
                    }
                    VStack {
                        ProcessingStatus()
                        Spacer()
                    }
                }
                .onAppear {
                    guard vmState.state == .AWAITING_RESTORE_SCROLL else { return }
                    print ("🟢🟢 List (count>0) onAppear -- restoreToScrollPos")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        self.restoreScrollPosition()
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToRecent)) { _ in
                    guard vmState.viewIsVisible else { return }
                    scrollToTop = true
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
    
    private func makeCellContent(vPost: VPost) -> some View {
        VStack {
            ForEach(vPost.parentPosts.indices, id:\.self) { index in
//                if index == 0 && vPost.parentPosts[index].event.replyToId != nil {
//                    Button("Show this thread") {
//                        navigateTo(vPost.parentPosts[index])
//                    }.padding(.top, 10)
//                }
                NoteRow(vPost: vPost.parentPosts[index], connect: vPost.parentPosts[index].event.replyToId != nil || index > 0 ? .both : .bottom)
                    .background(Color.systemBackground)
                    .onTapGesture {
                        navigateTo(vPost)
                    }
            }
//            if vPost.event.replyToId != nil && vPost.parentPosts.count == 0 {
//                Button("Show this thread") {
//                    navigateTo(vPost)
//                }.padding(.top, 10)
//            }
            NoteRow(vPost: vPost, connect: vPost.event.replyToId != nil ? .top : nil)
            .background(Color.systemBackground)
            .onTapGesture {
                navigateTo(vPost)
            }
        }
        .border(lastAppearedId == vPost.id ? Color.blue : Color.clear)
        .boxShadow()
        .padding()
    }
    
    private func xmakeCellContent(vPost: VPost) -> some View {
        PostOrThread(vPost: vPost)
            .onBecomingVisible {
                guard vmState.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                guard vmState.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                guard vmState.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                //                                        lastAppearedId = vPost.id
                vm.lastAppearedSubject.send(vPost.event)
                //                                        vm.onPostAppeared(vPost.event)
            }
            .boxShadow()
            .padding()
    }
    
    struct CellButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(configuration.isPressed ? Color.orange : nil)
        }
    }
    
    func restoreScrollPosition() {
//        print("🟢🟢 restoreScrollPosition:  \(vmState.state.rawValue) ")
        //        guard vm.state == .AWAITING_RESTORE_SCROLL || vm.state == .SWITCHING_ACCOUNT else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
        guard vmState.state == .AWAITING_RESTORE_SCROLL else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
        if let lastAppeared = self.vmState.restoreScrollTo {
//            print("🟢🟢🟢 proxy.scrollTo \(lastAppeared.id)  --- \(vmState.vPostLeafs.count)  ")
            if let index = vmState.vPostLeafs.firstIndex(where: { $0.id == lastAppeared.id }) {
//                print("🟢🟢🟢 should scroll to leaf index: \(index)")
                scrollToIndex = index
            }
            // or maybe the leaf is now a parent?
            else if let index = vmState.vPostLeafs.firstIndex(where: { $0.parentPosts.map { $0.id }.contains(lastAppeared.id) }) {
//                print("🟢🟢🟢 should scroll to leaf-to-parent index: \(index)")
                scrollToIndex = index
            }
            vmState.state = .COMPLETED_RESTORED_FETCH_WITH_SCROLL
        }
        else {
//            print("🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢")
            vmState.state = .COMPLETED_FIRST_FETCH
        }
    }
}
