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
                ProSidebarLayout {
                    SideTabs(vm: vm, selectedTab: $vm.selectedTab)
                        .frame(width: SIDEBAR_WIDTH)
                } columns: {
                    ProColumnOrder {
                        // Main list (following/notifications/bookmarks)
                        TabView(selection: $vm.selectedTab) {
                                PhoneViewIsh()
                                    .environmentObject(VideoPostPlaybackCoordinator())
                                    .environment(\.horizontalSizeClass, .compact)
                                    .environment(\.availableWidth, columnWidth)
                                    .modifier(ProMainColumnTabBarHidden())
                                    .tag("Main")
                            
                                NotificationsContainer()
                                    .environment(\.horizontalSizeClass, .compact)
                                    .environment(\.availableWidth, columnWidth)
                                    .modifier(ProMainColumnTabBarHidden())
                                    .tag("Notifications")

                                Search()
                                    .environment(\.horizontalSizeClass, .compact)
                                    .environment(\.availableWidth, columnWidth)
                                    .modifier(ProMainColumnTabBarHidden())
                                    .tag("Search")
                            
                                BookmarksTab()
                                    .environment(\.horizontalSizeClass, .compact)
                                    .environment(\.availableWidth, columnWidth)
                                    .modifier(ProMainColumnTabBarHidden())
                                    .tag("Bookmarks")
                        
                                MainDMsTab()
                                    .environment(\.horizontalSizeClass, .compact)
                                    .environment(\.availableWidth, columnWidth)
                                    .modifier(ProMainColumnTabBarHidden())
                                    .tag("Messages")

                            }
                            .modifier(ProMainColumnTabsStyle())
                            .frame(width: columnWidth)
                            .debugDimensions()

                    } extraColumns: {
                        // Independent feed columns
                        ForEach(IS_IPHONE ? vm.duoColumns : vm.columns) { columnConfig in
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
                .onValueChange(vm.duoColumnCount) { _, _ in
                    columnWidth = columnSize(geo.size.width)
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
        .modifier { content in
            if #available(iOS 27.1, *), IS_IPHONE {
                content.modifier(DuoProNavigation(vm: vm))
            }
            else {
                content
            }
        }
    }
    
    func columnSize(_ availableWidth: CGFloat) -> CGFloat {
        let totalColumns = (IS_IPHONE ? vm.duoColumns.count : vm.columns.count) + 1 // +1 for main column
        if IS_IPHONE {
            return max(0, (availableWidth - CGFloat(totalColumns + 1) * COLUMN_SPACING) / CGFloat(totalColumns))
        }
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

/// Duo uses native app controls; Catalyst keeps its existing sidebar.
struct ProSidebarLayout<Sidebar: View, Columns: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let columns: Columns

    var body: some View {
        if #available(iOS 26.0, *), IS_IPHONE {
            // Separate column navigation containers from the app's bar region.
            columns.padding(.horizontal, COLUMN_SPACING)
        }
        else {
            HStack(spacing: COLUMN_SPACING) {
                sidebar
                columns
            }
        }
    }
}

/// Sidebar selection must not be animated as a horizontal page transition.
/// A native tab container retains each tab's navigation and scroll state.
struct ProMainColumnTabsStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), IS_IPHONE {
            content
                .tabViewStyle(.tabBarOnly)
                // Match the neighboring scroll views' bottom drawing region.
                .ignoresSafeArea(.container, edges: .bottom)
        }
        else {
            content
        }
    }
}

/// Tab-bar visibility is a preference of each selected tab, not its container.
struct ProMainColumnTabBarHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *), IS_IPHONE {
            content.toolbar(.hidden, for: .tabBar)
        }
        else {
            content
        }
    }
}

/// Keep the column controlled by the app rail beside it. The platform choice is
/// stable, so changing tabs or the number of extra feeds retains the main stack.
struct ProColumnOrder<Primary: View, ExtraColumns: View>: View {
    var primaryOnRight: Bool = IS_IPHONE
    @ViewBuilder let primary: Primary
    @ViewBuilder let extraColumns: ExtraColumns

    var body: some View {
        HStack(spacing: COLUMN_SPACING) {
            if primaryOnRight {
                extraColumns
                primary
            }
            else {
                primary
                extraColumns
            }
        }
    }
}
