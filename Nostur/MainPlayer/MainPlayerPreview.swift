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
    VStack {
        TabView {
            GeometryReader { geometry in
                VStack {
                    Button("PLAY!!!") {
                        AnyPlayerModel.shared.loadVideo(url: "https://static.vecteezy.com/system/resources/previews/016/465/804/mp4/silhouettes-flock-of-seagulls-over-the-sea-during-amazing-sky-video.mp4")
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
        .overlay(alignment: .bottom) {
            OverlayVideo()
                .offset(y: -offset)
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
