//
//  CustomizableFooter.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/10/2023.
//


import SwiftUI

struct FooterButton: Identifiable {
    let id:String
    var isFirst = false
    var isLast = false
}

struct CustomizableFooterFragmentView: View {
    @ObservedObject private var settings:SettingsStore = .shared
    
    private var buttons:[FooterButton] {
        Array(self.settings.footerButtons)
            .map({
                FooterButton(
                    id: String($0),
                    isFirst: Array(self.settings.footerButtons).first == $0,
                    isLast: Array(self.settings.footerButtons).last == $0
                )
            })
    }
    
    @EnvironmentObject private var theme:Theme
    private let nrPost:NRPost
    private var isDetail = false
    
    init(nrPost: NRPost, isDetail: Bool = false) {
        self.nrPost = nrPost
        self.isDetail = isDetail
    }
    
    var body: some View {
        //        #if DEBUG
        //        let _ = Self._printChanges()
        //        #endif
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                ForEach(buttons) { button in
                    switch button.id {
                    case "💬":
                        ReplyButton(nrPost: nrPost, isDetail: isDetail, isFirst: button.isFirst, isLast: button.isLast)
                    case "🔄":
                        RepostButton(nrPost: nrPost, isFirst: button.isFirst, isLast: button.isLast)
                    case "+":
                        LikeButton(nrPost: nrPost, isFirst: button.isFirst, isLast: button.isLast)
                    case "⚡️":
                        if IS_NOT_APPSTORE { // Only available in non app store version
                            ZapButton(nrPost: nrPost, isFirst: button.isFirst, isLast: button.isLast)
                                .opacity(nrPost.contact?.anyLud ?? false ? 1 : 0.3)
                                .disabled(!(nrPost.contact?.anyLud ?? false))
                        }
                        else {
                            EmptyView()
                        }
                    case "🔖":
                        BookmarkButton(nrPost: nrPost, isFirst: button.isFirst, isLast: button.isLast)
                    default:
                        ReactionButton(nrPost: nrPost, reactionContent:button.id, isFirst: button.isFirst, isLast: button.isLast)
                    }
                    if !button.isLast {
                        Spacer()
                    }
                }
            }
            .frame(height: 28)
            
            // UNDO SEND AND SENT TO RELAYS
            OwnPostFooter(nrPost: nrPost)
        }
        .foregroundColor(theme.footerButtons)
        .font(.system(size: 14))
    }
}


struct CustomizablePreviewFooterFragmentView: View {
    
    public var footerButtons:String = "💬🔄+💯💜⚡️🔖"
    
    private var buttons:[FooterButton] {
        Array(self.footerButtons)
            .map({
                FooterButton(
                    id: String($0),
                    isFirst: Array(self.footerButtons).first == $0,
                    isLast: Array(self.footerButtons).last == $0
                )
            })
    }
    
    @EnvironmentObject var theme:Theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                ForEach(buttons) { button in
                    switch button.id {
                    case "💬":
                        HStack {
                            Image("ReplyIcon")
                            Text("0").opacity(0)
                        }
                        .padding(.vertical, 5)
                        .padding(.leading, button.isFirst ? 0 : 5)
                        .padding(.trailing, button.isLast ? 0 : 5)
                    case "🔄":
                        // REPOST
                        HStack {
                            Image("RepostedIcon")
                            Text("0").opacity(0)
                        }
                        .padding(.vertical, 5)
                        .padding(.leading, button.isFirst ? 0 : 5)
                        .padding(.trailing, button.isLast ? 0 : 5)
                    case "+":
                        // LIKE
                        HStack {
                            Image("LikeIcon")
                            Text("0").opacity(0)
                        }
                        .padding(.vertical, 5)
                        .padding(.leading, button.isFirst ? 0 : 5)
                        .padding(.trailing, button.isLast ? 0 : 5)
                    case "⚡️":
                        if IS_NOT_APPSTORE { // Only available in non app store version
                            Image("BoltIcon")
                                .padding(.vertical, 5)
                                .padding(.leading, button.isFirst ? 0 : 5)
                                .padding(.trailing, button.isLast ? 0 : 5)
                        }
                        else {
                            EmptyView()
                        }
                    case "🔖":
                        Image("BookmarkIcon")
                            .padding(.vertical, 5)
                            .padding(.leading, button.isFirst ? 0 : 5)
                            .padding(.trailing, button.isLast ? 0 : 5)
                    default:
                        Text(button.id)
                        .padding(.vertical, 5)
                        .padding(.leading, button.isFirst ? 0 : 5)
                        .padding(.trailing, button.isLast ? 0 : 5)
                    }
                    if !button.isLast {
                        Spacer()
                    }
                }
            }
            .frame(height: 28)
        }
        .foregroundColor(theme.footerButtons)
        .font(.system(size: 14))
        
        
    }
}

#Preview("Customizable Footer") {
    PreviewContainer({ pe in
        pe.loadPosts()
    }) {
        VStack(spacing: 0) {
            
            CustomizablePreviewFooterFragmentView()
            
            if let p = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0") {
                CustomizableFooterFragmentView(nrPost: p)
            }
        }
    }
}

let IS_NOT_APPSTORE = ((Bundle.main.infoDictionary?["NOSTUR_IS_DESKTOP"] as? String) ?? "NO") != "NNO"

