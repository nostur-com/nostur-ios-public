//
//  ListViewContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/04/2023.
//

import SwiftUI

struct ListViewContainer: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    public let vm: LVM
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        SmoothTable(lvm: vm, dim: dim, themes: themes)
//            .withoutAnimation()
            .overlay(alignment: .topTrailing) {
                ListUnreadCounter(vm: vm, theme: themes.theme)
                    .padding(.trailing, 10)
                    .padding(.top, 5)
            }
            .overlay {
                IsolatedLVMLoadingView(vm: vm)
            }
    }
}

struct IsolatedLVMLoadingView: View {
    @ObservedObject var vm:LVM
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        if vm.posts.value.isEmpty {
            CenteredProgressView()
        }
    }
}

import NavigationBackport

struct ListViewContainerTester: View {
    @EnvironmentObject var la: LoggedInAccount
    
    var body: some View {
        NBNavigationStack {
            ListViewContainer(vm: LVMManager.shared.followingLVM(forAccount: la.account))
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
