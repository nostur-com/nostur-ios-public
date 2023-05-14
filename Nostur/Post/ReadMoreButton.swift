//
//  ReadMoreButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/05/2023.
//

import SwiftUI

struct ReadMoreButton: View {
    var nrPost:NRPost
    
    var moreItems:Int { nrPost.previewWeights.moreItemsCount }
    
    var body: some View {
        HStack {
            Text("This post has \(moreItems) more \(moreItems > 1 ? "items" : "item")")
            Button("Show") { navigateTo(nrPost) }
                .buttonStyle(.bordered)
        }
        .padding(.leading, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            navigateTo(nrPost)
        }
    }
}

struct ReadMoreButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let nostrReport = PreviewFetcher.fetchNRPost("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                ReadMoreButton(nrPost: nostrReport)
            }
        }
        .withPreviewEnvironment()
    }
}
