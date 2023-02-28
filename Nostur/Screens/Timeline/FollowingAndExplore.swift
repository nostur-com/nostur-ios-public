//
//  FollowingAndGlobal.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI

struct FollowingAndExplore: View {
    
    @EnvironmentObject var nav:NavigationModel
//    @StateObject var followingModel = TimelineModel(id:"Following")
//    @StateObject var exploreModel = TimelineModel(id:"Explore")
    
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
            ZStack {
                NavigationStack(path: $nav.timelinePath) {
                    FollowingStateIsolation()
//                        .environmentObject(followingModel)
                        .frame(maxWidth: 600)
                        .withNavigationDestinations()
                }
                .opacity(nav.selectedSubTab == "Following" ? 1 : 0)
                NavigationStack(path: $nav.explorePath) {
                    ExploreStateIsolation()
//                        .environmentObject(exploreModel)
                        .frame(maxWidth: 600)
                        .withNavigationDestinations()
                }
                .opacity(nav.selectedSubTab == "Explore" ? 1 : 0)
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

struct FollowingAndExplore_Previews: PreviewProvider {
    static var previews: some View {
        FollowingAndExplore()
            .withPreviewEnvironment()
    }
}
