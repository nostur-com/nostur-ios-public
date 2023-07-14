//
//  Kind1.swift
//  Same as Kind1Default.swift but for full width images
//  TODO: Need to make just a flag on Kind1 and remove this
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
    let missingReplyTo:Bool // For rendering in thread
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    let isReply:Bool // is reply of PostDetail
    let isDetail:Bool
    let grouped:Bool
    
    let sp:SocketPool = .shared
    let up:Unpublisher = .shared
    @ObservedObject var settings:SettingsStore = .shared
    
    init(nrPost: NRPost, hideFooter:Bool = true, missingReplyTo:Bool = false, connect:ThreadConnectDirection? = nil, isReply:Bool = false, isDetail:Bool = false, grouped:Bool = false) {
        self.nrPost = nrPost
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
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
    
    @State var showMiniProfile = false
    
    var body: some View {
        
        VStack(spacing: 3) {
            HStack(alignment: .top, spacing:0) {
                ZappablePFP(pubkey: nrPost.pubkey, contact: nrPost.contact?.mainContact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
                //                PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact)
                    .frame(width: 50, height: 50)
                    .onTapGesture {
                        if !IS_APPLE_TYRANNY {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
                        else {
                            withAnimation {
                                showMiniProfile = true
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if (showMiniProfile) {
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        sendNotification(.showMiniProfile,
                                                         MiniProfileSheetInfo(
                                                            pubkey: nrPost.pubkey,
                                                            contact: nrPost.contact?.mainContact,
                                                            zapEtag: nrPost.id,
                                                            location: geo.frame(in: .global).origin
                                                         )
                                        )
                                        showMiniProfile = false
                                    }
                            }
                            .frame(width: 10)
                            .zIndex(100)
                            .transition(.asymmetric(insertion: .scale(scale: 0.4), removal: .opacity))
                            .onReceive(receiveNotification(.dismissMiniProfile)) { _ in
                                showMiniProfile = false
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                NoteHeaderView(nrPost: nrPost, singleLine: false)
                Spacer()
                LazyNoteMenuButton(nrPost: nrPost)
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
                if missingReplyTo {
                    ReplyingToFragmentView(nrPost: nrPost)
                        .contentShape(Rectangle())
                        .onTapGesture { navigateTo(nrPost) }
                }
                if let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata:fileMetadata, availableWidth: imageWidth, fullWidth: true)
                }
                else {
                    if (nrPost.kind != 1) && (nrPost.kind != 6) {
                        Label(String(localized:"kind \(Double(nrPost.kind).clean) type not (yet) supported", comment: "Message shown when a 'kind X' post is not yet supported"), systemImage: "exclamationmark.triangle.fill")
                            .hCentered()
                            .frame(maxWidth: .infinity)
                            .background(Color("LightGray").opacity(0.2))
                    }
                    if let subject = nrPost.subject {
                        Text(subject)
                            .fontWeight(.bold)
                            .lineLimit(3)
                        
                    }
                    ContentRenderer(nrPost: nrPost, isDetail:isDetail, fullWidth: true, availableWidth: imageWidth)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(nrPost)
                        }
                    if !isDetail && (nrPost.previewWeights?.moreItems ?? false) {
                        ReadMoreButton(nrPost: nrPost)
                    }
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    FooterFragmentView(nrPost: nrPost)
                        .padding(.top, 10)
                    //                        .frame(idealHeight: 38.0)
                    //                        .fixedSize(horizontal: false, vertical: true)
                    //                     Make sure we get the correct size (is now 28.0 + 10.0)
                    //                        .readSize { newSize in
                    //                            print("Final Footer size: \(newSize)")
                    //                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(nrPost)
                        }
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

struct Kind1_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    Kind1(nrPost: nrPost)
                }
            }
        }
    }
}
