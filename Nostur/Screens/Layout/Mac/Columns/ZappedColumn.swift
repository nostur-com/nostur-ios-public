//
//  ZappedColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//


import SwiftUI
import NavigationBackport

struct ZappedColumn: View {
    @Environment(\.theme) var theme: Theme
    @StateObject private var vm = ZappedViewModel()
    @State private var showSettings = false
    
    var body: some View {
        Zapped()
            .environmentObject(vm)
            .modifier { // need to hide glass bg in 26+
                if #available(iOS 26.0, *) {
                    $0.toolbar {
                        refreshButton
                            .sharedBackgroundVisibility(.hidden)
                        settingsButton
                            .sharedBackgroundVisibility(.hidden)
                    }
                }
                else {
                    $0.toolbar {
                        refreshButton
                        settingsButton
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NBNavigationStack {
                    ZappedFeedSettings(zappedVM: vm)
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
    
    @ToolbarContentBuilder
    private var refreshButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Group {
                if !isFeedLoading {
                    Button(String(localized: "Refresh", comment: "Toolbar action to refresh the zapped feed"), systemImage: "arrow.clockwise") {
                        Task {
                            await vm.refresh()
                        }
                    }
                }
            }
        }
    }
    
    private var isFeedLoading: Bool {
        switch vm.state {
        case .initializing, .loading, .fetchingFromFollows:
            return true
        case .ready, .timeout:
            return false
        }
    }
}

#Preview {
    ZappedColumn()
}
