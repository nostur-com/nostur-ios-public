//
//  GalleryColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//


import SwiftUI
import NavigationBackport

struct GalleryColumn: View {
    @Environment(\.theme) var theme
    @StateObject private var vm = GalleryViewModel()
    @State private var showSettings = false
    
    var body: some View {
        Gallery()
            .environmentObject(vm)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
                        showSettings = true
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NBNavigationStack {
                    GalleryFeedSettings(vm: vm)
                        .environment(\.theme, theme)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close", systemImage: "xmark") {
                                  showSettings = false
                                }
                            }
                        }
                }
                .nbUseNavigationStack(.whenAvailable) // .never is broken on macCatalyst, showSettings = false will not dismiss  .sheet(isPresented: $showSettings) ..
                .presentationBackgroundCompat(theme.listBackground)
            }
    }
}

#Preview {
    GalleryColumn()
}
