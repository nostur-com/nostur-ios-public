//
//  ReadMoreButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/05/2023.
//

import SwiftUI

struct ReadMoreButton: View {
    @EnvironmentObject private var themes:Themes
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
            Button(String(localized: "Show", comment: "Button to show more items in a post")) { navigateTo(nrPost) }
                .buttonStyle(.bordered)
        }
        .padding(.leading, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(themes.theme.lineColor.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            navigateTo(nrPost)
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
