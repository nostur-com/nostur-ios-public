//
//  ReadMoreButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/05/2023.
//

import SwiftUI

/// Compact chevron to expand truncated post content.
///
/// Hit-testing is limited to the chevron (plus padding). Do **not** wrap this in a
/// full-size `Color.clear` overlay — that steals taps from nested embeds' own
/// show-more controls (first tap expands the outer post, second tap expands the embed).
struct ShowMoreChevronButton: View {
    @Environment(\.theme) private var theme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.compact.down")
                .foregroundColor(.white)
                .padding(5)
                .padding(.top, 5)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .foregroundColor(theme.accent)
                }
        }
        .buttonStyle(.plain)
        // Slightly larger hit target around the chevron only
        .padding(10)
        .contentShape(Rectangle())
    }
}

struct ReadMoreButton: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.containerID) private var containerID
    @Environment(\.theme) private var theme
    var nrPost:NRPost
    
    var moreItems:Int { nrPost.previewWeights?.moreItemsCount ?? 0 }
    
    var body: some View {
        HStack {
            if moreItems > 1 {
                Text("This post has \(moreItems) more items", comment: "Message shown when there are more items in a post")
            }
            else if moreItems == 1 {
                Text("This post has 1 more item", comment: "Message shown when a post has 1 more item")
            }
            Button(String(localized: "Show", comment: "Button to show more items in a post")) {
                guard !nxViewingContext.contains(.preview) else { return }
                navigateTo(nrPost, context: containerID)
            }
                .buttonStyle(.bordered)
        }
        .padding(.leading, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
        )
        .onTapGesture {
            guard !nxViewingContext.contains(.preview) else { return }
            navigateTo(nrPost, context: containerID)
        }
    }
}

struct ReadMoreButton_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            VStack {
                if let nostrReport = PreviewFetcher.fetchNRPost("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                    ReadMoreButton(nrPost: nostrReport)
                }
            }
        }
    }
}
