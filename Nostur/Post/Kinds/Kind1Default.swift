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
    @ObservedObject var nrPost:NRPost
    let hideFooter:Bool // For rendering in NewReply
    let inThread:Bool // For rendering in thread
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    let isReply:Bool // is reply on PostDetail
    let isDetail:Bool
     
    let sp:SocketPool = .shared
    let up:Unpublisher = .shared
    @ObservedObject var settings:SettingsStore = .shared
    
    init(nrPost: NRPost, hideFooter:Bool = true, inThread:Bool = false, connect:ThreadConnectDirection? = nil, isReply:Bool = false, isDetail:Bool = false) {
        self.nrPost = nrPost
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
            PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact)
                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT)
                .background(alignment: .top) {
                    Color("LightGray")
                        .frame(width: 2, height: 20)
                        .offset(x:0, y: -20)
                        .opacity(connect == .top || connect == .both ? 1 : 0)
                }
                .onTapGesture {
                    navigateTo(ContactPath(key: nrPost.pubkey))
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
                if let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata:fileMetadata, availableWidth: imageWidth)
                }
                else {
                    if (nrPost.kind != 1) {
                        Label("kind \(Double(nrPost.kind).clean) type not (yet) supported", systemImage: "exclamationmark.triangle.fill")
                            .hCentered()
                            .frame(maxWidth: .infinity)
                            .background(Color("LightGray").opacity(0.2))
                    }
                    if let subject = nrPost.subject {
                        Text(subject)
                            .fontWeight(.bold)
                            .lineLimit(3)
                            
                    }
                    ContentRenderer(nrPost: nrPost, fullWidth: false, availableWidth: imageWidth)
                        .frame(maxWidth: .infinity, alignment:.leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(nrPost)
                        }
                    if (nrPost.previewWeights.moreItems) {
                        ReadMoreButton(nrPost: nrPost)
                            .padding(.vertical, 5)
                            .hCentered()
                    }
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    FooterFragmentView(nrPost: nrPost)
                        .padding(.top, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(nrPost)
                        }
                }
            }
            .padding(.bottom, 10)
            .background(alignment: .topLeading) {
                Color.systemBackground
                    .frame(height: 25)
                    .padding(.trailing, 45) // Space for NoteMenu tapping
                    .onTapGesture {
                        navigateTo(nrPost)
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
                    navigateTo(nrPost)
                }
        }
        
    }
}

struct Kind1Default_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let nrPost = PreviewFetcher.fetchNRPost("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                Kind1Default(nrPost: nrPost)
            }
            
            if let nrPost = PreviewFetcher.fetchNRPost() {
                Kind1Default(nrPost: nrPost)
            }
        }
        .withPreviewEnvironment()
    }
}
