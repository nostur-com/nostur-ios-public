//
//  ProfileInteractionsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/02/2025.
//

import SwiftUI

struct ProfileInteractionsView: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject private var settings: SettingsStore = .shared
    @ObservedObject private var nrContact: NRContact
    
    @StateObject private var conversationsVM: ProfileInteractionsConversationsVM
    @StateObject private var reactionsVM: ProfileInteractionsReactionsVM
    @StateObject private var zapsVM: ProfileInteractionsZapsVM
    @StateObject private var repostsVM: ProfileInteractionsRepostsVM
    
    
    @State private var selectedType = "Conversations"
    
    init(nrContact: NRContact) {
        self.nrContact = nrContact
        _conversationsVM = StateObject(wrappedValue: ProfileInteractionsConversationsVM(nrContact.pubkey))
        _reactionsVM = StateObject(wrappedValue: ProfileInteractionsReactionsVM(nrContact.pubkey))
        _zapsVM = StateObject(wrappedValue: ProfileInteractionsZapsVM(nrContact.pubkey))
        _repostsVM = StateObject(wrappedValue: ProfileInteractionsRepostsVM(nrContact.pubkey))
    }
    
    var body: some View {
        Section {
            switch selectedType {
            case "Conversations":
                switch conversationsVM.state {
                case .initializing, .loading:
                    ProgressView()
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                        .onAppear { conversationsVM.load() }
                        .task(id: "profileInteractions") {
                            do {
                                try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
                                
                                Task { @MainActor in
                                    if conversationsVM.state == .loading || conversationsVM.state == .initializing {
                                        conversationsVM.state = .timeout
                                    }
                                }
                            } catch { }
                        }
                case .ready:
                    ForEach(conversationsVM.posts) { nrPost in
                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                            Box(nrPost: nrPost) {
                                PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                            }
                        }
                        //                    .id(nrPost.id)
                        .onBecomingVisible {
                            // SettingsStore.shared.fetchCounts should be true for below to work
                            conversationsVM.prefetch(nrPost)
                        }
                        .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                        .listRowSeparator(.hidden)
                        .listRowBackground(themes.theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                case .timeout:
                    VStack(alignment: .center) {
                        Text("Nothing found")
                        Button("Reload") { conversationsVM.reload() }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            case "Reactions":
                switch reactionsVM.state {
                case .initializing, .loading:
                    ProgressView()
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                        .onAppear { reactionsVM.load() }
                        .task(id: "profileInteractions") {
                            do {
                                try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
                                
                                Task { @MainActor in
                                    if reactionsVM.state == .loading || reactionsVM.state == .initializing {
                                        reactionsVM.state = .timeout
                                    }
                                }
                            } catch { }
                        }
                case .ready:
                    ForEach(reactionsVM.posts) { nrPost in
                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                            Box(nrPost: nrPost) {
                                PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                            }
                        }
                        //                    .id(nrPost.id)
                        .onBecomingVisible {
                            // SettingsStore.shared.fetchCounts should be true for below to work
                            reactionsVM.prefetch(nrPost)
                        }
                        .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                        .overlay(alignment: .topLeading) {
                            if let reaction = reactionsVM.reactionsMap[nrPost.id] {
                                Text(reaction == "+" ? "❤️" : reaction)
                                    .padding(.top, 5)
                                    .padding(.leading, 5)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(themes.theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                case .timeout:
                    VStack(alignment: .center) {
                        Text("Nothing found")
                        Button("Reload") { reactionsVM.reload() }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            case "Reposts":
                switch repostsVM.state {
                case .initializing, .loading:
                    ProgressView()
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                        .onAppear { repostsVM.load() }
                        .task(id: "profileInteractions") {
                            do {
                                try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
                                
                                Task { @MainActor in
                                    if repostsVM.state == .loading || repostsVM.state == .initializing {
                                        repostsVM.state = .timeout
                                    }
                                }
                            } catch { }
                        }
                case .ready:
                    ForEach(repostsVM.posts) { nrPost in
                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                            Box(nrPost: nrPost) {
                                PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                            }
                        }
                        //                    .id(nrPost.id)
                        .onBecomingVisible {
                            // SettingsStore.shared.fetchCounts should be true for below to work
                            repostsVM.prefetch(nrPost)
                        }
                        .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                        .listRowSeparator(.hidden)
                        .listRowBackground(themes.theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                case .timeout:
                    VStack(alignment: .center) {
                        Text("Nothing found")
                        Button("Reload") { repostsVM.reload() }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            case "Zaps":
                switch zapsVM.state {
                case .initializing, .loading:
                    ProgressView()
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                        .onAppear { zapsVM.load() }
                        .task(id: "profileInteractions") {
                            do {
                                try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
                                
                                Task { @MainActor in
                                    if zapsVM.state == .loading || zapsVM.state == .initializing {
                                        zapsVM.state = .timeout
                                    }
                                }
                            } catch { }
                        }
                case .ready:
                    ForEach(zapsVM.posts) { nrPost in
                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                            Box(nrPost: nrPost) {
                                PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                                    .padding(.top, 20) // bit more padding so we have some space to put zap
                            }
                        }
                        //                    .id(nrPost.id)
                        .onBecomingVisible {
                            // SettingsStore.shared.fetchCounts should be true for below to work
                            zapsVM.prefetch(nrPost)
                        }
                        .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                        .overlay(alignment: .topLeading) {
                            if let zap = zapsVM.zapsMap[nrPost.id] {
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
                                .background(themes.theme.accent)
                                .clipShape(Capsule())
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(themes.theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                case .timeout:
                    VStack(alignment: .center) {
                        Text("Nothing found")
                        Button("Reload") { zapsVM.reload() }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            default:
                Text("🧩")
            }
            
        } header: {
            Picker("Type", selection: $selectedType) {
                Text("Conversations")
                    .tag("Conversations")
                Text("Reactions")
                    .tag("Reactions")
                Text("Zaps")
                    .tag("Zaps")
                Text("Reposts")
                    .tag("Reposts")
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            .listRowBackground(themes.theme.listBackground)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }
}
