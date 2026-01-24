//
//  Streams.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI
import NavigationBackport

struct Streams: View {
    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var streamsVM: StreamsViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    @Weak private var collectionView: UICollectionView?    
    @Weak private var tableView: UITableView?
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { setSelectedTab(newValue) }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Streams" }
        set { setSelectedSubTab(newValue) }
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        Container {
            switch streamsVM.state {
            case .initializing, .loading:
                CenteredProgressView()
            case .ready:
                List {
                    ForEach(streamsVM.streams) { nrLiveEvent in
                        LiveEventRowView2(liveEvent: nrLiveEvent)
                            .listRowSeparator(.hidden)
                            .listRowBackground(theme.listBackground)
                            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                .environment(\.defaultMinListRowHeight, 0)
                .listStyle(.plain)
                .refreshable {
                    await streamsVM.refresh()
                }
                .introspect(.list, on: .iOS(.v15)) { view in
                    DispatchQueue.main.async {
                      self.tableView = view
                    }
                }
                .introspect(.list, on: .iOS(.v16...)) { view in
                    DispatchQueue.main.async {
                      self.collectionView = view
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Streams" else { return }
                    self.scrollTo(index: 0)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Streams" else { return }
                    self.scrollTo(index: 0)
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    streamsVM.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Text("Time-out while loading discover feed")
                    Button("Try again") { streamsVM.reload() }
                }
                .centered()
            }
        }
        .background(theme.listBackground)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            guard IS_DESKTOP_COLUMNS() || (selectedTab == "Main" && selectedSubTab == "Streams") else { return }
            streamsVM.load(speedTest: speedTest)
        }
        .onChange(of: selectedSubTab) { newValue in
            guard !IS_DESKTOP_COLUMNS() && newValue == "Streams" else { return }
            streamsVM.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                StreamsFeedSettings(streamsVM: streamsVM)
                    .environment(\.theme, theme)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") {
                                showSettings = false
                            }
                        }
                    }
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
}

#Preview {
    Streams()
        .environmentObject(StreamsViewModel())
        .environmentObject(Themes.default)
}

@_spi(Advanced) import SwiftUIIntrospect
extension Streams {
    
    // Scroll instantly instead of waiting to finish scrolling before it works (when using ScrollViewProxy)
    private func scrollTo(index: Int) {

        if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
            if let collectionView,
               let rows = collectionView.dataSource?.collectionView(collectionView, numberOfItemsInSection: 0),
               rows > index
            {
                collectionView.scrollToItem(at: .init(row: index, section: 0), at: .top, animated: true)
            }
        }
        else { // iOS 15 UITableView
            if let tableView,
               let rows = tableView.dataSource?.tableView(tableView, numberOfRowsInSection: 0),
               rows > index
            {
                tableView.scrollToRow(at: .init(row: index, section: 0), at: .top, animated: true)
            }
        }
    }
}

