//
//  FollowingAndGlobal.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI

struct FollowingAndExplore: View {
    
    @EnvironmentObject var nav:NavigationModel
    @StateObject var followingModel = TimelineModel()
    @StateObject var exploreModel = TimelineModel()
    
    var body: some View {
        VStack {
            HStack {
                TabButton(action: {
//                    withAnimation {
                        nav.selectedSubTab = "Following"
//                    }
                }, title: "Following", selected: nav.selectedSubTab == "Following")
                
                TabButton(action: {
//                    withAnimation {
                        nav.selectedSubTab = "Explore"
//                    }
                }, title: "Explore", selected: nav.selectedSubTab == "Explore")
            }
            switch nav.selectedSubTab {
                case "Following":
                    NavigationStack(path: $nav.timelinePath) {
                        FollowingStateIsolation()
                            .environmentObject(followingModel)
                            .frame(maxWidth: 600)
                            .withNavigationDestinations()
                    }
                case "Explore":
                    NavigationStack(path: $nav.explorePath) {
                        ExploreStateIsolation()
                            .environmentObject(exploreModel)
                            .frame(maxWidth: 600)
                            .withNavigationDestinations()
                    }
                default:
                    EmptyView()
            }
            Spacer()
        }
        .safeAreaInset(edge: .top) {
            AppTopBar()
                .padding(5)
                .background(Color("BackgroundColor").opacity(0.9))
        }
    }
}

struct FollowingAndGlobal_Previews: PreviewProvider {
    static var previews: some View {
        FollowingAndExplore()
            .withPreviewEnvironment()
    }
}
