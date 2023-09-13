//
//  Gallery.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2023.
//

import SwiftUI
import NukeUI

struct Gallery: View {
    @EnvironmentObject var theme:Theme
    @ObservedObject var vm:GalleryViewModel
    
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Gallery"
    
    @Namespace var top
    
    private static let initialColumns = 3
    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: initialColumns)
    
    
    var body: some View {
        ScrollViewReader { proxy in
            switch vm.state {
            case .initializing:
                EmptyView()
            case .loading:
                CenteredProgressView()
                    .task(id: "gallery") {
                        do {
                            try await Task.sleep(
                                until: .now + .seconds(vm.timeoutSeconds),
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
                    LazyVGrid(columns: gridColumns) {
                        ForEach(vm.items) { item in
                            GeometryReader { geo in
                                GridItemView(size: geo.size.width, item: item, withPFP: true)
                            }
                            .clipped()
                            .aspectRatio(1, contentMode: .fit)
                        }
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
        .background(theme.listBackground)
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
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
    }
}

struct Gallery_Previews: PreviewProvider {
    static var previews: some View {
        Gallery(vm: GalleryViewModel())
            .environmentObject(Theme.default)
    }
}

struct GridItemView: View {
    let size: Double
    let item: GalleryItem
    var withPFP = false
    var url:URL { item.url }
    
    var body: some View {
        LazyImage(request: makeImageRequest(url, width: size, height: size, contentMode: .aspectFill, upscale: true, label: "GridItemView")) { state in
            if state.error != nil {
                Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                    .centered()
                    .onAppear {
                        L.og.error("Failed to load image: \(url.absoluteString) - \(state.error?.localizedDescription ?? "")")
                    }
                    .onTapGesture {
                        navigateTo(NotePath(id: item.event.id))
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
                        sendNotification(.fullScreenView, FullScreenItem(url: url, event: item.event))
                    }
                    .transaction { t in t.animation = nil }
                    .overlay(alignment:.topLeading) {
                        if state.isLoading { // does this conflict with showing preview images??
                            HStack(spacing: 5) {
                                ImageProgressView(progress: state.progress)
                                Text("Loading...")
                            }
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
                HStack(spacing: 5) {
                    ImageProgressView(progress: state.progress)
                }
                .centered()
            }
            else {
                Color(.secondarySystemBackground)
            }
        }
        .pipeline(ImageProcessing.shared.content)
        .transaction { t in t.animation = nil }
        .frame(width: size, height: size)
    }
}


