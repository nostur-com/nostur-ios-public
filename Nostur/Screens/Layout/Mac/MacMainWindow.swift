//
//  MacMainWindow.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import SwiftUI
import NavigationBackport

let COLUMN_SPACING = 1.0
let SIDEBAR_WIDTH: CGFloat = 50.0

struct MacMainWindow: View {
    @Environment(\.theme) private var theme
    

    @StateObject private var vm: MacColumnsVM = .shared

    @State var availableFeeds: [CloudFeed] = []
    @State private var columnWidth: CGFloat = 200.0 {
        didSet {
            ScreenSpace.shared.columnWidth = columnWidth
        }
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
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
                                .environmentObject(VideoPostPlaybackCoordinator())
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Main")
                            
                            NotificationsContainer()
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Notifications")

                            Search()
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Search")
                            
                            BookmarksTab()
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Bookmarks")
                        
                            MainDMsTab()
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Messages")

                        }
                        .frame(width: columnWidth)
                        .debugDimensions()
                    
                    // Extra lists (+ -)
                    ForEach(vm.columns) { columnConfig in
                        MacColumn(config: columnConfig)
                            .environmentObject(VideoPostPlaybackCoordinator())
                            .environment(\.availableWidth, columnSize(geo.size.width))
                            .environment(\.containerID, columnConfig.id.uuidString)
                            .modifier {
                                switch columnConfig.type {
                                case .DMs(_), .DMConversation(_):
                                    $0
                                case .notifications(let pubkey), .vines(let pubkey), .yaks(let pubkey), .photos(let pubkey):
                                    if pubkey == nil {
                                        $0
                                    }
                                    else {
                                        $0.simultaneousGesture(TapGesture().onEnded({ _ in
                                            AppState.shared.containerIDTapped = columnConfig.id.uuidString
                                        }))
                                    }
                                default:
                                    $0.simultaneousGesture(TapGesture().onEnded({ _ in
                                        AppState.shared.containerIDTapped = columnConfig.id.uuidString
                                    }))
                                }
                            }
                            .frame(width: columnWidth)
                            .debugDimensions()
                    }
                }
                .background(theme.background)
                
                .overlay(alignment: .center) {
                    OverlayPlayer()
                        .edgesIgnoringSafeArea(.bottom)
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
        pe.loadPosts()
        pe.loadBookmarks()
        pe.loadContacts()
        pe.loadCloudFeeds()
    }, previewDevice: PreviewDevice(rawValue: "My Mac (Mac Catalyst)"), content: {
        MacMainWindow()
    })
}
