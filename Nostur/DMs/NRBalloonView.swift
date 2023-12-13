//
//  BalloonView.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI

struct NRBalloonView: View {
    public var event: Event
    public var isSentByCurrentUser: Bool
    public var time: String
    @State private var contentElements:[ContentElement] = []
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
                DMContentRenderer(pubkey: event.pubkey, contentElements: contentElements, availableWidth: DIMENSIONS.shared.listWidth, theme: themes.theme)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSentByCurrentUser ? themes.theme.background : themes.theme.listBackground)
                    )
                    .background(alignment: isSentByCurrentUser ? .bottomTrailing : .bottomLeading) {
                        Image(systemName: "moon.fill")
                            .foregroundColor(isSentByCurrentUser ? themes.theme.background : themes.theme.listBackground)
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
                            .padding(isSentByCurrentUser ? .leading : .trailing, 19)
                    }
            }
            
            if !isSentByCurrentUser {
                Spacer()
            }
        }
        .onAppear {
            let (elements, _) = NRContentElementBuilder.shared.buildElements(event, dm: true)
            self.contentElements = elements
        }
    }
}
