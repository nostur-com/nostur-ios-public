//
//  ProfilePostsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

struct ProfilePostsView: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings:SettingsStore = .shared
    @StateObject private var vm:ProfilePostsViewModel
    @State var showMore = true
    @State var lastFetchAtId = ""
    
    init(pubkey: String) {
        _vm = StateObject(wrappedValue: ProfilePostsViewModel(pubkey))
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        switch vm.state {
        case .initializing, .loading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
                .onAppear { vm.load() }
                .task(id: "profileposts") {
                    do {
                        try await Task.sleep(
                            until: .now + .seconds(10),
                            tolerance: .seconds(2),
                            clock: .continuous
                        )
                        vm.state = .timeout
                    } catch {
                        
                    }
                }
        case .ready:
            VStack {
                LazyVStack(spacing: 10) {
                    ForEach(vm.posts) { nrPost in
                        Box(nrPost: nrPost) {
                            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, ignoreBlock: true, theme: themes.theme)
                        }
                        .id(nrPost.id)
                        .onBecomingVisible {
                            // SettingsStore.shared.fetchCounts should be true for below to work
                            vm.prefetch(nrPost)
                            
                            guard nrPost == vm.posts.last else { return }
                            guard lastFetchAtId != nrPost.id else { return }
                            vm.loadMore(after: nrPost, amount: 10)
                            vm.fetchMore(after: nrPost, amount: 20)
//                            vm.loadMore(after: nrPost, amount: max(20, vm.posts.count * 2))
                            lastFetchAtId = nrPost.id
                        }
                        .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                    }
                }
            }
            
//            .padding(.top, 10)
//            .background(themes.theme.listBackground)
        case .timeout:
            VStack(alignment: .center) {
                Text("Unable to fetch posts")
                    .frame(maxWidth: .infinity, alignment: .center)
                Button("Try again") { vm.reload() }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

#Preview { 
    let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
    //        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
    //        let pubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
            
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        ScrollView {
            LazyVStack {
                ProfilePostsView(pubkey: pubkey)
            }
        }
    }
}
