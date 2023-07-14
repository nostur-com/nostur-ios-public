//
//  Kind1Default.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

// TODO: For performance replace all Xxx(nrPosts: nrPost) with specific attributes
// TODO: For performance, create separate Views per state dependency
// Note 1 default (not full-width)
struct Kind1Default: View {
    @EnvironmentObject var dim:DIMENSIONS
    @ObservedObject var nrPost:NRPost
    let hideFooter:Bool // For rendering in NewReply
    let missingReplyTo:Bool // For rendering in thread
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    let isReply:Bool // is reply on PostDetail
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
        // FULL WIDTH IS OFF
        
        // LIST OR LIST PARENT
        if !isDetail { return dim.availableNoteRowImageWidth() }
        
        // DETAIL
        if isDetail && !isReply { return dim.availablePostDetailImageWidth() }
        
        // DETAIL PARENT OR REPLY
        return dim.availablePostDetailRowImageWidth()
    }
    
    @State var showMiniProfile = false
    
    var body: some View {
//        let _ = Self._printChanges()
        HStack(alignment: .top, spacing: 0) {
            ZappablePFP(pubkey: nrPost.pubkey, contact: nrPost.contact?.mainContact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
//            PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact)
                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT)
                .background(alignment: .top) {
                    Color("LightGray")
                        .frame(width: 2, height: 20)
                        .offset(x:0, y: -20)
                        .opacity(connect == .top || connect == .both ? 1 : 0)
                }
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
                .padding(.horizontal, DIMENSIONS.POST_ROW_PFP_HPADDING)

            VStack(alignment:.leading, spacing: 3) { // Post container
                HStack { // name + reply + context menu
                    NoteHeaderView(nrPost: nrPost)
                    Spacer()
                    LazyNoteMenuButton(nrPost: nrPost)
                }
                .frame(idealHeight: 22.0)
                .fixedSize(horizontal: false, vertical: true)
//                     Make sure we get the correct size (is now 20.5 or 21.5 because nip05 icon?)
//                .readSize { newSize in
//                    print("NoteHeader size: \(newSize)")
//                }
                if missingReplyTo {
                    ReplyingToFragmentView(nrPost: nrPost)
//                            .padding(.bottom, 3)
                        .contentShape(Rectangle())
                        .onTapGesture { navigateTo(nrPost) }
                }
                if let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata:fileMetadata, availableWidth: imageWidth)
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
//                    Text("availableWidth: \(imageWidth.description)")
                    ContentRenderer(nrPost: nrPost, isDetail:isDetail, fullWidth: false, availableWidth: imageWidth)
                        .frame(maxWidth: .infinity, alignment:.leading)
                        .background(
                            Color.systemBackground
                                .onTapGesture {
                                    navigateTo(nrPost)
                                }
                        )
//                        .contentShape(Rectangle())
//                        .onTapGesture {
//                            navigateTo(nrPost)
//                        }
                    if !isDetail && (nrPost.previewWeights?.moreItems ?? false) {
                        ReadMoreButton(nrPost: nrPost)
                            .padding(.vertical, 5)
                            .hCentered()
                    }
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    FooterFragmentView(nrPost: nrPost)
                        .padding(.top, 10)
                        .frame(idealHeight: 38.0)
                        .fixedSize(horizontal: false, vertical: true)
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
            Color.clear.frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH+(DIMENSIONS.POST_ROW_PFP_HPADDING))
                .padding(.top, DIMENSIONS.POST_ROW_PFP_HEIGHT)
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateTo(nrPost)
                }
        }
        
    }
}

struct Kind1Default_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                    Kind1Default(nrPost: nrPost)
                }
                
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    Kind1Default(nrPost: nrPost)
                }
            }
            .withSheets()
        }
    }
}
