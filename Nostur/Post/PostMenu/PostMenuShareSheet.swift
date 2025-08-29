//
//  PostMenuShareSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//

import SwiftUI
import NostrEssentials
import NavigationBackport

struct PostMenuShareSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    
    public let nrPost: NRPost
    public var onDismiss: (() -> Void)?
    
    @State private var postId: String = ""
    @State private var url: String = ""
    
    var body: some View {
        List {
            Section(header: Text("Nostr ID")) {
                CopyableTextView(text: postId, copyText: "nostr:\(postId)")
                    .lineLimit(1)
            }
            .listRowBackground(theme.background)
            
            Section(header: Text("Link")) {
                CopyableTextView(text: url)
                    .lineLimit(1)
            }
            .listRowBackground(theme.background)
            
            Section {
                Button(action: {
                    onDismiss?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.shareWeblink, nrPost)
                    }
                }) {
                    Label("Share link", systemImage: "link")
                }
                
                if #available(iOS 16, *), nrPost.kind != 30023 {
                    Button(action: {
                        onDismiss?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                            sendNotification(.sharePostScreenshot, nrPost)
                        }
                    }) {
                        Label("Share screenshot", systemImage: "photo")
                    }
                }
            }
            .listRowBackground(theme.background)
        }
        .onAppear {
            loadId()
        }
        
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { onDismiss?() }) {
                    Text("Done")
                }
            }
        }
    }
    
    private func loadId() {
        let relaysForHint: Set<String> = resolveRelayHint(forPubkey: nrPost.pubkey, receivedFromRelays: nrPost.footerAttributes.relays)
        
        if nrPost.kind >= 30000 && nrPost.kind < 40000 {
            if let si = try? NostrEssentials.ShareableIdentifier("naddr", kind: Int(nrPost.kind), pubkey: nrPost.pubkey, dTag: nrPost.dTag, relays: Array(relaysForHint)) {
                postId = si.identifier
                url = "https://njump.me/\(si.identifier)"
            }
        }
        else {
            if let si = try? NostrEssentials.ShareableIdentifier("nevent", id: nrPost.id, kind: Int(nrPost.kind), pubkey: nrPost.pubkey, relays: Array(relaysForHint)) {
                postId = si.identifier
                url = "https://njump.me/\(si.identifier)"
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadPosts()
    }) {
        NBNavigationStack {
            if let nrPost = PreviewFetcher.fetchNRPost() {
                PostMenuShareSheet(nrPost: nrPost)
            }
        }
    }
}
