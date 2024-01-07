//
//  ProfileLikesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import CoreData

struct ProfileLikesView: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings:SettingsStore = .shared
    @StateObject private var vm:ProfileLikesViewModel
    
    init(pubkey: String) {
        _vm = StateObject(wrappedValue: ProfileLikesViewModel(pubkey))
    }
    
    var body: some View {
        switch vm.state {
        case .initializing, .loading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
                .onAppear { vm.load() }
                .task(id: "profilelikes") {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
                        vm.state = .timeout
                    } catch { }
                }
        case .ready:
            LazyVStack(spacing: 10) {
                ForEach(vm.posts, id:\.id) { nrPost in
                    Box(nrPost: nrPost) {
                        PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
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
//            .background(themes.theme.listBackground)
        case .timeout:
            VStack(alignment: .center) {
                Text("Unable to fetch content")
                Button("Try again") { vm.reload() }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .center)
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
