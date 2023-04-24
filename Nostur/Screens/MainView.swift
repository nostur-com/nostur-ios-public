//
//  MainView.swift - When switching account, removes all views from navigation stack and start fresh
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI

struct MainView: View {
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @State var navPath = NavigationPath()
    @State var account:Account?
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            if let account {
                FollowingAndExplore(account: account)
                    .withNavigationDestinations()
                    .overlay(alignment: .bottomTrailing) {
                        NewNoteButton(showingNewNote: $showingNewNote)
                            .padding([.top, .leading, .bottom], 10)
                            .padding([.trailing], 25)
                    }
                    .overlay(alignment: .bottom) {
                        ProcessingStatus()
                            .opacity(0.85)
                            .padding(.bottom, 10)
                    }
                    .sheet(isPresented: $showingNewNote) {
                        NavigationStack {
                            NewNote(noteCancellationId: $noteCancellationId)
                        }
                    }
            }
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
            let account = notification.object as! Account
            guard self.account != account else { return }
            self.account = account
            if selectedSubTab != "Following" {
                selectedSubTab = "Following"
            }
        }
        .onAppear {
            guard let account = NosturState.shared.account else { return }
            self.account = account
        }
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            guard !IS_IPAD else { return }
            guard selectedTab == "Main" else { return }
            navPath.append(destination.destination)
        }
        .onReceive(receiveNotification(.navigateToOnMain)) { notification in
            let destination = notification.object as! NavigationDestination
            navPath.append(destination.destination)
        }
        .onReceive(receiveNotification(.clearNavigation)) { notification in
            navPath.removeLast(navPath.count)
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
//        if let account = PreviewFetcher.fetchAccount() {
//            MainView(account: account)
            MainView()
                .withPreviewEnvironment()
//        }
    }
}
