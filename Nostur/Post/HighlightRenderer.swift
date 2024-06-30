//
//  HighlightRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/05/2023.
//

import SwiftUI

// TODO: Not sure why we have Highlight() and HighlightRenderer(). Can maybe remove one.
struct HighlightRenderer: View {
    private let nrPost:NRPost
    @ObservedObject private var highlightAttributes:NRPost.HighlightAttributes
    private var theme:Theme
    
    init(nrPost: NRPost, theme: Theme) {
        self.nrPost = nrPost
        self.highlightAttributes = nrPost.highlightAttributes
        self.theme = theme
    }
    
    var body: some View {
        VStack {
            Text(nrPost.content ?? "")
                .fixedSize(horizontal: false, vertical: true)
                .fontItalic()
                .padding(20)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let firstE = nrPost.firstE {
                        navigateTo(NotePath(id: firstE))
                    }
                    else if let aTag = nrPost.fastTags.first(where: { $0.0 == "a" }),
                            let naddr = try? ShareableIdentifier(aTag: aTag.1) {
                            navigateTo(Naddr1Path(naddr1: naddr.bech32string))
                    }
                }
                .overlay(alignment:.topLeading) {
                    Image(systemName: "quote.opening")
                        .foregroundColor(Color.secondary)
                }
                .overlay(alignment:.bottomTrailing) {
                    Image(systemName: "quote.closing")
                        .foregroundColor(Color.secondary)
                }
            
            if let hlAuthorPubkey = highlightAttributes.authorPubkey {
                HStack {
                    Spacer()
                    PFP(pubkey: hlAuthorPubkey, nrContact: highlightAttributes.contact, size: 20)
                    Text(highlightAttributes.anyName ?? "Unknown")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateTo(ContactPath(key: hlAuthorPubkey))
                }
                .padding(.trailing, 40)
            }
            HStack {
                Spacer()
                if let url = highlightAttributes.url, let md = try? AttributedString(markdown:"[\(url)](\(url))") {
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
                .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
        )
    }
}

import NavigationBackport

struct HighlightRenderer_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            NBNavigationStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    HighlightRenderer(nrPost: nrPost, theme: Themes.default.theme)
                }
            }
        }
    }
}
