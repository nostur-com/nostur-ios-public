//
//  ProfileZapsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/02/2025.
//

import SwiftUI

struct ProfileZapsView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    @StateObject private var vm: ProfileZapsViewModel
    @State private var pfpURL: URL?
    @ObservedObject private var nrContact: NRContact
    
    init(nrContact: NRContact) {
        self.nrContact = nrContact
        _vm = StateObject(wrappedValue: ProfileZapsViewModel(nrContact.pubkey))
    }
    
    var body: some View {
        switch vm.state {
        case .initializing, .loading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                .onAppear { vm.load() }
                .task(id: "profileZaps") {
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
                        PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages)
                                .padding(.top, 20) // bit more padding so we have some space to put zap
                    }
                    .overlay(alignment: .topLeading) {
                        if let zap = vm.zapsMap[nrPost.id] {
                            HStack(spacing: 5) {
                                Circle()
                                    .foregroundColor(randomColor(seed: nrContact.pubkey))
                                    .frame(width: 20.0, height: 20.0)
                                    .overlay {
                                        if let pfpURL = nrContact.pictureUrl {
                                            MiniPFP(pictureUrl: pfpURL, size: 20.0)
                                                .animation(.easeIn, value: pfpURL)
                                        }
                                    }
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.yellow)
                                
                                Text(zap.0)
                                    .foregroundColor(.white)
                                    .fontWeightBold()
                                
                                if let content = zap.1 {
                                    Text(content)
                                        .foregroundColor(.white)
                                        .font(.footnote)
                                        .lineLimit(1)
                                }
                            }
                            .padding(4)
                            .background(theme.accent)
                            .clipShape(Capsule())
                        }
                    }
                }
//                    .id(nrPost.id)
                .onBecomingVisible {
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
