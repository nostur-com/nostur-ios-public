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
                        if #available(iOS 17, *) {
                            LazyVGrid(columns: Self.gridColumns) {
                                ForEach(vm.items.indices, id:\.self) { index in
                                    GeometryReader { geo in
                                        if index < vm.items.count { // Should fix "Index out of range" crash
                                            GridItemView17(size: geo.size.width, item: vm.items[index], withPFP: true)
                                        }
                                    }
                                    .clipped()
                                    .aspectRatio(1, contentMode: .fit)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        sendNotification(.fullScreenView17, FullScreenItem17(items: vm.items, index: index))
                                    }
                                }
                            }
                        }
                        else {
                            LazyVGrid(columns: Self.gridColumns) {
                                ForEach(vm.items) { item in
                                    GeometryReader { geo in
                                        GridItemView(size: geo.size.width, item: item, withPFP: true)
                                    }
                                    .clipped()
                                    .aspectRatio(1, contentMode: .fit)
                                }
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
                    Spacer()
                    Text("Time-out while loading gallery")
                    Button("Try again") { vm.reload() }
                    Spacer()
                }
            }
        }
        .background(themes.theme.listBackground)
        .onAppear {
            // Load if tab is active OR if macOS (detail pane)
            guard IS_CATALYST || (selectedTab == "Main" && selectedSubTab == "Gallery") else { return }
            vm.load()
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
                vm.load()
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Gallery" else { return }
            vm.load() // didLoad is checked in .load() so no need here
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

struct GridItemView: View {
    @EnvironmentObject private var themes:Themes
    public let size: Double
    public let item: GalleryItem
    public var withPFP = false
    private var url: URL { item.url }
    
    var body: some View {
        LazyImage(request: makeImageRequest(url, width: size, height: size, contentMode: .aspectFill, upscale: true, label: "GridItemView")) { state in
            if state.error != nil {
                if SettingsStore.shared.lowDataMode {
                    Text(url.absoluteString)
                        .foregroundColor(themes.theme.accent)
                        .truncationMode(.middle)
                        .onTapGesture {
                            guard let eventId = item.eventId else { return }
                            navigateTo(NotePath(id: eventId))
                        }
                }
                else {
                    Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                        .centered()
                        .onAppear {
                            L.og.error("Failed to load image: \(url.absoluteString) - \(state.error?.localizedDescription ?? "")")
                        }
                        .onTapGesture {
                            guard let eventId = item.eventId else { return }
                            navigateTo(NotePath(id: eventId))
                        }
                }
            }
            else if let image = state.image {
                image
                //                            .interpolation(.none)
                    .resizable() // <-- without this STILL sometimes a randomly an image with wrong size, even though we have all the correct dimensions. Somewhere Nuke is doing something wrong
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        sendNotification(.fullScreenView, FullScreenItem(url: url, galleryItem: item))
                    }
                    .overlay(alignment:.topLeading) {
                        if state.isLoading { // does this conflict with showing preview images??
                            ImageProgressView(state: state)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if withPFP, let pfpPictureURL = item.pfpPictureURL {
                            MiniPFP(pictureUrl: pfpPictureURL)
                                .padding(10)
                        }
                    }
            }
            else if state.isLoading { // does this conflict with showing preview images??
                ImageProgressView(state: state, numericOnly: false)
            }
            else {
                Color(.secondarySystemBackground)
            }
        }
        .pipeline(ImageProcessing.shared.content)
        .frame(width: size, height: size)
    }
}

struct GridItemView17: View {
    @EnvironmentObject private var themes: Themes
    public let size: Double
    public let item: GalleryItem
    public var withPFP = false
    private var url: URL { item.url }
    
    var body: some View {
        LazyImage(request: makeImageRequest(url, width: size, height: size, contentMode: .aspectFill, upscale: true, label: "GridItemView")) { state in
            if state.error != nil {
                if SettingsStore.shared.lowDataMode {
                    Text(url.absoluteString)
                        .foregroundColor(themes.theme.accent)
                        .truncationMode(.middle)
                        .onTapGesture {
                            guard let eventId = item.eventId else { return }
                            navigateTo(NotePath(id: eventId))
                        }
                }
                else {
                    Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                        .centered()
                        .onAppear {
                            L.og.error("Failed to load image: \(url.absoluteString) - \(state.error?.localizedDescription ?? "")")
                        }
                        .onTapGesture {
                            guard let eventId = item.eventId else { return }
                            navigateTo(NotePath(id: eventId))
                        }
                }
            }
            else if let image = state.image {
                image
                    .resizable() // <-- without this STILL sometimes a randomly an image with wrong size, even though we have all the correct dimensions. Somewhere Nuke is doing something wrong
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .overlay(alignment:.topLeading) {
                        if state.isLoading { // does this conflict with showing preview images??
                            ImageProgressView(state: state)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if withPFP, let pfpPictureURL = item.pfpPictureURL {
                            MiniPFP(pictureUrl: pfpPictureURL)
                                .padding(10)
                        }
                    }
            }
            else if state.isLoading { // does this conflict with showing preview images??
                ImageProgressView(state: state, numericOnly: false)
            }
            else {
                Color(.secondarySystemBackground)
            }
        }
        .pipeline(ImageProcessing.shared.content)
    }
}