// TODO: Make nice
struct LiveEventRowView2: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    @ObservedObject private var liveEvent: NRLiveEvent
    private var fullWidth: Bool = false
    private var hideFooter: Bool = false
    private var navTitleHidden: Bool = false
    private var forceAutoload: Bool
    
    private var shouldAutoload: Bool {
        return !liveEvent.isNSFW  && (forceAutoload || SettingsStore.shouldAutodownload(liveEvent) || nxViewingContext.contains(.screenshot))
    }
    
    init(liveEvent: NRLiveEvent, fullWidth: Bool = false, hideFooter: Bool = false, navTitleHidden: Bool = false, forceAutoload: Bool = false) {
        self.liveEvent = liveEvent
        self.fullWidth = fullWidth
        self.hideFooter = hideFooter
        self.navTitleHidden = navTitleHidden
        self.forceAutoload = forceAutoload
    }
    
    @State private var showMiniProfile = false
    @State private var didLoad = false
    
    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: 3)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack {
                headerView
                
                LazyVGrid(columns: gridColumns, spacing: 8.0) {
                    ForEach(liveEvent.onStage.indices, id: \.self) { index in
                        NestParticipantView(nrContact: liveEvent.onStage[index],
                                            role: liveEvent.role(forPubkey: liveEvent.onStage[index].pubkey),
                                            aTag: liveEvent.id,
                                            disableZaps: true
                        )
                        .id(liveEvent.onStage[index].pubkey)
                    }
                }
                
                Divider()
                
                LazyVGrid(columns: gridColumns, spacing: 8.0) {
                    ForEach(liveEvent.listeners.indices, id: \.self) { index in
                        NestParticipantView(nrContact: liveEvent.listeners[index],
                                            role: liveEvent.role(forPubkey: liveEvent.listeners[index].pubkey),
                                            aTag: liveEvent.id,
                                            disableZaps: true
                        )
                        .id(liveEvent.listeners[index].pubkey)
                    }
                }
            }
            
            if let image = liveEvent.thumbUrl {
                MediaContentView(
                    galleryItem: GalleryItem(url: image, pubkey: liveEvent.pubkey, eventId: liveEvent.id),
                    availableWidth: (availableWidth - 40) + (fullWidth ? 40 : 20),
                    placeholderAspect: 16/9,
                    maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                    contentMode: .fit,
                    upscale: true,
                    autoload: shouldAutoload,
                    isNSFW: liveEvent.isNSFW
                )
                .allowsHitTesting(false)
                .padding(.horizontal, fullWidth ? -10 : 0)
                .padding(.vertical, 10)
            }
        }
        .onAppear {
            liveEvent.fetchPresenceFromRelays()
            
            // better just fetch all Ps for now
            if !liveEvent.missingPs.isEmpty {
                QueuedFetcher.shared.enqueue(pTags: liveEvent.missingPs)
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            setSelectedTab("Main")
            if let status = liveEvent.status, status == "planned" {
                navigateTo(liveEvent, context: containerID)
            }
            else if liveEvent.isLiveKit && (IS_CATALYST || IS_IPAD) { // Always do nests in tab on ipad/desktop
                navigateTo(liveEvent, context: containerID)
            }
            else {
                // LOAD NEST
                if liveEvent.isLiveKit {
                    LiveKitVoiceSession.shared.activeNest = liveEvent
                }
                // ALREADY PLAYING IN .OVERLAY, TOGGLE TO .DETAILSTREAM
                else if AnyPlayerModel.shared.nrLiveEvent?.id == liveEvent.id {
                    AnyPlayerModel.shared.viewMode = .detailstream
                }
                // LOAD NEW .DETAILSTREAM
                else {
                    Task {
                        await AnyPlayerModel.shared.loadLiveEvent(nrLiveEvent: liveEvent, availableViewModes: [.detailstream, .overlay, .audioOnlyBar])
                    }
                }
            }
        }
    }
    
    // Copy paste from LiveEventDetail (rec removed)
    @ViewBuilder
    private var headerView: some View {
        if streamHasEnded {
            HStack {
                Text("Stream has ended")
                    .foregroundColor(.secondary)
            }
        }
        else if liveEvent.totalParticipants > 0 {
            HStack {
                if liveEvent.totalParticipants > 0 {
                    Text("\(liveEvent.totalParticipants) participants")
                        .foregroundColor(.secondary)
                }
            }
        }
        else if let scheduledAt = liveEvent.scheduledAt {
            HStack {
                Image(systemName: "calendar")
                Text(scheduledAt.formatted())
            }
                .padding(.top, 10)
                .font(.footnote)
                .foregroundColor(theme.secondary)
        }
        
        if let title = liveEvent.title {
            Text(title)
                .font(.title)
                .fontWeightBold()
                .lineLimit(2)
        }
        
        if let summary = liveEvent.summary, (liveEvent.title ?? "") != summary {
            Text(summary)
                .lineLimit(20)
        }
        
//#if DEBUG
//        Text("copy event json")
//            .onTapGesture {
//                UIPasteboard.general.string = liveEvent.eventJson
//            }
//#endif
    }
    
    private var streamHasEnded: Bool {
        if let status = liveEvent.status, status == "ended" {
            return true
        }
        return false
    }
}
