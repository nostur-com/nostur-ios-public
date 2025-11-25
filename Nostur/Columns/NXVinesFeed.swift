//
//  NXVinesFeed.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/11/2025.
//

import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect
import Combine

struct NXVinesFeed: View {
    @AppStorage("enable_live_events") private var enableLiveEvents: Bool = true
    @Environment(\.theme) private var theme
    
    private var vm: NXColumnViewModel
    private let posts: [NRPost]
    private let isVisible: Bool
    @ObservedObject private var vmInner: NXColumnViewModelInner
    
    init(vm: NXColumnViewModel, posts: [NRPost], isVisible: Bool) {
        self.vm = vm
        self.posts = posts
        self.vmInner = vm.vmInner
        self.isVisible = isVisible
    }
    
    var body: some View {
        GeometryReader { geo in
            Container {
                if #available(iOS 17.0, *) {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(posts, id: \.id) { post in
                                PostRowDeletable(nrPost: post, isVisible: isVisible, theme: theme)
                                    .environment(\.availableHeight, geo.size.height)
                                    .environment(\.availableWidth, geo.size.width)
                                    .frame(height: geo.size.height)
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                } else {
                    ScrollView {
                        LazyVStack {
                            ForEach(posts, id: \.id) { post in
                                PostRowDeletable(nrPost: post, isVisible: isVisible, theme: theme)
                                    .environment(\.availableHeight, geo.size.height)
                                    .environment(\.availableWidth, geo.size.width)
                            }
                        }
                    }
                }
            }
            .background(theme.listBackground)
            
            // Handle going to detail and back
            .onAppear {
                vm.resumeViewUpdates()
            }
            .onDisappear {
                // When opening detail, the feed would still update in background using withAnimation { },
                // but because its not visible the hack to keep scroll position doesn't work
                // so we pause() updates (and resume() in onAppear {})
                vm.pauseViewUpdates()
            }
        }
    }
}
