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
    var isCompact = false
    @ViewBuilder var content: Content

    private var bottomOffset: CGFloat {
        isCompact ? -12.0 : -95.0
    }

    private var buttonsBottomOffset: CGFloat {
        isCompact ? -12.0 : -90.0
    }

    private var buttonsWidth: CGFloat {
        isCompact ? 42.0 : 56.0
    }

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
                            .lineLimit(isCompact ? 4 : 30)
                            .font(.caption)
                            .padding(.vertical, 5)
                    }
                }
                .font(isCompact ? .caption : .body)
                .padding(isCompact ? 8 : 10)
                .padding(.trailing, buttonsWidth)
                .offset(y: bottomOffset)
                
            }
        
            // Buttons
            .overlay(alignment: .bottomTrailing) {
                VideoPostButtons(nrPost: nrPost, isCompact: isCompact, theme: theme)
                    .padding(.horizontal, 3)
                    .frame(width: buttonsWidth)
                    .padding(.trailing, isCompact ? 3 : 7)
                    .offset(y: buttonsBottomOffset)
            }
    }
}
