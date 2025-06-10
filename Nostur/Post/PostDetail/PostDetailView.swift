//
//  PostDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/02/2023.
//

import SwiftUI
import CoreData
import NavigationBackport

struct PostDetailView: View {
    
//    static func == (lhs: Self, rhs: Self) -> Bool {
//        lhs.nrPost.id == rhs.nrPost.id && lhs.didLoad == rhs.didLoad
//    }
    
    @ObservedObject private var themes: Themes = .default
    private let nrPost: NRPost
    private var navTitleHidden: Bool = false
    @State private var didLoad = false
    @State private var didScroll = false
    
    init(nrPost: NRPost, navTitleHidden: Bool = false) {
        self.nrPost = nrPost
        self.navTitleHidden = navTitleHidden
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: GUTTER) { // 2 for space between (parents+detail) and replies
//                        Color.red
//                            .frame(height: 30)
//                            .debugDimensions()
                        PostAndParent(nrPost: nrPost,  navTitleHidden:navTitleHidden)
                        
                            // Around parents + detail (not replies)
                            .padding(10)
                            .background(themes.theme.listBackground)
                            .overlay(alignment: .bottom) {
                                themes.theme.background.frame(height: GUTTER)
                            }
//                            .background(themes.theme.background)
//                            .background(Color.blue)
//                        
//                        if (nrPost.kind == 443) {
//                            Text("Comments on \(nrPost.fastTags.first(where: { $0.0 == "r" } )?.1.replacingOccurrences(of: "https://", with: "") ?? "...")")
//                                .fontWeightBold()
//                                .navigationTitle("Comments on \(nrPost.fastTags.first(where: { $0.0 == "r" } )?.1.replacingOccurrences(of: "https://", with: "") ?? "...")")
//                                
//                        }
                        
                        // MARK: REPLIES TO OUR MAIN POST
                        if (nrPost.kind == 443) {
                            // SPECIAL HANDLING FOR WEBSITE COMMENTS
                            WebsiteComments(nrPost: nrPost)
                                .environment(\.nxViewingContext, [.selectableText, .postReply, .detailPane])
                        }
                        else if didLoad {
                            // NORMAL REPLIES TO A POST
                            ThreadReplies(nrPost: nrPost)
                                .environment(\.nxViewingContext, [.selectableText, .postReply, .detailPane])
                        }
                    }
//                    .background(themes.theme.listBackground)
//                    .background(Color.red)
                }
                .onAppear {
                    guard !didLoad else { return }
                    didLoad = true
                    
                    // If we navigated to this post by opening it from an embedded
                    nrPost.footerAttributes.loadFooter()
                    // And maybe we don't have parents so:
                    nrPost.loadParents()
                    
                }
                .onReceive(receiveNotification(.scrollToDetail)) { notification in
                    guard !didScroll else { return }
                    let detailId = notification.object as! String
                    didScroll = true
                    withAnimation {
                        proxy.scrollTo(detailId, anchor: .top)
                    }
                }
                .navigationTitleIf(nrPost.kind != 443, title: nrPost.replyToId != nil ? String(localized:"Thread", comment:"Navigation title when viewing a Thread") : String(localized:"Post.noun", comment: "Navigation title when viewing a Post"))
                          
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(navTitleHidden)
            }
        }
            .nosturNavBgCompat(themes: themes)
            .background(themes.theme.listBackground)
            .environment(\.nxViewingContext, [.selectableText, .detailPane])
    }
}

extension View {
    @ViewBuilder
    func navigationTitleIf(_ condition: Bool, title: String) -> some View {
        if condition {
            self.navigationTitle(title)
        }
        else {
            self
        }
    }
}

let THREAD_LINE_OFFSET = 24.0
