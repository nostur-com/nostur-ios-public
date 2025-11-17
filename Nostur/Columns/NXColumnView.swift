//
//  NXColumnView.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI
import NavigationBackport

struct NXColumnView<HeaderContent: View>: View {
    
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    
    @StateObject private var viewModel = NXColumnViewModel()
    @StateObject private var speedTest = NXSpeedTest()
    
    private var config: NXColumnConfig
    private var isVisible: Bool
    private var header: HeaderContent
    
    init(config: NXColumnConfig, isVisible: Bool, @ViewBuilder header: () -> HeaderContent) {
        self.config = config
        self.isVisible = isVisible
        self.header = header()
    }

    @State private var feedSettingsFeed: CloudFeed?
    @State private var didLoad = false
    
    var body: some View {
        ZStack {
            switch(viewModel.viewState) {
            case .loading:
                ZStack(alignment: .center) {
                    theme.listBackground
                    CenteredProgressView()
                }
            case .posts(let nrPosts):
                VStack(spacing: 0) {
                    header
                    NXPostsFeed(vm: viewModel, posts: nrPosts)
                }
            case .timeout:
                ZStack(alignment: .center) {
                    theme.listBackground
                    VStack(spacing: 20) {
                        Text("Nothing here :(")
                        Button(action: {
                            viewModel.reload(config)
                        }) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                                .foregroundColor(theme.accent)
                        }
                    }
                    
                    .centered()
                }
            case .error(let errorMessage):
                ZStack(alignment: .center) {
                    theme.listBackground
                    VStack(spacing: 20) {
                        Text(errorMessage)
                        Button(action: {
                            viewModel.reload(config)
                        }) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                                .foregroundColor(theme.accent)
                        }
                    }
                    .centered()
                }
                
            }
        }
        
        .safeAreaInset(edge: .top, alignment: .leading, spacing: 0) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
//            LiveEventsBanner(showLiveEventsBanner: $showLiveEventsBanner)
//                .opacity(showLiveEventsBanner ? 1.0 : 0)
//                .frame(height: showLiveEventsBanner ? 50 : 0)
        }
        
//        .overlay(alignment: .top) {
//            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
//        }
//#if DEBUG
//        .overlay(alignment: .bottom) {
//            speedTestView
//        }
//#endif
        .onAppear {
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) .onAppear -[LOG]-")
#endif
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
            if isVisible, let relaysData = config.feed?.relaysData {
                
                // prepare auth
                for relayData in relaysData {
                    // A) if .auth==true then relayData is from app relays and auth should be done with logged in account
                    // B) if .auth==false then auth may be done if feed.accountPubkey is set (is set when adding relay-feed)
                    if !relayData.auth, let accountPubkey = config.feed?.accountPubkey {
                        // for B) we cache the pubkey to auth with
                        ConnectionPool.shared.queue.async(flags: .barrier) {
                            ConnectionPool.shared.relayFeedAuthPubkeyMap[relayData.id] = accountPubkey
                        }
                    }
                }
                
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
        
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if IS_DESKTOP_COLUMNS() {
                    Button("Feed settings...", systemImage: "gearshape") {
                        feedSettingsFeed = config.feed
                    }
                    .help("Feed settings...")
                }
            }
        }
        
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            guard viewModel.isVisible, let config = viewModel.config else { return }
            feedSettingsFeed = config.feed
        }
        .sheet(item: $feedSettingsFeed, onDismiss: {
            if let feed = feedSettingsFeed {
                dismissSheet(feed)
            }
        }, content: { feed in
            NBNavigationStack {
                FeedSettings(feed: feed)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") {
                                dismissSheet(feed)
                            }
                        }
                    }
                    .environment(\.theme, theme)
                    .environment(\.containerID, containerID)
                    .environmentObject(la)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        })
    }
    
    private func dismissSheet(_ feed: CloudFeed) {
        DataProvider.shared().saveToDiskNow(.viewContext)
        feedSettingsFeed = nil
        
        if feed.type == CloudFeedType.relays.rawValue {
            sendNotification(.listRelaysChanged, NewRelaysForList(subscriptionId: feed.subscriptionId, relays: feed.relaysData, wotEnabled: feed.wotEnabled))
        }
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

#Preview("Single column") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadCloudFeeds(1)
        Themes.default.loadOrange()
    }) {
        
        if let list = PreviewFetcher.fetchCloudFeed() {
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


// Makes optional title possible in: PostLayout { } title: { }

extension NXColumnView where HeaderContent == EmptyView {
    
    init(config: NXColumnConfig, isVisible: Bool) {
        self.init(config: config, isVisible: isVisible, header: { EmptyView() })
    }
}
