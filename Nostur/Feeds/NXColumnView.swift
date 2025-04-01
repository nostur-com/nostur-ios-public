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
    
    @StateObject private var viewModel = NXColumnViewModel()
    @StateObject private var speedTest = NXSpeedTest()
    
    private var config: NXColumnConfig
    private var isVisible: Bool
    
    init(config: NXColumnConfig, isVisible: Bool) {
        self.config = config
        self.isVisible = isVisible
    }

    @State private var feedSettingsFeed: CloudFeed?
    @State private var didLoad = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ZStack {
            switch(viewModel.viewState) {
            case .loading:
                ZStack(alignment: .center) {
                    CenteredProgressView()
                }
            case .posts(let nrPosts):
                NXPostsFeed(vm: viewModel, posts: nrPosts)
            case .timeout:
                ZStack(alignment: .center) {
                    Color.clear
                    Text("Nothing here :(")
                        .foregroundColor(themes.theme.accent)
                }
            case .error(let errorMessage):
                Text(errorMessage)
            }
        }
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
//#if DEBUG
//        .overlay(alignment: .bottom) {
//            speedTestView
//        }
//#endif
        .onAppear {
            L.og.debug("☘️☘️ \(config.name) .onAppear -[LOG]-")
            viewModel.isVisible = isVisible
            
            if isVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { // This should always be a bit delayed else it will be cancelled out by other feeds .onChange(of: isVisible)
                    if case .relays(let feed) = config.columnType, feed.relaysData.count == 1 {
                        Drafts.shared.lockToThisRelay = feed.relaysData.first
                    }
                    else {
                        Drafts.shared.lockToThisRelay = nil
                    }
                }
            }
            
            guard !didLoad else { return }
            didLoad = true
            viewModel.availableWidth = dim.availableNoteRowWidth
            if isVisible, let relaysData = config.feed?.relaysData {
                for relay in relaysData {
                    ConnectionPool.shared.addConnection(relay) { conn in
                        conn.connect()
                    }
                }
            }
            viewModel.initialize(config, speedTest: speedTest)
        }
        .onChange(of: isVisible) { newValue in
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) .onChange(of: isVisible) newValue: \(newValue) -[LOG]-")
#endif
            
            if newValue {
                if isVisible, let relaysData = config.feed?.relaysData {
                    for relay in relaysData {
                        ConnectionPool.shared.addConnection(relay) { conn in
                            conn.connect()
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { // This should always be a bit delayed else it will be cancelled out by other feeds .onChange(of: isVisible)
                    if case .relays(let feed) = config.columnType, feed.relaysData.count == 1 {
                        Drafts.shared.lockToThisRelay = feed.relaysData.first
                    }
                    else {
                        Drafts.shared.lockToThisRelay = nil
                    }
                }
            }
            
            guard viewModel.isVisible != newValue else { return }
            viewModel.isVisible = newValue
        }
        .onChange(of: config) { [config] newConfig in
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) .onChange(of: config)")
#endif
            guard viewModel.config != newConfig else { return }
            if let relaysData = newConfig.feed?.relaysData {
                for relay in relaysData {
                    ConnectionPool.shared.addConnection(relay) { conn in
                        conn.connect()
                    }
                }
            }

            viewModel.viewState = .loading
            viewModel.initialize(newConfig, speedTest: speedTest)
            
            // Fix feed paused by NXPostsFeed.onDisappear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                viewModel.resume()
            }
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
    }
    
#if DEBUG
    @ViewBuilder
    private var speedTestView: some View {
        VStack {
            Text("First: \(speedTest.resultFirstFetch) Final: \(speedTest.resultLastFetch)")
            if let timestampStart = speedTest.timestampStart {
                ForEach(Array(speedTest.relaysFinishedAt.enumerated()), id: \.offset) { index, timestamp in
                    Text("\(timestamp.timeIntervalSince(timestampStart))")
                }
                Divider()
                ForEach(Array(speedTest.relaysTimeouts.enumerated()), id: \.offset) { index, timestamp in
                    Text("\(timestamp.timeIntervalSince(timestampStart))")
                }
            }
        }
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
    }
#endif
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
