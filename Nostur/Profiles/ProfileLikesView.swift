//
//  ProfileLikesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import CoreData

struct ProfileLikesView: View {
    @EnvironmentObject private var theme:Theme
    @ObservedObject private var settings:SettingsStore = .shared
    @StateObject private var vm:ProfileLikesViewModel
    
    init(pubkey: String) {
        _vm = StateObject(wrappedValue: ProfileLikesViewModel(pubkey))
    }
    
    var body: some View {
        switch vm.state {
        case .initializing:
            CenteredProgressView()
                .onAppear { vm.load() }
        case .loading:
            CenteredProgressView()
                .task(id: "profilelikes") {
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
            }
//            .padding(.top, 10)
//            .background(theme.listBackground)
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
    
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        ScrollView {
            ProfileLikesView(pubkey: pubkey)
        }
    }
}
