//
//  Kind1.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

// Note Full width
struct Kind1: View {
    @EnvironmentObject var dim:DIMENSIONS
    let vPost:VPost
    let hideFooter:Bool // For rendering in NewReply
    let inThread:Bool // For rendering in thread
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    let isReply:Bool // is reply of PostDetail
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
        // FULL WIDTH IS ON
        
        // LIST OR LIST PARENT
        if !isDetail { return dim.listWidth }
        
        // DETAIL
        if isDetail && !isReply { return dim.availablePostDetailRowImageWidth() }
        
        // DETAIL PARENT OR REPLY
        return dim.availablePostDetailRowImageWidth()
    }
    
    var body: some View {
        
        VStack(spacing: 3) {
            HStack(alignment: .top, spacing:0) {
                PFP(pubkey: vPost.pubkey, pictureUrl: event.contact?.picture, isFollowing: vPost.following)
                    .frame(width: 50, height: 50)
                    .onTapGesture {
                        navigateTo(ContactPath(key: vPost.pubkey)) // TODO: if vPost.contact navigate with that else by .pubkey
                    }
                    .padding(.horizontal, 10)
                NoteHeaderView(vPost: vPost, singleLine: false)
                Spacer()
                NoteMenuView(vPost: vPost)
                    .padding(.horizontal, 20)
            }
            .background(alignment: .leading) {
                Color.systemBackground
                    .padding(.leading, DIMENSIONS.ROW_PFP_SPACE)
                    .padding(.trailing, 60) // Space for NoteMenu tapping
                    .onTapGesture {
                        navigateTo(vPost)
                    }
            }
            .padding(.bottom, 10)
            VStack(alignment:.leading, spacing: 3) {// Post container
                ReplyingToFragmentView(vPost: vPost)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { navigateTo(vPost) }
                if vPost.event.kind == 1063 {
                    Kind1063(vPost, availableWidth: imageWidth)
                }
                else {
                    ContentRenderer(vPost: vPost, fullWidth: true, availableWidth: imageWidth)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(vPost)
                        }
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    FooterFragmentView(vPost: vPost)
                        .padding(10)
                        .onTapGesture {
                            navigateTo(vPost)
                        }
                }
            }
        }
    }
}

struct Kind1_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let vPost = PreviewFetcher.fetchVPost() {
                Kind1(vPost: vPost)
            }
        }
        .withPreviewEnvironment()
    }
}
