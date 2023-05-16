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
    @ObservedObject var nrPost:NRPost
    let hideFooter:Bool // For rendering in NewReply
    let inThread:Bool // For rendering in thread
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    let isReply:Bool // is reply of PostDetail
    let isDetail:Bool
//    @ObservedObject var event:Event
     
    let sp:SocketPool = .shared
    let up:Unpublisher = .shared
    @ObservedObject var settings:SettingsStore = .shared
    
    init(nrPost: NRPost, hideFooter:Bool = true, inThread:Bool = false, connect:ThreadConnectDirection? = nil, isReply:Bool = false, isDetail:Bool = false) {
        self.nrPost = nrPost
//        self.event = nrPost.event
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
                PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact)
                    .frame(width: 50, height: 50)
                    .onTapGesture {
                        navigateTo(ContactPath(key: nrPost.pubkey)) // TODO: if nrPost.contact navigate with that else by .pubkey
                    }
                    .padding(.horizontal, 10)
                NoteHeaderView(nrPost: nrPost, singleLine: false)
                Spacer()
                NoteMenuView(nrPost: nrPost)
                    .padding(.horizontal, 20)
            }
            .background(alignment: .leading) {
                Color.systemBackground
                    .padding(.leading, DIMENSIONS.ROW_PFP_SPACE)
                    .padding(.trailing, 60) // Space for NoteMenu tapping
                    .onTapGesture {
                        navigateTo(nrPost)
                    }
            }
            .padding(.bottom, 10)
            VStack(alignment:.leading, spacing: 3) {// Post container
                ReplyingToFragmentView(nrPost: nrPost)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { navigateTo(nrPost) }
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
                    ContentRenderer(nrPost: nrPost, fullWidth: true, availableWidth: imageWidth)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(nrPost)
                        }
                    if (nrPost.previewWeights.moreItems) {
                        ReadMoreButton(nrPost: nrPost)
                    }
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    FooterFragmentView(nrPost: nrPost)
                        .padding(10)
                        .onTapGesture {
                            navigateTo(nrPost)
                        }
                }
            }
        }
    }
}

struct Kind1_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let nrPost = PreviewFetcher.fetchNRPost() {
                Kind1(nrPost: nrPost)
            }
        }
        .withPreviewEnvironment()
    }
}
