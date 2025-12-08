//
//  EmojiColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//


import SwiftUI
import NavigationBackport

struct EmojiColumn: View {
    @Environment(\.theme) var theme
    @StateObject private var vm = EmojiFeedViewModel()
    @State private var showSettings = false
    
    var body: some View {
        EmojiFeed()
            .environmentObject(vm)
            .modifier { // need to hide glass bg in 26+
                if #available(iOS 26.0, *) {
                    $0.toolbar {
                        settingsButton
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
                else {
                    $0.toolbar {
                        settingsButton
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NBNavigationStack {
                    EmojiFeedSettings(vm: vm)
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
    
    @ToolbarContentBuilder
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
                showSettings = true
            }
        }
    }
}

#Preview {
    EmojiColumn()
}
