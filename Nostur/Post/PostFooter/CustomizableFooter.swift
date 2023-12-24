//
//  CustomizableFooter.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/10/2023.
//


import SwiftUI
import Algorithms

struct CustomizableFooterFragmentView: View {
    @ObservedObject private var settings:SettingsStore = .shared
    @ObservedObject private var vmc:ViewModelCache = .shared
    private var theme:Theme
    
//    static let gridColumns = Array(repeating: GridItem(.flexible()), count: ViewModelCache.BUTTONS_PER_ROW)

    private let nrPost:NRPost
    private var isDetail = false
    
    init(nrPost: NRPost, isDetail: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.isDetail = isDetail
        self.theme = theme
    }
    
    var body: some View {
        //        #if DEBUG
        //        let _ = Self._printChanges()
        //        #endif
        VStack(alignment: .leading, spacing: 5) {
            ForEach(vmc.buttonRows) { row in
                HStack(spacing: 0) {
                    ForEach(row.buttons) { button in
                        switch button.id {
                        case "💬":
                            ReplyButton(nrPost: nrPost, isDetail: isDetail, isFirst: button.isFirst, isLast: button.isLast, theme: theme)
                        case "🔄":
                            RepostButton(nrPost: nrPost, isFirst: button.isFirst, isLast: button.isLast, theme: theme)
                        case "+":
                            LikeButton(nrPost: nrPost, isFirst: button.isFirst, isLast: button.isLast, theme: theme)
                        case "⚡️":
                            if IS_NOT_APPSTORE { // Only available in non app store version
                                ZapButton(nrPost: nrPost, isFirst: button.isFirst, isLast: button.isLast, theme: theme)
                                    .opacity(nrPost.contact?.anyLud ?? false ? 1 : 0.3)
                                    .disabled(!(nrPost.contact?.anyLud ?? false))
                            }
                            else {
                                EmptyView()
                            }
                        case "🔖":
                            BookmarkButton(nrPost: nrPost, isFirst: button.isFirst, isLast: button.isLast, theme: theme)
                        default:
                            ReactionButton(nrPost: nrPost, reactionContent:button.id, isFirst: button.isFirst, isLast: button.isLast)
                        }
                        if !button.isLast {
                            Spacer()
                        }
                    }
                }
            }
            
            // UNDO SEND AND SENT TO RELAYS
            OwnPostFooter(nrPost: nrPost, theme: theme)
                .offset(y: 14)
        }
        .padding(.top, 5)
        .padding(.bottom, 16)
        .foregroundColor(theme.footerButtons)
        .font(.system(size: 14))
    }
}

struct CustomizablePreviewFooterFragmentView: View {
    
    @State private var nrPost:NRPost? = nil
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var vmc:ViewModelCache = .shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let nrPost {
                CustomizableFooterFragmentView(nrPost: nrPost, isDetail: false, theme: themes.theme)
            }
        }
        .foregroundColor(themes.theme.footerButtons)
        .font(.system(size: 14))
        .onAppear {
            bg().perform {
                let tmpEvent = Event(context: bg())
                tmpEvent.flags = "tmp" // event should not be in database anymore after view is finished. add a flag just in case, so we can still clean up later.
                tmpEvent.id = "tmp"
                let tmpNRPost = NRPost(event: tmpEvent)
                DispatchQueue.main.async {
                    self.nrPost = tmpNRPost
                    bg().perform {
                        bg().delete(tmpEvent)
                    }
                }
            }
        }
    }
}

#Preview("Customizable Footer") {
    PreviewContainer({ pe in
        NRState.shared.loggedInAccount?.followingPFPs["7ecd3fe6353ec4c53672793e81445c2a319ccf0a298a91d77adcfa386b52f30d"] = URL(string: "https://files.peakd.com/file/peakd-hive/chekohler/AK297i3PX3mZpwVagu4FhZjVLcSW7UpEDv7b4mXRKSQav5vwsWgw46iGUcqSoDi.jpg")!
        NRState.shared.loggedInAccount?.followingPFPs["738f69184aeda675002b687fe47c8e9e2f7b1a267d6f9145b1193312f97c18ef"] = URL(string: "https://pbs.twimg.com/profile_images/1431273817477992452/arsE5HEn_400x400.jpg")!
        NRState.shared.loggedInAccount?.followingPFPs["79b647ba67c6f434b348e4af011e0984af14a459b6d86fd05e8f2ee8d32ec8c9"] = URL(string: "https://hitony.com/tony.gif")!
        pe.loadContacts()
        pe.loadRepliesAndReactions()
    }) {
        HStack(spacing: 0) {
            Circle()
                .foregroundColor(Color.random)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                .padding(.trailing, 10)
            VStack(spacing: 10) {
    
                CustomizablePreviewFooterFragmentView()
                
                Divider()
                
                if let p = PreviewFetcher.fetchNRPost("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81", withReplies: true) {
                    
                    CustomizableFooterFragmentView(nrPost: p, theme: Themes.default.theme)
                    
                    ForEach(p.replies) {
                        Text($0.pubkey)
                    }
                }
            }
        }
        .padding(5)
    }
}

let IS_NOT_APPSTORE = ((Bundle.main.infoDictionary?["NOSTUR_IS_DESKTOP"] as? String) ?? "NO") != "NNO"

let FOOTER_BUTTONS_PREVIEW = "💬🔄+⚡️😆👍🤔🔖"
