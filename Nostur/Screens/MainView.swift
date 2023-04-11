//
//  MainView.swift - When switching account, removes all views from navigation stack and start fresh
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI

struct MainView: View {
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var navPath = NavigationPath()
    @State var account:Account?
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            if let account {
                FollowingAndExplore(account: account)
                    .withNavigationDestinations()
            }
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
            let account = notification.object as! Account
            guard self.account != account else { return }
            self.account = account
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
