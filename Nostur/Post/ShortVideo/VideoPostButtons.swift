//
//  VideoPostButtons.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/11/2025.
//

import SwiftUI

struct VideoPostButtons: View {
    @Environment(\.containerID) var containerID
    @ObservedObject private var settings: SettingsStore = .shared
    @ObservedObject private var vmc: ViewModelCache = .shared
    private var theme: Theme

    private let nrPost: NRPost
    private var isDetail = false
    private let isItem: Bool
    
    init(nrPost: NRPost, isDetail: Bool = false, isItem: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.isDetail = isDetail
        self.isItem = isItem
        self.theme = theme
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            postButtons
            
            // UNDO SEND AND SENT TO RELAYS
            if nrPost.ownPostAttributes.isOwnPost { // TODO: fixme
//                OwnPostFooter(nrPost: nrPost)
//                    .offset(y: 14)
            }
        }
        .padding(.top, 5)
        .padding(.bottom, 16)
        .foregroundColor(theme.footerButtons)
        .font(.system(size: 14))
    }
    
    @ViewBuilder
    private var postButtons: some View {
        VStack(spacing: 15.0) {
            Spacer()
            ZappablePFP(pubkey: nrPost.pubkey, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, zapAtag: nrPost.aTag, forceFlat: true)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                
                .onTapGesture {
                    navigateToContact(pubkey: nrPost.pubkey, nrPost: nrPost,  context: containerID)
                }
                .padding(.bottom, 15.0)
            ForEach(vmc.buttonRow) { button in
                switch button.id {
                case "💬":
                    VideoReplyButton(nrPost: nrPost, isDetail: isDetail, theme: theme)
                case "🔄":
                    VideoRepostButton(nrPost: nrPost, theme: theme)
                case "+":
                    VideoEmojiButton(nrPost: nrPost, theme: theme)
                case "⚡️", "⚡": // These are different. Apple Emoji keyboard creates \u26A1\uFE0F, but its the same as \u26A1 🤷‍♂️
                    if IS_NOT_APPSTORE { // Only available in non app store version
                        VideoZapButton(nrPost: nrPost, theme: theme)
                            .opacity(nrPost.contact.anyLud ? 1 : 0.3)
                            .disabled(!(nrPost.contact.anyLud))
                    }
                    else {
                        EmptyView()
                    }
                case "🔖":
                    VideoBookmarkButton(nrPost: nrPost, theme: theme)
                default:
                    VideoReactionButton(nrPost: nrPost, reactionContent:button.id)
                }
            }
        }
        .font(.system(size: 26))
    }
}
