//
//  MainPlayerPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//


import SwiftUI

let CONTROLS_HEIGHT: CGFloat = 36.0

@available(iOS 18.0, *)
#Preview("Integrated media player bar") {
    @Previewable @State var offset: CGFloat = 69.0
    @Previewable @ObservedObject var apm: AnyPlayerModel = .shared
    VStack {
        TabView {
            GeometryReader { geometry in
                VStack {
                    HStack {
                        Button("Landscape") {
                            Task {
                                await AnyPlayerModel
                                    .shared
                                    .loadVideo(
                                        url: "https://static.vecteezy.com/system/resources/previews/016/465/804/mp4/silhouettes-flock-of-seagulls-over-the-sea-during-amazing-sky-video.mp4",
        //                                availableViewModes: [.fullscreen, .overlay, .detailstream])
                                        availableViewModes: [.fullscreen, .overlay])
                            }
                        }
                        
                        Button("Portrait") {
                            Task {
                                await AnyPlayerModel
                                    .shared
                                    .loadVideo(
                                        url: "https://m.primal.net/OErQ.mov",
        //                                availableViewModes: [.fullscreen, .overlay, .detailstream])
                                        availableViewModes: [.fullscreen, .overlay])
                            }
                        }
                        
                        Button("Other") {
                            Task {
                                await AnyPlayerModel
                                    .shared
                                    .loadVideo(
                                        url: "https://m.primal.net/OEzS.mp4",
        //                                availableViewModes: [.fullscreen, .overlay, .detailstream])
                                        availableViewModes: [.fullscreen, .overlay])
                            }
                        }
                        
                        Button("Close") {
                            AnyPlayerModel.shared.close()
                        }
                    }
                    
                    Text("Tab 1")
                }
                    .tabItem { Label("", systemImage: "house") }
                    .tag("Main")
                    .preference(key: TabBarHeightKey.self, value: geometry.size.height)
            }
            
            Text("Tab 2")
                .tabItem { Label("", systemImage: "bookmark") }
                .tag("Bookmarks")
            
            Text("Tab 3")
                .tabItem { Label("", systemImage: "magnifyingglass") }
                .tag("Search")
            
            Text("Tab 4")
                .tabItem { Label("", systemImage: "bell.fill") }
                .tag("Notifications")
                .badge(2)
            
            Text("Tab 5")
                .tabItem { Label("", systemImage: "envelope.fill") }
                .tag("Messages")
                .badge(1)
        }
        .overlay(alignment: .center) {
            OverlayVideo()
//                .offset(y: apm.viewMode == .videostream ? 0 : -offset)
        }
        
    }
    .onPreferenceChange(TabBarHeightKey.self) { tabBarHeight in
        print("Tab Bar Height: \(UIScreen.main.bounds.height - tabBarHeight)")
    }
}

struct TabBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

