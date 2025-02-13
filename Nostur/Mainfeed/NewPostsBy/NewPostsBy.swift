//
//  NewPostsBy.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/12/2023.
//

import SwiftUI
import Combine


struct NewPostsBy: View {
    
    @EnvironmentObject private var themes: Themes
    @ObservedObject private var settings: SettingsStore = .shared
    @StateObject private var vm: NewPostsVM
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Notifications" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "New Posts" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
    }
    
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
                            try await Task.sleep(nanoseconds: UInt64(8) * NSEC_PER_SEC)
                            vm.timeout()
                        } catch { }
                    }
            case .ready:
                List(vm.posts) { nrPost in
                    ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                        PostOrThread(nrPost: nrPost)
                            .onBecomingVisible {
                                // SettingsStore.shared.fetchCounts should be true for below to work
                                vm.prefetch(nrPost)
                            }
                    }
                    .id(nrPost.id) // <-- must use .id or can't .scrollTo
                    .listRowSeparator(.hidden)
                    .listRowBackground(themes.theme.listBackground)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .environment(\.defaultMinListRowHeight, 50)
                .listStyle(.plain)
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Notifications" && selectedNotificationsTab == "New Posts" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Notifications" && selectedNotificationsTab == "New Posts" else { return }
                    self.scrollToTop(proxy)
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
    
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let topPost = vm.posts.first else { return }
        withAnimation {
            proxy.scrollTo(topPost.id, anchor: .top)
        }
    }
}

#Preview("NewPostsBy") {
    NewPostsBy(pubkeys: [], since: 0)
        .environmentObject(Themes.default)
}
