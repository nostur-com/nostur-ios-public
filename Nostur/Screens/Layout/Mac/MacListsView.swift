//
//  MacListsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import SwiftUI
import NavigationBackport

let COLUMN_SPACING = 1.0

@available(iOS 16.0, *)
struct MacListsView: View {
//    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
//    @EnvironmentObject private var screenSpace: ScreenSpace
    
    let SIDEBAR_WIDTH: CGFloat = 50.0
    @StateObject private var vm: MacListState = .shared

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
                    SideTabs(columnsCount: $vm.columnsCount, selectedTab: $vm.selectedTab)
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
                        
                            DMContainer()
                                .environment(\.horizontalSizeClass, .compact)
                                .environment(\.availableWidth, columnWidth)
                                .tag("Messages")
                                .toolbar(.hidden, for: .tabBar)
                        }
                        .frame(width: columnWidth)
                        .debugDimensions()
                    
                    // Extra lists (+ -)
                    ForEach(0..<max(1,vm.columnsCount), id:\.self) { columnIndex in
                        MacList(availableWidth: columnSize(geo.size.width)) {
                            ColumnViewWrapper(availableFeeds: availableFeeds)
                        }
                        .id(columnIndex)
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
                .onChange(of: vm.columnsCount) { _ in
                    let newColumnSize = columnSize(geo.size.width)
                    if columnWidth != newColumnSize {
                        columnWidth = newColumnSize
                    }
                }
            }
            .onAppear {
                availableFeeds = CloudFeed.fetchAll(context: DataProvider.shared().viewContext)
                    .filter {
                        switch $0.feedType {
                            case .picture(_):
                                return true
                            case .pubkeys(_):
                                return true
                            case .relays(_):
                                return true
                            case .followSet(_), .followPack(_):
                                return true
                            default:
                                return false
                        }
                    }
            }
            .withSheets()
            .withLightningEffect()
        }
    }
    
    func columnSize(_ availableWidth: CGFloat) -> CGFloat {
        let totalColumns = vm.columnsCount + 1 // +1 for main column
        let spacing = Double((totalColumns + 1)) * COLUMN_SPACING // +1 for side bar
        
        return CGFloat((availableWidth - SIDEBAR_WIDTH - spacing) / Double(totalColumns))
    }
}



@available(iOS 16.0, *)
struct ColumnViewWrapper: View {
    let availableFeeds:[CloudFeed]
    @State private var selectedFeed: CloudFeed? = nil
    @State private var navPath = NBNavigationPath()
    
    var body: some View {
//        Text("uuuh")
//        NXColumnConfigurator()
        ColumnView(availableFeeds: availableFeeds, selectedFeed: $selectedFeed, navPath: $navPath)
    }
}

@available(iOS 16.0, *)
struct ColumnView: View {
    @Environment(\.theme) private var theme
    let availableFeeds: [CloudFeed]
    @Binding var selectedFeed: CloudFeed?
    @Binding var navPath: NBNavigationPath
    @State private var columnConfig: NXColumnConfig?
    
    var body: some View {
        NBNavigationStack(path: $navPath) {
            ZStack {
                theme.listBackground

                
                if selectedFeed == nil {
                    VStack(alignment:.leading) {
                        
                        Text("Choose content for this column")
                        
                        Group {
                            
                            Button { } label: {
                                Label("Following", systemImage: "person.3.fill")
                            }
                            
                            Button { } label: {
                                Label("Custom Feed", systemImage: "person.3")
                            }
                            
                            Button { } label: {
                                Label("Profile", systemImage: "person.fill")
                            }
    //
    //                        Button { } label: {
    //                            Label("Private notes", systemImage: "note.text")
    //                        }
                            
                            Button { } label: {
                                Label("Hashtag", systemImage: "number")
                            }
                            
                            Button { } label: {
                                Label("Messages", systemImage: "envelope")
                            }
                            
                            Button { } label: {
                                Label("Notifications", systemImage: "bell.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                else if let columnConfig {
                    AvailableWidthContainer {
                        NXColumnView(config: columnConfig, isVisible: true)
                    }
                }
            }
            .withFeedSelectorToolbarMenu(feeds: availableFeeds, selectedFeed: $selectedFeed)
            .withNavigationDestinations()
            
            .onAppear {
                if let selectedFeed {
                    columnConfig = NXColumnConfig(id: selectedFeed.subscriptionId, columnType: selectedFeed.feedType, accountPubkey: selectedFeed.accountPubkey, name: selectedFeed.name_)
                }
            }
            .onChange(of: selectedFeed) { newValue in
                guard let newValue else { return }
                columnConfig = NXColumnConfig(id: newValue.subscriptionId, columnType: newValue.feedType, accountPubkey: newValue.accountPubkey, name: newValue.name_)
            }
        }
    }
}

struct MacListHeader: View {
    var title:String? = nil
    
    var body: some View {
        
        TabButton(action: {
            
        }, title: title ?? "List")
    }
}


struct MacList<Content: View>: View {
    
    private let content: Content
    private let availableWidth: CGFloat

    init(availableWidth: CGFloat = 600, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.availableWidth = availableWidth
    }
    
    var body: some View {
        content
            .environment(\.availableWidth, availableWidth)
    }
}




@available(iOS 16.0, *)
struct MacListsView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            
            pe.loadContacts()
            pe.loadCloudFeeds()
//            pe.loadRelayNosturLists()
            
        }, previewDevice:PreviewDevice(rawValue: "My Mac (Mac Catalyst)"), content: {
            MacListsView()
        })
    }
}
