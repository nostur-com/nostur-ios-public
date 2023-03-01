//
//  FollowingAndGlobal.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI

struct FollowingAndExplore: View {
    
    //    @EnvironmentObject var nav:NavigationModel
    //    @State var timelinePath = NavigationPath()
    //    @State var explorePath = NavigationPath()
    @AppStorage("selected_subtab") var selectedSubTab = "Explore"
    
    var body: some View {
        VStack {
            HStack {
                TabButton(action: {
                    //                    withAnimation {
                    selectedSubTab = "Following"
                    //                    }
                }, title: "Following", selected: selectedSubTab == "Following")
                
                TabButton(action: {
                    //                    withAnimation {
                    selectedSubTab = "Explore"
                    //                    }
                }, title: "Explore", selected: selectedSubTab == "Explore")
            }
            ZStack {
                //                NavigationStack(path: $timelinePath) {
                FollowingStateIsolation()
                //                        .environmentObject(followingModel)
                    .frame(maxWidth: 600)
                //                        .withNavigationDestinations()
                //                }
                    .opacity(selectedSubTab == "Following" ? 1 : 0)
                //                NavigationStack(path: $explorePath) {
                ExploreStateIsolation()
                //                        .environmentObject(exploreModel)
                    .frame(maxWidth: 600)
                //                        .withNavigationDestinations()
                //                }
                    .opacity(selectedSubTab == "Explore" ? 1 : 0)
            }
            Spacer()
        }
        .navigationTitle(selectedSubTab)
        .navigationBarHidden(true)
//        .navigationBarTitleDisplayMode(.inline)
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
