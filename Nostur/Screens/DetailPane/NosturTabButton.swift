//
//  NosturTabButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/06/2023.
//

import SwiftUI
import NavigationBackport

// Tabs for DetailPane, not main feeds
struct NosturTabButton: View {
    @Environment(\.theme) private var theme
    public var isSelected: Bool = false
    public var onSelect: () -> Void
    public var onClose: () -> Void
    @ObservedObject public var tab: TabModel
    private var isArticle: Bool { tab.isArticle }
    
    @State private var isHoveringCloseButton = false
    @State private var isHoveringTab = false
    @State private var showGallerySettings = false
    
    var body: some View {
        HStack(spacing: 5) {
            if IS_CATALYST {
                Image(systemName: "xmark")
                    .foregroundColor(isHoveringTab ? .gray : .clear)
                    .padding(4)
                    .contentShape(Rectangle())
                    .background(isHoveringCloseButton ? .gray.opacity(0.1) : .clear)
                    .onHover { over in
                        isHoveringCloseButton = over
                    }
                    .onTapGesture {
                        self.onClose()
                    }
            }
            else {
                Image(systemName: "xmark").foregroundColor(.gray)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.onClose()
                    }
            }
            Text(tab.navigationTitle)
                .lineLimit(1)
                .foregroundColor(theme.accent)
                .frame(maxWidth: 150)
            
            if let galleryVM = tab.galleryVM {
                Text(String(format: "%ih", galleryVM.ago)).lineLimit(1)
                    .font(.caption)
                    .foregroundColor(theme.accent.opacity(0.5))
                
                Image(systemName: "gearshape")
                    .onTapGesture {
                        showGallerySettings = true
                    }
                    .sheet(isPresented: $showGallerySettings, content: {
                        NBNavigationStack {
                            GalleryFeedSettings(vm: galleryVM)
                                .environment(\.theme, theme)
                        }
                        .nbUseNavigationStack(.never)
                        .presentationBackgroundCompat(theme.listBackground)
                    })
                    .foregroundColor(theme.accent)
                    .padding(.leading, 5)
            }
        }
        .padding(.trailing, 23)
        .padding(.vertical, 10)
        .padding(.leading, 5)
        .background(isSelected ? (isArticle ? theme.secondaryBackground : theme.listBackground) : theme.background)
        .contentShape(Rectangle())
        .onHover { over in
            isHoveringTab = over
        }
        .onTapGesture {
            self.onSelect()
        }
    }
}
