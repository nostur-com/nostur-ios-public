////
////  Kind1.swift
////  Same as Kind1Default.swift but for full width images
////  TODO: Need to make just a flag on Kind1 and remove this
////  Nostur
////
////  Created by Fabian Lachman on 11/05/2023.
////
//
//import SwiftUI
//
//// Note Full width
//struct Kind1: View {
//    @EnvironmentObject private var dim: DIMENSIONS
//    @ObservedObject private var pfpAttributes: PFPAttributes
//    @ObservedObject var settings:SettingsStore = .shared
//    
//    private let nrPost: NRPost
//    private let hideFooter: Bool // For rendering in NewReply
//    private let missingReplyTo: Bool // For rendering in thread
//    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
//    private let isReply: Bool // is reply of PostDetail
//    private let isDetail: Bool
//    private let grouped: Bool
//    private let forceAutoload: Bool
//    private var theme: Theme
//    @State private var didStart = false
//    
//    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, grouped:Bool = false, forceAutoload: Bool = false, theme: Theme) {
//        self.nrPost = nrPost
//        self.pfpAttributes = nrPost.pfpAttributes
//        self.hideFooter = hideFooter
//        self.missingReplyTo = missingReplyTo
//        self.connect = connect
//        self.isReply = isReply
//        self.isDetail = isDetail
//        self.grouped = grouped
//        self.forceAutoload = forceAutoload
//        self.theme = theme
//    }
//    
//    let THREAD_LINE_OFFSET = 34.0
//    
//    var imageWidth: CGFloat {
//        // FULL WIDTH IS ON
//        
//        // LIST OR LIST PARENT
//        if !isDetail { return dim.listWidth - 20 }
//        
//        // DETAIL
//        if isDetail && !isReply { return dim.availablePostDetailRowImageWidth() }
//        
//        // DETAIL PARENT OR REPLY
//        return dim.availablePostDetailRowImageWidth()
//    }
//    
//    @State var showMiniProfile = false
//    
//    
//}
//
//
//
//struct Kind1_Previews: PreviewProvider {
//    static var previews: some View {
//        PreviewContainer({ pe in
//            pe.loadPosts()
//        }) {
//            SmoothListMock {
//                Box {
//                    if let nrPost = PreviewFetcher.fetchNRPost() {
//                        VStack(spacing: 0) {
//                            Kind1(nrPost: nrPost, theme: Themes.default.theme)
//                            CustomizableFooterFragmentView(nrPost: nrPost, isDetail: false, theme: Themes.default.theme)
//                        }
//                    }
//                }
//            }
//        }
//    }
//}
