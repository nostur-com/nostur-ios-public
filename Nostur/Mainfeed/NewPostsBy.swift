//
//  NewPostsBy.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/12/2023.
//

import SwiftUI
import Combine


struct NewPostsBy: View {
    
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings:SettingsStore = .shared
    @StateObject private var vm:NewPostsVM
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Notifications" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "New Posts" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
    }
    
    @Namespace private var top
    
    init(pubkeys: Set<String>, since: Int64) {
        _vm = StateObject(wrappedValue: NewPostsVM(pubkeys: pubkeys, since: since))
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            switch vm.state {
            case .initializing, .loading:
                CenteredProgressView()
                    .task(id: "new-posts") {
                        do {
                            try await Task.sleep(
                                until: .now + .seconds(8.0),
                                tolerance: .seconds(2),
                                clock: .continuous
                            )
                            vm.timeout()
                        } catch {
                            
                        }
                    }
            case .ready:
                ScrollView {
                    Color.clear.frame(height: 1).id(top)
                    if !vm.posts.isEmpty {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.posts) { post in
                                Box(nrPost: post) {
                                    PostRowDeletable(nrPost: post, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                                }
                                .id(post.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
//                                .transaction { t in
//                                    t.animation = nil
//                                }
                                .onBecomingVisible {
                                    // SettingsStore.shared.fetchCounts should be true for below to work
                                    vm.prefetch(post)
                                }
                            }
                        }
                        .padding(0)
                    }
                    else {
                        Button("Refresh") { vm.load() }
                            .centered()
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Notifications" && selectedNotificationsTab == "New Posts" else { return }
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Notifications" && selectedNotificationsTab == "New Posts" else { return }
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
                .padding(0)
            case .timeout:
                VStack {
                    Text("Time-out while loading posts")
                    Button("Try again") { vm.load() }
                }
                .centered()
            }
        }
        .navigationTitle("New Posts")
        .navigationBarTitleDisplayMode(.inline)
        .background(themes.theme.listBackground)
        .onAppear {
            guard selectedTab == "Notifications" && selectedNotificationsTab == "New Posts" else { return }
            vm.load()
        }
        .onChange(of: selectedNotificationsTab) { newValue in
            guard newValue == "New Posts" else { return }
            vm.load()
        }
    }
}

#Preview("NewPostsBy") {
    NewPostsBy(pubkeys: [], since: 0)
        .environmentObject(Themes.default)
}
