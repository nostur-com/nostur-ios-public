//
//  ZapLayout.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/06/2026.
//

import SwiftUI

// Copy pasta from PostLayout, removed generic post stuff, updated to handle zaps (9735 / 9734), only isItem view, updated with zap info
struct ZapLayout<Content: View, TitleContent: View>: View {
    
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    private var fromPubkey: String
    @ObservedObject private var nrContact: NRContact
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let fullWidth: Bool
    private let forceAutoload: Bool
    private let isItem: Bool  // true to put more emphasis on the item when it is not a text post
    
    private let THREAD_LINE_OFFSET = 24.0
    
    private var imageWidth: CGFloat {
        // FULL WIDTH IS OFF
        
        // LIST OR LIST PARENT
        if !isDetail { return fullWidth ? (availableWidth - 20) : DIMENSIONS.availableNoteRowWidth(availableWidth) }
        
        // DETAIL
        if isDetail && !isReply { return fullWidth ? DIMENSIONS.availablePostDetailRowImageWidth(availableWidth) : availableWidth }
        
        // DETAIL PARENT OR REPLY
        return DIMENSIONS.availablePostDetailRowImageWidth(availableWidth)
    }
    
    private let content: Content
    private let titleContent: TitleContent
    
    private var nxViewingContext: Set<NXViewingContextOptions>
    private var containerID: String
    private var theme: Theme
    private var availableWidth: CGFloat
    
    init(nrPost: NRPost, fromPubkey: String, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil,
         isReply: Bool = false, isDetail: Bool = false, fullWidth: Bool = true, forceAutoload: Bool = false, isItem: Bool = false,
         nxViewingContext: Set<NXViewingContextOptions> = [], containerID: String, theme: Theme, availableWidth: CGFloat, @ViewBuilder content: () -> Content, @ViewBuilder title: () -> TitleContent) {
        self.nrPost = nrPost
        self.fromPubkey = fromPubkey
        self.nrContact = NRContact.instance(of: fromPubkey)
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.forceAutoload = forceAutoload
        self.isItem = isItem
        self.content = content()
        self.titleContent = title()
        
        self.nxViewingContext = nxViewingContext
        self.containerID = containerID
        self.theme = theme
        self.availableWidth = availableWidth
    }
    
    var body: some View {
//#if DEBUG
//        let _ = nxLogChanges(of: Self.self)
//#endif
        if isDetail || fullWidth {
            fullWidthLayout
        }
        else {
            normalLayout
        }
    }
    
    @ViewBuilder
    private var normalLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            regularPFP
            
            // Post container
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) { // name + reply + context menu
                    ZappedFromName(pubkey: fromPubkey, nrPost: nrPost)
                    Spacer()
                    PostMenuButton(nrPost: nrPost, theme: theme)
                }
                
                if missingReplyTo || nxViewingContext.contains(.screenshot) {
                    ReplyingToFragmentView(nrPost: nrPost)
                }
                
                HStack(alignment: .top, spacing: 5) {
                    ZapAmountView(nrPost: nrPost, fromPubkey: fromPubkey, withPFP: false, nxViewingContext: nxViewingContext, containerID: containerID, theme: theme)
                    content
                }

                // No need for DetailFooterFragment here because .isDetail will always be in .fullWidthLayout
                
                if (!hideFooter && settings.rowFooterEnabled) && !isItem { // also no footer for items (only in Detail)
                    CustomizableFooterFragmentView(nrPost: nrPost, isItem: false, theme: theme)
                        .background(theme.listBackground)
                        .drawingGroup(opaque: true)
                }
            }
        }
