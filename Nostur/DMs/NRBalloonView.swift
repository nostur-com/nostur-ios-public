//
//  BalloonView.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI

struct NRBalloonView: View {
    @EnvironmentObject private var dim: DIMENSIONS
    public var event: Event
    public var isSentByCurrentUser: Bool
    public var time: String
    @State private var contentElements: [ContentElement] = []
    @EnvironmentObject var themes: Themes
    
    var body: some View {
        HStack {
            if isSentByCurrentUser {
                Spacer()
            }
            
            if event.noteText == "(Encrypted content)" {
                NRTextDynamic(convertToHieroglyphs(text: event.noteText))
            }
            else if !contentElements.isEmpty {
                DMContentRenderer(pubkey: event.pubkey, contentElements: contentElements, availableWidth: dim.listWidth, theme: themes.theme, isSentByCurrentUser: isSentByCurrentUser)
//                    .debugDimensions("DMContentRenderer")
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSentByCurrentUser ? themes.theme.accent : themes.theme.background)
                    )
                    .background(alignment: isSentByCurrentUser ? .bottomTrailing : .bottomLeading) {
                        Image(systemName: "moon.fill")
                            .foregroundColor(isSentByCurrentUser ? themes.theme.accent : themes.theme.background)
                            .scaleEffect(x: isSentByCurrentUser ? 1 : -1)
                            .rotationEffect(.degrees(isSentByCurrentUser ? 35 : -35))
                            .offset(x: isSentByCurrentUser ? 10 : -10, y: 0)
                            .font(.system(size: 25))
                    }
                    .padding(.horizontal, 10)
                    .padding(isSentByCurrentUser ? .leading : .trailing, 50)
                    .overlay(alignment: isSentByCurrentUser ? .bottomLeading : .bottomTrailing) {
                        Text(time)
                            .frame(alignment: isSentByCurrentUser ? .leading : .trailing)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                            .padding(isSentByCurrentUser ? .leading : .trailing, 5)
                    }
            }
            
            if !isSentByCurrentUser {
                Spacer()
            }
        }
        .onAppear {
            // Take width of NRContentTextRendererInner > NRTextFixed.debugDimensions("NRTextFixed")
            // Subtract that from dim.listWidth. We need to pass that result (98.0) to NRContentElementBuilder.buildElements(_ event:Event, dm:Bool, availableWidth: CGFloat?) so our NRTextFixed calculates correct heights and doesn't cut off
            let (elements, _, _) = NRContentElementBuilder.shared.buildElements(input: event.noteText, fastTags: event.fastTags, event: event , primaryColor: isSentByCurrentUser ? .white : themes.theme.primary)
            self.contentElements = elements
        }
    }
}
