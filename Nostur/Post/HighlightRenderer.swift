//
//  HighlightRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/05/2023.
//

import SwiftUI

struct HighlightRenderer: View {
    @EnvironmentObject var theme:Theme
    let nrPost:NRPost
    
    var body: some View {
        VStack {
            Text(nrPost.content ?? "")
                .italic()
                .padding(20)
                .overlay(alignment:.topLeading) {
                    Image(systemName: "quote.opening")
                        .foregroundColor(Color.secondary)
                }
                .overlay(alignment:.bottomTrailing) {
                    Image(systemName: "quote.closing")
                        .foregroundColor(Color.secondary)
                }
            
            if let hl = nrPost.highlightData, let hlPubkey = hl.highlightAuthorPubkey {
                HStack {
                    Spacer()
                    PFP(pubkey: hlPubkey, nrContact: hl.highlightNrContact, size: 20)
                    Text(hl.highlightAuthorName ?? "Unknown")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateTo(ContactPath(key: hlPubkey))
                }
                .padding(.trailing, 40)
            }
            HStack {
                Spacer()
                if let url = nrPost.highlightData?.highlightUrl, let md = try? AttributedString(markdown:"[\(url)](\(url))") {
                    Text(md)
                        .lineLimit(1)
                        .font(.caption)
                }
            }
            .padding(.trailing, 40)
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(theme.lineColor.opacity(0.2), lineWidth: 1)
        )
    }
}

struct HighlightRenderer_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            NavigationStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    HighlightRenderer(nrPost: nrPost)
                }
            }
        }
    }
}
