//
//  Gallery.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2023.
//

import SwiftUI

struct Gallery: View {
    @EnvironmentObject var theme:Theme
    @ObservedObject var vm:GalleryViewModel
    
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Hot"
    
    @Namespace var top
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if vm.items.isEmpty {
                    CenteredProgressView()
                }
                else {
                    Color.clear.frame(height: 1).id(top)
                    LazyVStack(spacing: 10) {
                        ForEach(vm.items) { item in
                            
                        }
                    }
                    .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                        guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
                        withAnimation {
                            proxy.scrollTo(top)
                        }
                    }
                    .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                        guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
                        withAnimation {
                            proxy.scrollTo(top)
                        }
                    }
                    .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                        vm.reload()
                    }
                }
            }
        }
        .background(theme.listBackground)
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
            vm.load()
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
            vm.hotPosts = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { // Reconnect delay
                vm.load()
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Gallery" else { return }
            vm.load() // didLoad is checked in .load() so no need here
        }
    }
}

struct Hot_Previews: PreviewProvider {
    static var previews: some View {
        Gallery(vm: GalleryViewModel())
            .environmentObject(Theme.default)
    }
}


