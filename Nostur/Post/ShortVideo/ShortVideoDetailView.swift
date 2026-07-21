//
//  ShortVideoDetailView.swift
//  Nostur
//
//  Full-width short video (Divine/Vine) detail — used when navigating from
//  notifications, bookmarks, etc. Avoids PostDetailView's padded layout and
//  "Post" nav chrome around the video.
//

import SwiftUI

struct ShortVideoDetailView: View {
    @Environment(\.theme) private var theme
    private let nrPost: NRPost
    private var navTitleHidden: Bool = false
    
    init(nrPost: NRPost, navTitleHidden: Bool = false) {
        self.nrPost = nrPost
        self.navTitleHidden = navTitleHidden
    }
    
    var body: some View {
        // GeometryReader + ignoresSafeArea so the video fills the full screen
        // including under the nav bar (same idea as ProfileBanner going under top).
        // toolbarBackground(.hidden) alone only clears the bar fill — content would
        // still be laid out *below* the reserved nav area, leaving an empty strip.
        GeometryReader { geo in
            VideoPost(nrPost: nrPost, isDetail: true, theme: theme)
                .environment(\.availableHeight, geo.size.height)
                .environment(\.availableWidth, geo.size.width)
                .environment(\.shortVideoAutoplayAudioEnabled, true)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(navTitleHidden)
        .modifier {
            if #available(iOS 16.0, *) {
                $0
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar) // light back chevron on video
            } else {
                $0
            }
        }
        .onAppear {
            nrPost.footerAttributes.loadFooter()
        }
    }
}
