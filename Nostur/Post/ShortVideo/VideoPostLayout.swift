//
//  VideoPostLayout.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/11/2025.
//

import SwiftUI

struct VideoPostLayout<Content: View>: View {
    let nrPost: NRPost
    let theme: Theme
    @ViewBuilder var content: Content

    
    var body: some View {
        self.content
            // Post info
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading) {
                    if let title = nrPost.eventTitle {
                        Text(title)
                            .foregroundStyle(Color.white)
                            .lineLimit(2)
                            .layoutPriority(1)
                            .fontWeightBold()
                            .padding(.vertical, 5)
                    }
                    
                    MinimalNoteTextRenderView(nrPost: nrPost, textColor: Color.white)
                    
                    if let summary = nrPost.eventSummary, !summary.isEmpty {
                        Text(summary)
                            .foregroundColor(Color.white)
                            .lineLimit(30)
                            .font(.caption)
                            .padding(.vertical, 5)
                    }
                }
                .padding(10)
                .offset(y: -65.0)
            }
        
            // Buttons
            .overlay(alignment: .bottomTrailing) {
                VideoPostButtons(nrPost: nrPost, theme: theme)
                    .padding(.horizontal, 3)
                    .frame(width: 56)
                    .padding(.trailing, 7)
                    .offset(y: -90.0)
            }
    }
}
