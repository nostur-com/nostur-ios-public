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
    private let isCompact: Bool
    
    init(nrPost: NRPost, isDetail: Bool = false, isItem: Bool = false, isCompact: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.isDetail = isDetail
        self.isItem = isItem
        self.isCompact = isCompact
        self.theme = theme
    }

    private var profileImageSize: CGFloat {
        isCompact ? 30.0 : DIMENSIONS.POST_ROW_PFP_WIDTH
    }

    private var profileFrameSize: CGFloat {
        isCompact ? 36.0 : DIMENSIONS.POST_ROW_PFP_DIAMETER
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: isCompact ? 2 : 5) {
            Spacer()
            PostMenuButton(nrPost: nrPost, theme: theme)
                .offset(x: isCompact ? -4 : -7)
                .padding(.bottom, isCompact ? 10 : 20)
            
            ZappablePFP(pubkey: nrPost.pubkey, size: profileImageSize, zapEtag: nrPost.id, zapAtag: nrPost.aTag, forceFlat: true)
                .frame(width: profileFrameSize, height: profileFrameSize)
                
                .onTapGesture {
                    navigateToContact(pubkey: nrPost.pubkey, nrPost: nrPost,  context: containerID)
                }
                .padding(.bottom, isCompact ? 12.0 : 25.0)
            
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
            
            // UNDO SEND AND SENT TO RELAYS
            if nrPost.ownPostAttributes.isOwnPost { // TODO: fixme
//                OwnPostFooter(nrPost: nrPost)
//                    .offset(y: 14)
            }
        }
        .padding(.top, 5)
        .padding(.bottom, isCompact ? 8 : 16)
        .foregroundColor(theme.footerButtons)
        .font(.system(size: isCompact ? 18 : 24))
    }
}
