//
//  ListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

struct ListView: View {
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @AppStorage("selected_listId") var selectedListId = ""
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var dim:DIMENSIONS
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
        //        let _ = Self._printChanges()
        VStack(spacing: 0) {
//            Text("leafs: \(vmState.nrPostLeafs.count)")
//            if 1 == 2 {
//                SmoothListAttempt382(nrPosts: vmState.nrPostLeafs)
//            }
//            else if 1 == 1 && vmState.nrPostLeafs.count > 0 {
            if vmState.nrPostLeafs.count > 0 {
                //                Text("\(vmState.state.rawValue) | nrPosts: \(vmState.nrPostLeafs.count) | threadValue: \(vmState.nrPostLeafs.reduce(0, { $0 + $1.threadPostsCount } ) )")
                SmoothList(needsRefresh: $needsRefresh,
                           needsFullReload: $needsFullReload,
                           needsScrollToTop: $needsScrollToTop,
                           needsScrollToIndex: $needsScrollToIndex,
                           data: $vmState.nrPostLeafs,
                           autoScroll: $settings.autoScroll,
                           fullWidthImages: $settings.fullWidthImages,
                           dim: dim,
                           onRowAppeared: { (sectionIndex, rowIndex) in
                    guard vmState.state != .AWAITING_RESTORE_SCROLL else { return }
                    guard vmState.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                    guard vmState.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                    guard vmState.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                    //                        print("\(nrPost.id) index: \(vmState.nrPostLeafs.firstIndex(of: nrPost) ?? -1)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastAppearedId = vmState.nrPostLeafs[safe: rowIndex]?.id {
                            vm.lastAppearedSubject.send(lastAppearedId)
                        }
                    }
                },
                           onFinishedScrolling: { (isAtTop, indexPaths) in
                    guard vmState.state != .AWAITING_RESTORE_SCROLL else { return }
                    guard vmState.state != .AWAITING_FIRST_FETCH else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                    guard vmState.state != .AWAITING_SCROLL else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                    guard vmState.state != .SWITCHING_ACCOUNT else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
                    //                        print("\(nrPost.id) index: \(vmState.nrPostLeafs.firstIndex(of: nrPost) ?? -1)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let firstIndex = indexPaths.min(by: { $0.row < $1.row }) {
                            if firstIndex.row < 1 { // not sure why just index 0 doesn't work 1% of the time
                                vm.lvmCounter.count = 0
                            }
                            
                            if let lastAppearedId = vmState.nrPostLeafs[safe: firstIndex.row]?.id {
                                vm.lastAppearedSubject.send(lastAppearedId)
                            }
                        }
                        
                        guard isAtTop != vmState.isAtTop else { return }
                        self.vmState.isAtTop = isAtTop
                    }
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
//                        vm.lastAppearedSubject.send(nrPost.id)
//                    }
//
                    
                    
//                    guard isAtTop != vmState.isAtTop else { return }
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                        self.vmState.isAtTop = isAtTop
//                        if indexPaths.contains(where: { $0.row == 0 }) {
//                            vm.lvmCounter.count = 0
//                        }
//                    }
                })
                .onChange(of: vmState.nrPostLeafs) { _ in
                    needsRefresh = true
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.needsScrollToIndex = getRestoreScrollIndex()
                        self.needsRefresh = true
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToRecent)) { _ in
                    needsScrollToTop = true
                }
                .onChange(of: selectedSubTab) { selectedTab in
                    vmState.viewIsVisible = vm.id != "List" && (selectedTab == vm.id)
                }
                .onChange(of: selectedListId) { selectedListId in
                    vmState.viewIsVisible = vm.id == "List" && (selectedListId == vm.subscriptionId)
                }
                .onChange(of: settings.fullWidthImages) { newValue in
                    needsFullReload = true
                }
                .onChange(of: settings.animatedPFPenabled) { newValue in
                    needsFullReload = true
                }
            }
            else {
                if (selectedSubTab == "Following" && ns.followingPublicKeys.count <= 1) {
                    VStack {
                        Spacer()
                        Text("You are not following anyone yet, visit the explore tab and follow some people")
                            .multilineTextAlignment(.center)
                            .padding(.all, 30.0)
                        
                        Button {
                            selectedSubTab = "Explore"
                        } label: {
                            Text("Explore")
                        }.buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }
                else {
                    CenteredProgressView()
                }
            }
        }
        .onAppear {
            //            vmState.viewIsVisible = (selectedSubTab != "List" && selectedSubTab == vm.id) || (selectedSubTab == "List" && selectedListId == vm.subscriptionId)
            vmState.viewIsVisible = true
        }
        .onDisappear {
            vmState.viewIsVisible = false
        }
        //        .background(Color("ListBackground"))
    }
    
    func getRestoreScrollIndex() -> Int? {
        print("🟢🟢 restoreScrollPosition:  \(vmState.state.rawValue) ")
        //        guard vm.state == .AWAITING_RESTORE_SCROLL || vm.state == .SWITCHING_ACCOUNT else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
        guard vmState.state == .AWAITING_RESTORE_SCROLL else { return nil } // Onlyif we didn't restore yet (so not like nav to post and back)
        if let lastAppearedId = self.vmState.restoreScrollToId {
            print("🟢🟢🟢 proxy.scrollTo \(lastAppearedId)  --- \(vmState.nrPostLeafs.count)  ")
            
            //            print(self.vmState.nrPosts[safe: 0]?.items.flatMap { [$0.id] + $0.parentPosts.map { $0.id } })
            vmState.state = .COMPLETED_RESTORED_FETCH_WITH_SCROLL
            if let index = vmState.nrPostLeafs.firstIndex(where: { $0.id == lastAppearedId }) {
                print("🟢🟢🟢 should scroll to leaf index: \(index)")
                return index
            }
            // or maybe the leaf is now a parent?
            else if let index = vmState.nrPostLeafs.firstIndex(where: { $0.parentPosts.map { $0.id }.contains(lastAppearedId) }) {
                //            else if let index = vmState.nrPostLeafs.firstIndex(where: { $0.parentPosts.map { $0.id }.contains(lastAppeared.id) }) {
                print("🟢🟢🟢 should scroll to leaf-to-parent index: \(index)")
                return index
            }
            else {
                print("🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢 dunno where to scroll to 1")
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