//        .padding(.vertical, 10)
        .background(alignment: .leading) {
            if connect == .bottom || connect == .both {
                theme.lineColor
                    .frame(width: 1)
                    .offset(x: THREAD_LINE_OFFSET, y: 10)
            }
        }
    }
    
    @ViewBuilder
    private var fullWidthLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    regularPFP
                    ZapAmountView(nrPost: nrPost, fromPubkey: fromPubkey, withPFP: false, nxViewingContext: nxViewingContext, containerID: containerID, theme: theme)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 10) {
                        NRPostHeaderContainer(nrPost: nrPost, singleLine: false, isDetail: isDetail)
                        Spacer()
                        PostMenuButton(nrPost: nrPost, theme: theme)
                    }
                    
                    if missingReplyTo || nxViewingContext.contains(.screenshot) {
                        ReplyingToFragmentView(nrPost: nrPost)
                    }
                    
                    content
                }
            }
            
            if isDetail {
                DetailFooterFragment(nrPost: nrPost)
                    .padding(.top, 10)
            }
            
            if isDetail || ((!hideFooter && settings.rowFooterEnabled)) {
                CustomizableFooterFragmentView(nrPost: nrPost, isDetail: true, isItem: false, theme: theme)
                    .background(theme.listBackground)
                    .drawingGroup(opaque: true)
            }
        }
    }
    
    @ViewBuilder
    private var regularPFP: some View {
        if SettingsStore.shared.enableLiveEvents && LiveEventsModel.shared.livePubkeys.contains(fromPubkey) {
            LiveEventPFP(pubkey: fromPubkey, size: DIMENSIONS.POST_ROW_PFP_WIDTH, forceFlat: nxViewingContext.contains(.screenshot))
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                .background(alignment: .top) {
                    if connect == .top || connect == .both {
                        theme.lineColor
                            .frame(width: 1, height: 10)
                            .offset(x: -0.5, y: -10)
                    }
                }
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    if let liveEvent = LiveEventsModel.shared.nrLiveEvents.first(where: { $0.pubkey == fromPubkey || $0.participantsOrSpeakers.map { $0.pubkey }.contains(fromPubkey) }) {
                        if let status = liveEvent.status, status == "planned" {
                            navigateTo(liveEvent, context: containerID)
                        }
                        else if liveEvent.isLiveKit && (IS_CATALYST || IS_IPAD) { // Always do nests in tab on ipad/desktop
                            navigateTo(liveEvent, context: containerID)
                        }
                        else {
                            // LOAD NEST
                            if liveEvent.isLiveKit {
                                LiveKitVoiceSession.shared.activeNest = liveEvent
                            }
                            // ALREADY PLAYING IN .OVERLAY, TOGGLE TO .DETAILSTREAM
                            else if AnyPlayerModel.shared.nrLiveEvent?.id == liveEvent.id {
                                AnyPlayerModel.shared.viewMode = .detailstream
                            }
                            // LOAD NEW .DETAILSTREAM
                            else {
                                Task {
                                    await AnyPlayerModel.shared.loadLiveEvent(nrLiveEvent: liveEvent, availableViewModes: [.detailstream, .overlay, .audioOnlyBar])
                                }
                            }
                        }
                    }
                }
        }
        else {
            ZappablePFP(pubkey: fromPubkey, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, zapAtag: nrPost.aTag, forceFlat: nxViewingContext.contains(.screenshot))
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                .background(alignment: .top) {
                    if connect == .top || connect == .both {
                        theme.lineColor
                            .frame(width: 1, height: 10)
                            .offset(x: -0.5, y: -10)
                    }
                }
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    navigateToContact(pubkey: fromPubkey, nrPost: nrPost,  context: containerID)
                }
        }
    }
}

// Makes optional title possible in: ZapLayout { } title: { }

extension ZapLayout where TitleContent == EmptyView {
    
    init(nrPost: NRPost, fromPubkey: String, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil,
         isReply: Bool = false, isDetail: Bool = false, fullWidth: Bool = true, forceAutoload: Bool = false,
         isItem: Bool = false, nxViewingContext: Set<NXViewingContextOptions>, containerID: String, theme: Theme, availableWidth: CGFloat, @ViewBuilder content: () -> Content) {
     
        self.init(nrPost: nrPost, fromPubkey: fromPubkey, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect,
                  isReply: isReply, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: forceAutoload, isItem: isItem,
                  nxViewingContext: nxViewingContext, containerID: containerID, theme: theme, availableWidth: availableWidth,
                  content: content, title: { EmptyView() })
        
    }
}


struct ZapAmountView: View {

    private let nrPost: NRPost
    private var fromPubkey: String
    private var withPFP: Bool
    @ObservedObject private var nrContact: NRContact
    
    private var nxViewingContext: Set<NXViewingContextOptions>
    private var containerID: String
    private var theme: Theme
    
    init(nrPost: NRPost, fromPubkey: String,
         withPFP: Bool = true,
         nxViewingContext: Set<NXViewingContextOptions> = [],
         containerID: String,
         theme: Theme) {
        self.nrPost = nrPost
        self.fromPubkey = fromPubkey
        self.withPFP = withPFP
        self.nrContact = NRContact.instance(of: fromPubkey)
        self.nxViewingContext = nxViewingContext
        self.containerID = containerID
        self.theme = theme
    }
    
    var body: some View {
        VStack(alignment: .center) {
           HStack(spacing: 2) {
               Image(systemName: "bolt.fill")
                   .foregroundColor(theme.accent)
               if withPFP {
                   PFP(pubkey: fromPubkey, nrContact: nrContact, size: 20.0)
                       .frame(width: 20.0, height: 20.0)
                       .onTapGesture {
                           navigateTo(nrContact, context: containerID)
                       }
               }
               if nrPost.isPrivateZap {
                   Image(systemName: "lock.fill")
                       .font(.caption)
                       .foregroundColor(.secondary)
                       .infoText("This is a private zap, the sender is not revealed in public.")
               }
           }
           Text(nrPost.sats, format: .number.notation((.compactName)))
               .font(.title3)
           if let fiatPrice = ExchangeRateModel.shared.formattedFiatValue(sats: Double(nrPost.sats)) {
               Text("\(fiatPrice)")
                   .font(.caption)
                   .opacity(nrPost.sats != 0 ? 0.5 : 0)
           }
       }
       .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER)
    }
}
