//
//  ProfilePostsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

struct ProfilePostsView: View {
    @EnvironmentObject var theme:Theme
    @ObservedObject var settings:SettingsStore = .shared
    @StateObject private var vm:ProfilePostsViewModel
    
    init(pubkey: String) {
        _vm = StateObject(wrappedValue: ProfilePostsViewModel(pubkey))
    }
    
    var body: some View {
        let _ = Self._printChanges()
        switch vm.state {
        case .initializing:
            CenteredProgressView()
                .onAppear { vm.load() }
        case .loading:
            CenteredProgressView()
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
            LazyVStack(spacing: 10) {
                ForEach(vm.posts, id:\.id) { nrPost in
                    Box(nrPost: nrPost) {
                        PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages)
                    }
//                    .id(nrPost.id)
                    .onBecomingVisible {
                        // SettingsStore.shared.fetchCounts should be true for below to work
                        vm.prefetch(nrPost)
                    }
                    .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                }
                
                if let last = vm.posts.last {
                    Button(String(localized:"Show more", comment: "Button to show posts on profile page")) {
                        vm.loadMore(after: last, amount: max(20, vm.posts.count * 2))
                    }
                    .hCentered()
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 10)
            .background(theme.listBackground)
        case .timeout:
            VStack(alignment: .center) {
                Spacer()
                Text("Time-out")
                Button("Try again") { vm.reload() }
                Spacer()
            }
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
