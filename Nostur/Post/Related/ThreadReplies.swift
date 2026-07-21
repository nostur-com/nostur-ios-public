//
//  ThreadReplies.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/05/2023.
//

import SwiftUI

struct ThreadReplies: View {
    @Environment(\.theme) private var theme
    @ObservedObject public var nrPost: NRPost
    @ObservedObject private var settings: SettingsStore = .shared
    @State private var showNotWoT = false
    @State private var didLoad = false
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        Group {
            if settings.nestedRepliesEnabled {
                NestedThreadReplies(nrPost: nrPost)
            }
            else {
                flatReplies
            }
        }
        .background(theme.listBackground)
        .onAppear {
            guard !didLoad else { return }
            guard !nrPost.plainTextOnly else { L.og.debug("plaintext enabled, probably spam") ; return }
            nrPost.loadGroupedReplies()
            didLoad = true
        }
        .onChange(of: settings.nestedRepliesEnabled) { _ in
            // Both lists are filled together; no reload required to switch modes.
            // Still reload if one list is empty (e.g. toggled before first load finished).
            guard didLoad else { return }
            if nrPost.nestedRepliesSorted.isEmpty && nrPost.groupedRepliesSorted.isEmpty {
                nrPost.loadGroupedReplies()
            }
        }
        .onReceive(receiveNotification(.blockListUpdated)) { _ in
            nrPost.loadGroupedReplies()
        }
        .onReceive(receiveNotification(.muteListUpdated)) { _ in
            nrPost.loadGroupedReplies()
        }
    }
    
    @ViewBuilder
    private var flatReplies: some View {
        LazyVStack(spacing: GUTTER) {
            if didLoad {
                if nrPost.groupedRepliesSorted.isEmpty && nrPost.groupedRepliesNotWoT.isEmpty {
                    Color.clear
                        .frame(height: 30) // need some space or footer buttons of detail post dissapear behind toolbar
                }
                ForEach(nrPost.groupedRepliesSorted) { reply in
                    PostOrThread(nrPost: reply, theme: theme, rootId: nrPost.id)
                        .id(reply.id)
                        .animation(Animation.spring(), value: nrPost.groupedRepliesSorted)
                }
                if !nrPost.groupedRepliesNotWoT.isEmpty {
                    Divider()
                    if WOT_FILTER_ENABLED() && !showNotWoT {
                        Button {
                            showNotWoT = true
                        } label: {
                           Text("Show more")
                                .padding(10)
                                .contentShape(Rectangle())
                        }
                        .padding(.bottom, 10)
                    }
                    if showNotWoT {
                        ForEach(nrPost.groupedRepliesNotWoT) { reply in
                            PostOrThread(nrPost: reply, theme: theme, rootId: nrPost.id)
                                .id(reply.id)
                        }
                        .animation(Animation.spring(), value: nrPost.groupedRepliesNotWoT)
                    }
                }
            }
        }
    }
}

import NavigationBackport

#Preview("Grouped replies") {
    let exampleId = "2e7119c8135375060ab0f3e40646869f7337ab86de32574ab1bf57dcd2a93754"
    
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        NBNavigationStack {
            if let nrPost = PreviewFetcher.fetchNRPost(exampleId, withReplies: true) {
                ScrollView {
                    ThreadReplies(nrPost: nrPost)
                        .environment(\.nxViewingContext, [.selectableText, .postReply, .detailPane])
                }
            }
        }
    }
}
