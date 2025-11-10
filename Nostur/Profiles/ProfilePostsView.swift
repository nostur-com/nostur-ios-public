//
//  ProfilePostsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

struct ProfilePostsView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    @StateObject private var vm: ProfilePostsViewModel
    @State var showMore = true
    @State var lastFetchAtId = ""
    
    init(pubkey: String, type: ProfilePostsViewModel.ProfilePostsType) {
        _vm = StateObject(wrappedValue: ProfilePostsViewModel(pubkey, type: type))
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        switch vm.state {
        case .initializing, .loading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .center)
                .onAppear { vm.load() }
                .task(id: "profileposts") {
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
                        PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, ignoreBlock: true, theme: theme)
                    }
                }
                .onBecomingVisible {
                    // SettingsStore.shared.fetchCounts should be true for below to work
                    vm.prefetch(nrPost)
                    
                    // on iPhone we can use vm.posts.last but on macOS it only works on second to last?? wtf!
                    guard nrPost == vm.posts[safe: vm.posts.count - 2] else { return }
                    
                    guard lastFetchAtId != nrPost.id else { return }
                    vm.loadMore(after: nrPost, amount: 10)
                    
                    // There is no way to query just root posts separate from replies
                    // So if we want to find root posts we increase the limit to increase the chance of getting enough root posts. (There could be many replies included in the response and we don't need them, unless we are querying for replies)
                    let requestLimit = vm.type == .posts ? 40 : 20
                    
                    vm.fetchMore(after: nrPost, amount: requestLimit)
//                            vm.loadMore(after: nrPost, amount: max(20, vm.posts.count * 2))
                    lastFetchAtId = nrPost.id
                }
                .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
            }
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
                ProfilePostsView(pubkey: pubkey, type: .posts)
            }
        }
    }
}
