////
////  NRKinds.swift
////  Nostur
////
////  Created by Fabian Lachman on 26/05/2023.
////
//
//import SwiftUI
//
//
//// We don't expect to show these, but anyone can quote or reply to any event so we still need to show something
//let KNOWN_VIEW_KINDS: Set<Int64> = [0,3,4,5,7,1984,9734,9735,30009,8,30008]
//
//// Need to clean up, AnyKind is only in Kind1Both?? shouldn't be there
//struct AnyKind: View {
//    @EnvironmentObject private var dim: DIMENSIONS
//    private var nrPost: NRPost
//    private var hideFooter: Bool = false
//    private var autoload: Bool = false
//    private var availableWidth: CGFloat
//    private var theme: Theme
//    
//    @State private var didStart = false
//    
//    init(_ nrPost: NRPost, hideFooter: Bool = false, autoload: Bool = false, availableWidth: CGFloat, theme: Theme) {
//        self.nrPost = nrPost
//        self.hideFooter = hideFooter
//        self.autoload = autoload
//        self.availableWidth = availableWidth
//        self.theme = theme
//    }
//    
//    var body: some View {
//        if SUPPORTED_VIEW_KINDS.contains(nrPost.kind) {
//            switch nrPost.kind {
//                case 1: // generic olas
//                    if (nrPost.kTag ?? "" == "20"), let imageUrl = nrPost.imageUrls.first {
//                        ContentRenderer(nrPost: nrPost, isDetail: false, fullWidth: true, availableWidth: availableWidth, forceAutoload: autoload, theme: theme, didStart: $didStart)
//                            .padding(.vertical, 10)
//                    }
//                    else {
//                        EmptyView()
//                    }
//                case 20:
//                if let imageUrl = nrPost.imageUrls.first {
//                        VStack {
//                            let iMeta: iMetaInfo? = findImeta(nrPost.fastTags, url: imageUrl.absoluteString) // TODO: More to NRPost.init?
//                            MediaContentView(
//                                media: MediaContent(
//                                    url: imageUrl,
//                                    dimensions: iMeta?.size,
//                                    blurHash: iMeta?.blurHash
//                                ),
//                                availableWidth: dim.listWidth,
//                                placeholderHeight: dim.listWidth * (iMeta?.aspect ?? 1.0),
//                                contentMode: .fill,
//                                imageUrls: nrPost.imageUrls,
//                                autoload: autoload
//                            )
//                            .padding(.horizontal, -10)
//                            .overlay(alignment: .bottomTrailing) {
//                                if nrPost.imageUrls.count > 1 {
//                                    Text("\(nrPost.imageUrls.count - 1) more")
//                                        .fontWeightBold()
//                                        .foregroundColor(.white)
//                                        .padding(5)
//                                        .background(.black)
//                                        .allowsHitTesting(false)
//                                }
//                            }
//                            
//                            ContentRenderer(nrPost: nrPost, isDetail: false, fullWidth: true, availableWidth: availableWidth, forceAutoload: autoload, theme: theme, didStart: $didStart)
//                                .padding(.vertical, 10)
//                        }
//                    }
//                    else {
//                        EmptyView()
//                    }
//                case 99999:
//                    let title = nrPost.eventTitle ?? "Untitled"
//                    if let eventUrl = nrPost.eventUrl {
//                        VideoEventView(title: title, url: eventUrl, summary: nrPost.eventSummary, imageUrl: nrPost.eventImageUrl, autoload: true, theme: theme)
//                            .padding(.vertical, 10)
//                    }
//                    else {
//                        EmptyView()
//                    }
////                case 9735: TODO: ....
////                    ZapReceipt(sats: , receiptPubkey: , fromPubkey: , from: )
//                default:
//                    EmptyView()
//            }
//        }
//        else if KNOWN_VIEW_KINDS.contains(nrPost.kind) {
//            KnownKindView(nrPost: nrPost, hideFooter: hideFooter, theme: theme)
//                .padding(.vertical, 10)
//        }
//        else {
//            UnknownKindView(nrPost: nrPost, isEmbedded: true, theme: theme)
//                .padding(.vertical, 10)
//        }
//    }
//}
//
//
