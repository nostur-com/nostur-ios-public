//
//  Gallery.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2023.
//

import SwiftUI
import NukeUI
import NavigationBackport

struct Gallery: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject var vm: GalleryViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Gallery" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_subtab") }
    }
    
    @Namespace var top
    
    static let gridColumns = Array(repeating: GridItem(.flexible()), count: 3)
    
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            switch vm.state {
            case .initializing, .loading:
                CenteredProgressView()
                    .task(id: "gallery") {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(vm.timeoutSeconds) * NSEC_PER_SEC)
                            vm.timeout()
                        } catch { }
                    }
            case .ready:
                ScrollView {
                    Color.clear.frame(height: 1).id(top)
                    if !vm.items.isEmpty {
                        LazyVGrid(columns: Self.gridColumns) {
                            ForEach(vm.items.indices, id:\.self) { index in
                                GeometryReader { geo in
                                    if index < vm.items.count { // Should fix "Index out of range" crash
                                        GalleryGridItemView(size: geo.size.width, items: vm.items, currentIndex: index, withPFP: true)
                                    }
                                }
                                .clipped()
                                .aspectRatio(1, contentMode: .fill)
//                                    .id(index)
                                .contentShape(Rectangle())
//                                    .onTapGesture {
//                                        sendNotification(.fullScreenView17, FullScreenItem17(items: vm.items, index: index))
//                                    }
                            }
                        }
                    }
                    else {
                        Button("Refresh") { vm.reload() }
                            .centered()
                    }
                }
                .refreshable {
                    await vm.refresh()
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
            case .timeout:
                VStack {
                    Text("Time-out while loading gallery")
                    Button("Try again") { vm.reload() }
                }
                .centered()
            }
        }
        .background(themes.theme.background)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            // Load if tab is active OR if macOS (detail pane)
            guard IS_CATALYST || (selectedTab == "Main" && selectedSubTab == "Gallery") else { return }
            vm.load(speedTest: speedTest)
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { _ in
            vm.reload()
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard vm.shouldReload else { return }
            guard !IS_CATALYST else { return }
            guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
            vm.state = .loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { // Reconnect delay
                vm.load(speedTest: speedTest)
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Gallery" else { return }
            vm.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                GalleryFeedSettings(vm: vm)
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
    }
}

struct Gallery_Previews: PreviewProvider {
    static var previews: some View {
        Gallery()
            .environmentObject(GalleryViewModel())
            .environmentObject(Themes.default)
    }
}

struct GalleryGridItemView: View {
    public let size: Double
    public let items: [GalleryItem]
    public let currentIndex: Int
    
    public var withPFP = false
    
    private var currentItem: GalleryItem { items[currentIndex] }
    
    var body: some View {
        MediaContentView(
            galleryItem: currentItem,
            availableWidth: size,
            placeholderAspect: 1.0,
            maxHeight: size,
            contentMode: .fill,
            galleryItems: items,
            autoload: true // Gallery is from follows so can be true
        )
        .overlay(alignment: .bottomLeading) {
            if withPFP, let pfpPictureURL = currentItem.pfpPictureURL {
                MiniPFP(pictureUrl: pfpPictureURL)
                    .padding(10)
            }
        }
    }
}


