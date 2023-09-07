//
//  Hot.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI

struct Hot: View {
    @EnvironmentObject var theme:Theme
    @ObservedObject var hotVM:HotViewModel
    
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Hot"
    
    var body: some View {
        ScrollView {
            if hotVM.hotPosts.isEmpty {
                CenteredProgressView()
            }
            else {
                LazyVStack(spacing: 10) {
                    ForEach(hotVM.hotPosts) { post in
                        Box(nrPost: post) {
                            PostOrThread(nrPost: post)
                        }
                    }
                }
            }
        }
        .background(theme.listBackground)
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
            hotVM.load()
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Hot" else { return }
            hotVM.load() // didLoad is checked in .load() so no need here
        }
    }
}

struct Hot_Previews: PreviewProvider {
    static var previews: some View {
        Hot(hotVM: HotViewModel())
            .environmentObject(Theme.default)
    }
}


