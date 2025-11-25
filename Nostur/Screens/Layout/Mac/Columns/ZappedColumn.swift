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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
                        showSettings = true
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
}

#Preview {
    ZappedColumn()
}
