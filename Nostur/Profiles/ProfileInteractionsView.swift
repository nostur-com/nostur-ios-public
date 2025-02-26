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
    @StateObject private var vm: ProfileInteractionsViewModel
    @State private var selectedType = "Conversations"
    
    init(pubkey: String) {
        _vm = StateObject(wrappedValue: ProfileInteractionsViewModel(pubkey))
    }
    
    var body: some View {
        Section {
            switch vm.state {
            case .initializing, .loading:
                ProgressView()
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                    .onAppear { vm.load() }
                    .task(id: "profileInteractions") {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
                            vm.state = .timeout
                        } catch { }
                    }
            case .ready:
                ForEach(vm.posts) { nrPost in
                    ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                        Box(nrPost: nrPost) {
                            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                        }
                    }
                    //                    .id(nrPost.id)
                    .onBecomingVisible {
                        // SettingsStore.shared.fetchCounts should be true for below to work
                        vm.prefetch(nrPost)
                    }
                    .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                    .listRowSeparator(.hidden)
                    .listRowBackground(themes.theme.listBackground)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            case .timeout:
                VStack(alignment: .center) {
                    Text("Unable to fetch content")
                    Button("Try again") { vm.reload() }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } header: {
            Picker("Type", selection: $selectedType) {
                Text("Conversations")
                    .tag("Conversations")
                Text("Reactions")
                    .tag("Reactios")
                Text("Zaps")
                    .tag("Zaps")
                Text("Reposts")
                    .tag("Reposts")
            }
            .pickerStyle(.segmented)
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
