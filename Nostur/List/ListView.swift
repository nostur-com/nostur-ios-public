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
    @State var needsScrollToTop = false
    @State var needsScrollToIndex:Int? = nil
    @State var needsRefresh = false
    @State var needsFullReload = false
    
    let vm:LVM
    @ObservedObject var vmState:LVMState
    @ObservedObject var settings:SettingsStore = .shared
    
    init(vm: LVM) {
        self.vm = vm
        self.vmState = vm.lvmState
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            if vmState.vPostLeafs.count > 0 {
//                Text("\(vmState.state.rawValue) | vPosts: \(vmState.vPostLeafs.count) | threadValue: \(vmState.vPostLeafs.reduce(0, { $0 + $1.threadPostsCount } ) )")
                
                ZStack {
                    SmoothList(needsRefresh: $needsRefresh,
                               needsFullReload: $needsFullReload,
                               needsScrollToTop: $needsScrollToTop,
                               needsScrollToIndex: $needsScrollToIndex,
                               data: $vmState.vPostLeafs,
                               autoScroll: $settings.autoScroll,
                               fullWidthImages: $settings.fullWidthImages,
                               onRowAppeared: { (_, _, vPost) in
                        guard vmState.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                        guard vmState.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                        guard vmState.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                        //                        print("\(vPost.id) index: \(vmState.vPostLeafs.firstIndex(of: vPost) ?? -1)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            vm.lastAppearedSubject.send(vPost.event)
                        }
                    },
                               onFinishedScrolling: { isAtTop in
                        guard isAtTop != vmState.isAtTop else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            self.vmState.isAtTop = isAtTop
                            
                        }
                    })
                    .onChange(of: vmState.vPostLeafs) { _ in
                        needsRefresh = true
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            self.needsScrollToIndex = getRestoreScrollIndex()
                            self.needsRefresh = true
                        }
                    }
//                    .background(Color.indigo)
                    VStack {
                        Spacer()
                        ProcessingStatus()
                            .opacity(0.85)
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToRecent)) { _ in
                    needsScrollToTop = true
                }
                .onChange(of: selectedSubTab) { selectedTab in
                    vmState.viewIsVisible = selectedTab == vm.id
                }
                .onChange(of: settings.fullWidthImages) { newValue in
                    needsFullReload = true
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
        //        .background(Color("ListBackground"))
    }
    
    func getRestoreScrollIndex() -> Int? {
        //        print("🟢🟢 restoreScrollPosition:  \(vmState.state.rawValue) ")
        //        guard vm.state == .AWAITING_RESTORE_SCROLL || vm.state == .SWITCHING_ACCOUNT else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
        guard vmState.state == .AWAITING_RESTORE_SCROLL else { return nil } // Onlyif we didn't restore yet (so not like nav to post and back)
        if let lastAppeared = self.vmState.restoreScrollTo {
            //            print("🟢🟢🟢 proxy.scrollTo \(lastAppeared.id)  --- \(vmState.vPostLeafs.count)  ")
            
            //            print(self.vmState.vPosts[safe: 0]?.items.flatMap { [$0.id] + $0.parentPosts.map { $0.id } })
            vmState.state = .COMPLETED_RESTORED_FETCH_WITH_SCROLL
            if let index = vmState.vPostLeafs.firstIndex(where: { $0.id == lastAppeared.id }) {
//                                print("🟢🟢🟢 should scroll to leaf index: \(index)")
                return index
            }
            // or maybe the leaf is now a parent?
            else if let index = vmState.vPostLeafs.firstIndex(where: { $0.parentPosts.map { $0.id }.contains(lastAppeared.id) }) {
                //            else if let index = vmState.vPostLeafs.firstIndex(where: { $0.parentPosts.map { $0.id }.contains(lastAppeared.id) }) {
//                                print("🟢🟢🟢 should scroll to leaf-to-parent index: \(index)")
                return index
            }
            else {
//                                print("🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢 dunno where to scroll to 1")
                return nil
            }
        }
        else {
//                        print("🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢 dunno where to scroll to 2")
            vmState.state = .COMPLETED_FIRST_FETCH
            return nil
            
        }
    }
}
