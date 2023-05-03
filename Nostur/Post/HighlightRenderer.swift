//
//  HighlightRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/05/2023.
//

import SwiftUI

struct HighlightRenderer: View {
    var vPost:VPost
    
    var body: some View {
        VStack {
            Text(vPost.event.content ?? "")
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
            
            if let highlightAuthorPubkey = vPost.highlightAuthorPubkey {
                HStack {
                    Spacer()
                    PFP(pubkey: highlightAuthorPubkey, pictureUrl: vPost.highlightAuthorPicture, size: 20, isFollowing: vPost.highlightAuthorIsFollowing)
                    Text(vPost.highlightAuthorName ?? "Unknown")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateTo(ContactPath(key: highlightAuthorPubkey))
                }
                .padding(.trailing, 40)
            }
            HStack {
                Spacer()
                if let url = vPost.highlightUrl, let md = try? AttributedString(markdown:"[\(url)](\(url))") {
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
                .stroke(.regularMaterial, lineWidth: 1)
        )
    }
}

struct HighlightRenderer_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            if let vPost = PreviewFetcher.fetchVPost() {
                HighlightRenderer(vPost: vPost)
            }
        }
        .withPreviewEnvironment()
    }
}
