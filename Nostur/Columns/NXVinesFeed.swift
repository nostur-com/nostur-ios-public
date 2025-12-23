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
    @Environment(\.theme) private var theme

    private var vm: NXColumnViewModel
    private let posts: [NRPost]
    private let isVisible: Bool
    @ObservedObject private var vmInner: NXColumnViewModelInner

    // Track current index for paging and arrow navigation
    @State private var currentIndex: Int = 0

    init(vm: NXColumnViewModel, posts: [NRPost], isVisible: Bool) {
        self.vm = vm
        self.posts = posts
        self.vmInner = vm.vmInner
        self.isVisible = isVisible
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if #available(iOS 17.0, *) {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0, pinnedViews: []) {
                                ForEach(Array(posts.enumerated()), id: \.element.id) { idx, post in
                                    PostRowDeletable(nrPost: post, isVisible: isVisible, theme: theme)
                                        .environment(\.availableHeight, geo.size.height)
                                        .environment(\.availableWidth, geo.size.width)
                                        .frame(height: geo.size.height)
                                        .id(post.id)
                                        .background(
                                            Color.clear
                                                .onAppear {
                                                    guard IS_DESKTOP_COLUMNS() else { return }
                                                    // Optionally, try to update currentIndex when page changes
                                                    // This is a naive approach; for full reliability use a PreferenceKey-based solution
                                                    if currentIndex != idx {
                                                        currentIndex = idx
                                                    }
                                                }
                                        )
                                }
                            }
                        }
                        .scrollTargetBehavior(.paging)
                        .onChange(of: currentIndex) { newIdx in
                            guard IS_CATALYST else { return }
                            // Scroll to the post with the new index (animated)
                            if posts.indices.contains(newIdx) {
                                withAnimation {
                                    scrollProxy.scrollTo(posts[newIdx].id, anchor: .top)
                                }
                            }
                        }
                        .overlay(alignment: .center) {
                            if IS_CATALYST { // buttons on macOS (columns and normal mode)
                                VStack {
                                    HStack {
                                        Spacer()
                                        VStack(spacing: 20) {
                                            // UP Arrow
                                            Button {
                                                if currentIndex > 0 {
                                                    currentIndex -= 1
                                                }
                                            } label: {
                                                Image(systemName: "chevron.up.circle.fill")
                                                    .resizable()
                                                    .frame(width: 32, height: 32)
                                                    .foregroundColor(.white)
                                                    .shadow(radius: 8)
                                            }
                                            .buttonStyle(.plain)
                                            .opacity(currentIndex > 0 ? 1 : 0)
                                            
                                            // DOWN Arrow
                                            Button {
                                                if currentIndex < posts.count - 1 {
                                                    currentIndex += 1
                                                }
                                            } label: {
                                                Image(systemName: "chevron.down.circle.fill")
                                                    .resizable()
                                                    .frame(width: 32, height: 32)
                                                    .foregroundColor(.white)
                                                    .shadow(radius: 8)
                                            }
                                            .buttonStyle(.plain)
                                            .opacity(currentIndex < posts.count - 1 ? 1 : 0)
                                        }
                                        .padding(.top, 190)
                                        .padding(.trailing, 18)
                                    }
                                    Spacer()
                                }
                                .allowsHitTesting(true)
                            }
                        }
                        .background(theme.listBackground)
                        .onAppear {
                            vm.resumeViewUpdates()
                        }
                        .onDisappear {
                            vm.pauseViewUpdates()
                        }
                    }
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
                    .background(theme.listBackground)
                    .onAppear {
                        vm.resumeViewUpdates()
                    }
                    .onDisappear {
                        vm.pauseViewUpdates()
                    }
                }
            }
        }
    }
}
