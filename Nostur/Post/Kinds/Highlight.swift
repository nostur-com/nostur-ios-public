//
//  Highlight.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

// Hightlight note
struct Highlight: View {
    @ObservedObject var nrPost:NRPost
    let hideFooter:Bool // For rendering in NewReply
    let inThread:Bool // For rendering in thread
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
//    @ObservedObject var event:Event
    @ObservedObject var settings:SettingsStore = .shared
    
    init(nrPost: NRPost, hideFooter:Bool = true, inThread:Bool = false, connect:ThreadConnectDirection? = nil) {
        self.nrPost = nrPost
//        self.event = nrPost.event
        self.hideFooter = hideFooter
        self.inThread = inThread
        self.connect = connect
    }
    
    let THREAD_LINE_OFFSET = 34.0
    
    var body: some View {
        
        HStack(alignment: .top, spacing:0) {
            PFP(pubkey: nrPost.pubkey, pictureUrl: nrPost.contact?.pictureUrl, isFollowing: nrPost.contact?.following ?? false)
                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT)
                .background(alignment: .top, content: {
                    Color("LightGray")
                        .frame(width: 2, height: 20)
                        .offset(x:0, y: -20)
                        .opacity(connect == .top || connect == .both ? 1 : 0)
                })
                .onTapGesture {
                    navigateTo(ContactPath(key: nrPost.pubkey)) // TODO: if nrPost.contact navigate with that else by .pubkey
                }
                .padding(.horizontal, DIMENSIONS.POST_ROW_PFP_HPADDING)

            VStack(alignment:.leading, spacing: 3) {// Post container
                HStack { // name + reply + context menu
                    NoteHeaderView(nrPost: nrPost)
                    Spacer()
                    NoteMenuView(nrPost: nrPost)
                }
                if !inThread {
                    ReplyingToFragmentView(nrPost: nrPost)
//                            .padding(.bottom, 3)
                        .contentShape(Rectangle())
                        .onTapGesture { navigateTo(nrPost) }
                }
                VStack {
                    Text(nrPost.content ?? "")
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .italic()
                        .padding(20)
                        .overlay(alignment:.topLeading) {
                            Image(systemName: "quote.opening")
                                .foregroundColor(Color.secondary)
                        }
                        .overlay(alignment:.bottomTrailing) {
                            Image(systemName: "quote.closing")
                                .foregroundColor(Color.secondary)
                        }
                    
                    if let hl = nrPost.highlightData, let hlPubkey = hl.highlightAuthorPubkey {
                        HStack {
                            Spacer()
                            PFP(pubkey: hlPubkey, pictureUrl: hl.highlightAuthorPicture, size: 20, isFollowing: hl.highlightAuthorIsFollowing)
                                .onTapGesture {
                                    navigateTo(ContactPath(key: hlPubkey))
                                }
                            Text(hl.highlightAuthorName ?? "Unknown")
                                .onTapGesture {
                                    navigateTo(ContactPath(key: hlPubkey))
                                }
                        }
                        .padding(.trailing, 20)
                    }
                    HStack {
                        Spacer()
                        if let url = nrPost.highlightData?.highlightUrl {
                            Text("[\(url)](\(url))")
                                .lineLimit(1)
                                .font(.caption)
                        }
                    }
                    .padding(.trailing, 20)
                }
                .padding(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(.regularMaterial, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateTo(nrPost)
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    FooterFragmentView(nrPost: nrPost)
                        .padding(.top, 10)
                }
            }
            .padding(.bottom, 10)
        }
        .background(alignment: .leading) {
            Color("LightGray")
                .frame(width: 2)
                .offset(x: THREAD_LINE_OFFSET, y: 18)
                .opacity(connect == .bottom || connect == .both ? 1 : 0)
        }
        .padding(.trailing, DIMENSIONS.KIND1_TRAILING)
        .background(alignment: .leading) {
            Color.systemBackground.frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH+(DIMENSIONS.POST_ROW_PFP_HPADDING))
                .padding(.top, DIMENSIONS.POST_ROW_PFP_HEIGHT)
                .onTapGesture {
                    navigateTo(nrPost)
                }
        }
        
    }
}

struct Highlight_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let nrPost = PreviewFetcher.fetchNRPost("6e00b687cdb567eda5093d54e6f73577ecae928f00a85c3b09dddbf2da52adc1") {
                Highlight(nrPost: nrPost)
            }
        }
        .withPreviewEnvironment()
    }
}
