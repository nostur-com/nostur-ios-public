//
//  ListViewContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/04/2023.
//

import SwiftUI

struct ListViewContainer: View {
    @EnvironmentObject var theme:Theme
    @EnvironmentObject var dim:DIMENSIONS
    @ObservedObject var vm:LVM
    
    var body: some View {
        SmoothList(lvm: vm, dim: dim, theme:theme)
            .overlay(alignment: .topTrailing) {
                ListUnreadCounter(vm: vm)
                    .padding(.trailing, 10)
                    .padding(.top, 5)
            }
            .overlay {
                if vm.state == .INIT || vm.nrPostLeafs.isEmpty {
                    CenteredProgressView()
                }
            }
    }
}

struct ListViewContainerTester: View {
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        if let account = ns.account {
            NavigationStack {
                ListViewContainer(vm: LVMManager.shared.followingLVM(forAccount: account))
            }
        }
    }
}


struct Previews_ListViewContainer_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            ListViewContainerTester()
        }
    }
}
