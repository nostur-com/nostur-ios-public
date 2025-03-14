//
//  NXColumnView.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI
import NavigationBackport

struct NXColumnView: View {
    
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var themes: Themes
    public var config: NXColumnConfig
    @StateObject private var viewModel = NXColumnViewModel()
    public var isVisible: Bool

    @State private var feedSettingsFeed: CloudFeed?
    @State private var didLoad = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        NBNavigationStack {
            switch(viewModel.viewState) {
            case .loading:
                ZStack(alignment: .center) {
                    themes.theme.listBackground
                    ProgressView()
                }
            case .posts(let nrPosts):
                NXPostsFeed(vm: viewModel, posts: nrPosts, isVisible: isVisible)
            case .error(let errorMessage):
                Text(errorMessage)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            L.og.debug("☘️☘️ \(config.name) .onAppear")
            viewModel.isVisible = isVisible
            viewModel.availableWidth = dim.availableNoteRowWidth
            if let relaysData = config.feed?.relaysData {
                for relay in relaysData {
                    ConnectionPool.shared.addConnection(relay) { conn in
                        conn.connect()
                    }
                }
            }
            viewModel.load(config)
        }
        .onChange(of: isVisible) { newValue in
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) .onChange(of: isVisible) newValue: \(newValue)")
#endif
            guard viewModel.isVisible != newValue else { return }
            viewModel.isVisible = newValue
        }
        .onChange(of: config) { newValue in
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) .onChange(of: config)")
#endif
            guard viewModel.config != newValue else { return }
            if let relaysData = newValue.feed?.relaysData {
                for relay in relaysData {
                    ConnectionPool.shared.addConnection(relay) { conn in
                        conn.connect()
                    }
                }
            }
            viewModel.load(newValue)
        }
        .onChange(of: dim.availableNoteRowWidth) { newValue in
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) .onChange(of: availableNoteRowWidth)")
#endif
            guard viewModel.availableWidth != newValue else { return }
            viewModel.availableWidth = newValue
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            guard isVisible, let config = viewModel.config else { return }
            feedSettingsFeed = config.feed
        }
        .sheet(item: $feedSettingsFeed, content: { feed in
            NBNavigationStack {
                FeedSettings(feed: feed)
            }
            .nbUseNavigationStack(.never)
        })
        
        
        // Resume on (re)connect or back from background
        .onChange(of: scenePhase) { newScenePhase in
            switch newScenePhase {
            case .active:
                if isVisible && !IS_CATALYST {
                    if (NRState.shared.appIsInBackground) { // if we were actually in background (from .background, not just a few seconds .inactive)
                        viewModel.resume()
                    }
                }
                else if isVisible {
                    viewModel.resume()
                }
                
            case .background:
                if !IS_CATALYST && ((!config.id.starts(with: "Following-") || config.name == "Explore")) {
                    viewModel.pause()
                }
            default:
                break
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadCloudFeeds(1)
    }) {
        
        if let list = PreviewFetcher.fetchList() {
            let config = NXColumnConfig(id: list.id?.uuidString ?? "?", columnType: .pubkeys(list), accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", name: "Following")
            NXColumnView(config: config, isVisible: true)
        }
    }
}


#Preview("3 columns") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadCloudFeeds(3)
    }) {
        FeedListViewTester()
    }
}



struct FeedListViewTester: View {
    @EnvironmentObject var la: LoggedInAccount
    
    @State private var columnConfigs: [NXColumnConfig] = []
    
    var body: some View {
        HStack {
            ForEach(columnConfigs) { config in
                ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                    AvailableWidthContainer {
                        NXColumnView(config: config, isVisible: true)
                    }
                }
            }
        }
        .onAppear {
            generateTestColumns()
        }
    }
    
    func generateTestColumns() {
        columnConfigs =  (PreviewFetcher.fetchLists().map { list in
            NXColumnConfig(id: list.id?.uuidString ?? "?", columnType: .pubkeys(list), accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", name: "Following")
        }) + [
//            ColumnConfig(id: "pubkeys", columnType: .pubkeys, accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"),
//            ColumnConfig(id: "mentions", columnType: .mentions, accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"),
//            ColumnConfig(id: "reactions", columnType: .reactions, accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e")
        ]
    }
}
