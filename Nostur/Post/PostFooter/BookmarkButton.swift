//
//  BookmarkButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct BookmarkButton: View {
    private let nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    private var isFirst: Bool
    private var isLast: Bool
    private var theme: Theme

    @State private var showColorSelector = false
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
        self.theme = theme
    }
    
    var body: some View {
        Image(systemName: footerAttributes.bookmarked ? "bookmark.fill" : "bookmark")
            .padding(.trailing, isLast && !IS_CATALYST ? 0 : 10) // On mac need space for scrollbar
            .padding(.leading, isFirst ? 0 : 10)
            .padding(.vertical, 5)
            .foregroundColor(footerAttributes.bookmarked ? footerAttributes.bookmarkColor : theme.footerButtons)
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture()
                    .onEnded { _ in
                        self.longTap()
                    }
            )
            .highPriorityGesture(
                TapGesture()
                    .onEnded { _ in
                        tap()
                    }
            )
            .overlay { // "orange", "red", "blue", "purple", "green", "brown" (BOOKMARK_COLORS)
                if showColorSelector {
                    HStack(spacing: 0) {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.brown)
                            .contentShape(Rectangle())
                            .padding(.leading, 10)
                            .padding(.trailing, 10)
                            .padding(.vertical, 10)
                            .onTapGesture {
                                self.addBookmark(.brown)
                                showColorSelector = false
                            }
                        
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.red)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .onTapGesture {
                                self.addBookmark(.red)
                                showColorSelector = false
                            }
                        
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.blue)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .onTapGesture {
                                self.addBookmark(.blue)
                                showColorSelector = false
                            }
                        
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.purple)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .onTapGesture {
                                self.addBookmark(.purple)
                                showColorSelector = false
                            }
                        
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.green)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .onTapGesture {
                                self.addBookmark(.green)
                                showColorSelector = false
                            }
                        
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.orange)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .onTapGesture {
                                self.addBookmark(.orange)
                                showColorSelector = false
                            }
                        
                        Image(systemName: "bookmark")
                            .foregroundColor(.orange)
                            .contentShape(Rectangle())
                            .padding(.leading, 10)
                            .padding(.trailing, 10)
                            .padding(.vertical, 10)
                            .onTapGesture {
                                self.removeBookmark()
                                showColorSelector = false
                            }
                    }
                        
                    .background(theme.listBackground)
                    .zIndex(1)
                    .offset(x: -115)
//                        .frame(width: 100, height: 100)
                    
                }
            }
            .zIndex(1)
    }
    
    private func tap() {
        guard !showColorSelector else { return }
        if footerAttributes.bookmarked {
            self.removeBookmark()
        }
        else {
            self.addBookmark()
        }
    }
    
    private func addBookmark(_ color: Color = .orange) {
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()

        // If already bookmarked, just change color
        if footerAttributes.bookmarked {
            Bookmark.updateColor(nrPost.id, color: color)
            
            bg().perform { // Update cache
                accountCache()?.addBookmark(nrPost.id, color: color)
            }
            return
        }
        
        // Otherwise, normal add bookamrk
        Bookmark.addBookmark(nrPost, color: color)
        self.footerAttributes.bookmarkColor = color
        bg().perform {
            accountCache()?.addBookmark(nrPost.id, color: color)
        }
    }
    
    private func removeBookmark() {
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        Bookmark.removeBookmark(nrPost)
        bg().perform {
            accountCache()?.removeBookmark(nrPost.id)
        }
    }
    
    private func longTap() {
        showColorSelector = true
    }
}



#Preview("Bookmark button") {
    
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        HStack(spacing: 0) {
            Circle()
                .foregroundColor(Color.random)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER + 10.0 + 10.0, alignment: .top)
                .fixedSize()
            VStack(spacing: 10) {
                if let p = PreviewFetcher.fetchNRPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3") {
                    BookmarkButton(nrPost: p, isLast: true, theme: Themes.default.theme)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                else {
                    Text("Nothing")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.trailing, 10)
        }
        .padding(.top, 100)
        .padding(.vertical, 10)
        .background(.gray.opacity(0.1))
        .frame(width: .infinity, height: 150)
        .clipped()
//        .fixedSize()
    }
}
