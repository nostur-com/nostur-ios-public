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
    @StateObject private var conversationsVM: ProfileInteractionsConversationsVM
    @StateObject private var reactionsVM: ProfileInteractionsReactionsVM
    @State private var selectedType = "Conversations"
    
    init(pubkey: String) {
        _conversationsVM = StateObject(wrappedValue: ProfileInteractionsConversationsVM(pubkey))
        _reactionsVM = StateObject(wrappedValue: ProfileInteractionsReactionsVM(pubkey))
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
                                conversationsVM.state = .timeout
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
                        Text("Unable to fetch content")
                        Button("Try again") { conversationsVM.reload() }
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
                                reactionsVM.state = .timeout
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
                        Text("Unable to fetch content")
                        Button("Try again") { reactionsVM.reload() }
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

#Preview {
    let pubkey = "2779f3d9f42c7dee17f0e6bcdcf89a8f9d592d19e3b1bbd27ef1cffd1a7f98d1"
    
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.parseMessages(testInteractions())
    }) {
        List {
            ProfileInteractionsView(pubkey: pubkey)
                .listRowSpacing(10.0)
                .listRowInsets(EdgeInsets())
                .listSectionSeparator(.hidden)
                .listRowSeparator(.hidden)
        }
        .environment(\.defaultMinListRowHeight, 50)
        .listStyle(.plain)
        .scrollContentBackgroundHidden()
    }
}
