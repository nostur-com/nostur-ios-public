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
            ScrollView {
                if vm.items.isEmpty {
                    CenteredProgressView()
                }
                else {
                    Color.clear.frame(height: 1).id(top)
                    LazyVGrid(columns: gridColumns) {
                        ForEach(vm.items) { item in
                            GeometryReader { geo in
                                GridItemView(size: geo.size.width, item: item)
                            }
                            .clipped()
                            .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
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
            .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                vm.reload()
            }
        }
        .background(theme.listBackground)
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
            vm.load()
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard selectedTab == "Main" && selectedSubTab == "Gallery" else { return }
            vm.items = []
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
    var url:URL { item.url }
    
    var body: some View {
        LazyImage(request: makeImageRequest(url, width: size, height: size, contentMode: .aspectFill, upscale: true, label: "GridItemView")) { state in
            if state.error != nil {
                Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                    .centered()
                    .onAppear {
                        L.og.error("Failed to load image: \(state.error?.localizedDescription ?? "")")
                    }
            }
            else if let image = state.image {
                image
                //                            .interpolation(.none)
                    .resizable() // <-- without this STILL sometimes a randomly an image with wrong size, even though we have all the correct dimensions. Somewhere Nuke is doing something wrong
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .onTapGesture {
                        sendNotification(.fullScreenView, FullScreenItem(url: url))
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


