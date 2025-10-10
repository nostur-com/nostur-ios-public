//
//  MacMainWindow.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import SwiftUI
import NavigationBackport

let COLUMN_SPACING = 1.0

@available(iOS 16.0, *)
struct MacMainWindow: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    
    let SIDEBAR_WIDTH: CGFloat = 50.0
    @StateObject private var vm: MacColumnsVM = .shared

    @State var availableFeeds: [CloudFeed] = []
    @State private var columnWidth: CGFloat = 200.0
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        Zoomable {
            GeometryReader { geo in
                HStack(spacing: COLUMN_SPACING) {
                    // Tabs on the side
                    SideTabs(vm: vm, selectedTab: $vm.selectedTab)
                        .frame(width: SIDEBAR_WIDTH)
                    
                    // Main list (following/notifications/bookmarks)
                    TabView(selection: $vm.selectedTab) {
                            PhoneViewIsh()
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Main")
                                .toolbar(.hidden, for: .tabBar)
                            
                            NotificationsContainer()
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Notifications")
                                .toolbar(.hidden, for: .tabBar)

                            Search()
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Search")
                                .toolbar(.hidden, for: .tabBar)
                            
                            BookmarksTab()
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Bookmarks")
                                .toolbar(.hidden, for: .tabBar)
                        
                            DMNavigationStack {
                                DMContainer()
                            }
                            .environment(\.horizontalSizeClass, .compact)
                            .environment(\.availableWidth, columnWidth)
                            .tag("Messages")
                            .toolbar(.hidden, for: .tabBar)
                        }
                        .frame(width: columnWidth)
                        .debugDimensions()
                    
                    // Extra lists (+ -)
                    ForEach(vm.columns) { columnConfig in
                        MacColumn(config: columnConfig)
                            .environment(\.availableWidth, columnSize(geo.size.width))
                            .environment(\.containerID, columnConfig.id.uuidString)
                            .frame(width: columnWidth)
                            .debugDimensions()
                    }
                }
                .onAppear {
                    columnWidth = columnSize(geo.size.width)
                }
                .onChange(of: geo.size.width) { newValue in
                    if newValue != columnWidth {
                        columnWidth = columnSize(geo.size.width)
                    }
                }
                .onChange(of: vm.columns) { _ in
                    let newColumnSize = columnSize(geo.size.width)
                    if columnWidth != newColumnSize {
                        columnWidth = newColumnSize
                    }
                }
            }
            .task {
                await vm.load()
            }
            .withSheets()
            .withLightningEffect()
        }
    }
    
    func columnSize(_ availableWidth: CGFloat) -> CGFloat {
        let totalColumns = vm.columns.count + 1 // +1 for main column
        let spacing = Double((totalColumns + 1)) * COLUMN_SPACING // +1 for side bar
        
        return CGFloat((availableWidth - SIDEBAR_WIDTH - spacing) / Double(totalColumns))
    }
}


@available(iOS 16.0, *)
#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadCloudFeeds()
    }, previewDevice: PreviewDevice(rawValue: "My Mac (Mac Catalyst)"), content: {
        MacMainWindow()
    })
}
