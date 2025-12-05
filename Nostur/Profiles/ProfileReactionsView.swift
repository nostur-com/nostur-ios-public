//
//  ProfileLikesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import CoreData
import NavigationBackport

struct ProfileReactionsView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    @StateObject private var vm: ProfileReactionsViewModel
    
    init(pubkey: String) {
        _vm = StateObject(wrappedValue: ProfileReactionsViewModel(pubkey))
    }
    
    var body: some View {
        switch vm.state {
        case .initializing, .loading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                .onAppear { vm.load() }
                .task(id: "profileReactions") {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
                        
                        Task { @MainActor in
                            if vm.state == .loading || vm.state == .initializing {
                                vm.state = .timeout
                            }
                        }
                    } catch { }
                }
        case .ready:
            ForEach(vm.posts) { nrPost in
                ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                    Box(nrPost: nrPost) {
                        PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: theme)
                    }
                    .overlay(alignment: .topLeading) {
                        if let reaction = vm.reactionsMap[nrPost.id] {
                            Text(reaction == "+" ? "❤️" : reaction)
                                .font(.title)
                                .padding(.top, 2)
                                .padding(.leading, 2)
                        }
                    }
                }
//                    .id(nrPost.id)
                .task {
                    // SettingsStore.shared.fetchCounts should be true for below to work
                    vm.prefetch(nrPost)
                }
                .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
            }
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

struct ProfileReactionList: View {
    private let pubkey: String
    @State private var nrContact: NRContact
    
    init(pubkey: String) {
        self.pubkey = pubkey
        _nrContact = State(wrappedValue: NRContact.instance(of: pubkey))
    }
    
    var body: some View {
        NXList(plain: true) {
            ProfileReactionsView(pubkey: pubkey)
        }
        .toolbar {
            ToolbarItem(placement: .title) {
                Text("\(nrContact.anyName)'s reactions")
            }
        }
    }
}

#Preview {
    let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
    
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.parseMessages(testSnowden())
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            ProfileReactionList(pubkey: pubkey)
        }
    }
}
