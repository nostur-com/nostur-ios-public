//
//  Kind1Default.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

// Note 1 default
struct Kind1Default: View {
    @EnvironmentObject var dim:DIMENSIONS
    let vPost:VPost
    let hideFooter:Bool // For rendering in NewReply
    let inThread:Bool // For rendering in thread
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    let isReply:Bool // is reply on PostDetail
    let isDetail:Bool
    @ObservedObject var event:Event
     
    let sp:SocketPool = .shared
    let up:Unpublisher = .shared
    @ObservedObject var settings:SettingsStore = .shared
    
    init(vPost: VPost, hideFooter:Bool = true, inThread:Bool = false, connect:ThreadConnectDirection? = nil, isReply:Bool = false, isDetail:Bool = false) {
        self.vPost = vPost
        self.event = vPost.event
        self.hideFooter = hideFooter
        self.inThread = inThread
        self.connect = connect
        self.isReply = isReply
        self.isDetail = isDetail
    }
    
    let THREAD_LINE_OFFSET = 34.0
    
    var imageWidth:CGFloat {
        // FULL WIDTH IS OFF
        
        // LIST OR LIST PARENT
        if !isDetail { return dim.availableNoteRowImageWidth() }
        
        // DETAIL
        if isDetail && !isReply { return dim.availablePostDetailImageWidth() }
        
        // DETAIL PARENT OR REPLY
        return dim.availablePostDetailRowImageWidth()
    }
    
    var body: some View {
        
        HStack(alignment: .top, spacing:0) {
            PFP(pubkey: vPost.pubkey, pictureUrl: event.contact?.picture ?? vPost.pictureUrl, isFollowing: vPost.following)
                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT)
                .background(alignment: .top) {
                    Color("LightGray")
                        .frame(width: 2, height: 20)
                        .offset(x:0, y: -20)
                        .opacity(connect == .top || connect == .both ? 1 : 0)
                }
                .onTapGesture {
                    navigateTo(ContactPath(key: vPost.pubkey)) // TODO: if vPost.contact navigate with that else by .pubkey
                }
                .padding(.horizontal, DIMENSIONS.POST_ROW_PFP_HPADDING)

            VStack(alignment:.leading, spacing: 3) {// Post container
                HStack { // name + reply + context menu
                    NoteHeaderView(vPost: vPost)
                    Spacer()
                    NoteMenuView(vPost: vPost)
                }
                if !inThread {
                    ReplyingToFragmentView(vPost: vPost)
//                            .padding(.bottom, 3)
                        .contentShape(Rectangle())
                        .onTapGesture { navigateTo(vPost) }
                }
                if vPost.event.kind == 1063 {
                    Kind1063(vPost, availableWidth: imageWidth)
                }
                else {
                    ContentRenderer(vPost: vPost, fullWidth: false, availableWidth: imageWidth)
                        .frame(maxWidth: .infinity, alignment:.leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(vPost)
                        }
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    FooterFragmentView(vPost: vPost)
                        .padding(.top, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(vPost)
                        }
                }
            }
            .padding(.bottom, 10)
            .background(alignment: .topLeading) {
                Color.systemBackground
                    .frame(height: 25)
                    .padding(.trailing, 45) // Space for NoteMenu tapping
                    .onTapGesture {
                        navigateTo(vPost)
                    }
            }
        }
        .background(alignment: .leading) {
            Color("LightGray")
                .frame(width: 2)
                .offset(x: THREAD_LINE_OFFSET, y: 18)
                .opacity(connect == .bottom || connect == .both ? 1 : 0)
        }
        .padding(.trailing, DIMENSIONS.KIND1_TRAILING)
        .background(alignment: .topLeading) {
            Color.systemBackground.frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH+(DIMENSIONS.POST_ROW_PFP_HPADDING))
                .padding(.top, DIMENSIONS.POST_ROW_PFP_HEIGHT)
                .onTapGesture {
                    navigateTo(vPost)
                }
        }
        
    }
}

struct Kind1Default_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let vPost = PreviewFetcher.fetchVPost() {
                Kind1Default(vPost: vPost)
            }
        }
        .withPreviewEnvironment()
    }
}
