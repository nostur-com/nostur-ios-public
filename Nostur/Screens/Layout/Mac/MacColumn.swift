//
//  MacColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/10/2025.
//

import SwiftUI
import NavigationBackport

struct MacColumn: View {
    @ObservedObject private var vm: MacColumnsVM = .shared
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    
    // Doesn't get updates propagated, so only use for initial setup
    var config: MacColumnConfig
    
    @State private var columnType = MacColumnType.unconfigured // use instead of config.type
    private var selectedFeed: CloudFeed? {
        if case .cloudFeed(let cloudFeedId) = columnType {
            return vm.availableFeeds.first(where: { $0.id?.uuidString == cloudFeedId })
        }
        return nil
    }
    
    private var selectedTitle: String {
        switch columnType {
        case .unconfigured:
            return "Select Feed"
        case .cloudFeed(let cloudFeedId):
            return vm.availableFeeds.first(where: { $0.id?.uuidString == cloudFeedId })?.feedTitle() ?? "(Untitled)"
        case .hot:
            return String(localized: "Hot", comment: "Feed title")
        case .zapped:
            return String(localized: "Zapped", comment: "Feed title")
        case .emoji:
            return String(localized: "Funny", comment: "Feed title")
        case .articles:
            return String(localized: "Reads", comment: "Feed title")
        case .gallery:
            return String(localized: "Gallery", comment: "Feed title")
        case .discoverLists:
            return String(localized: "Lists & Follow Packs", comment: "Feed title")
        case .notifications:
            return String(localized: "Notifications", comment: "Feed title")
        case .following:
            return String(localized: "Following", comment: "Feed title")
        case .photos:
            return String(localized: "Photos", comment: "Feed title")
        case .mentions:
            return String(localized: "Mentions", comment: "Feed title")
        case .bookmarks:
            return String(localized: "Booksmarks", comment: "Feed title")
        case .DMs:
            return String(localized: "Messages", comment: "Feed title")
        case .newPosts:
            return String(localized: "New Posts", comment: "Feed title")
        }
    }
    
    @State private var navPath = NBNavigationPath()
    
    var body: some View {
        NBNavigationStack(path: $navPath) {
            ZStack {
                theme.listBackground
                
                switch columnType {
                case .unconfigured:
                    Text("unconfigured")
                case .cloudFeed(_):
                    if let selectedFeed {
                        CloudFeedColumn(feed: selectedFeed)
                    }
                    else {
                        ProgressView()
                    }
                case .hot:
                    HotColumn()
                    
                case .zapped:
                    ZappedColumn()
                    
                case .gallery:
                    GalleryColumn()
                    
                case .articles:
                    ArticlesColumn()
                    
                case .emoji:
                    EmojiColumn()
                    
                case .discoverLists:
                    DiscoverListsColumn()
                    
                case .notifications:
                    Text("notifications")
                case .following:
                    Text("following")
                case .photos:
                    Text("photos")
                case .mentions:
                    Text("mentions")
                case .bookmarks:
                    Text("bookmarks")
                case .DMs:
                    Text("DMs")
                case .newPosts:
                    Text("newPosts")
                }

                
                
            }
            
            .withColumnConfigToolbarMenu(feeds: vm.availableFeeds, columnType: $columnType, title: selectedTitle)
//            .withFeedSelectorToolbarMenu(feeds: vm.availableFeeds, selectedFeed: $selectedFeed)
            
            .onAppear {
                columnType = config.type
            }
            
            .onValueChange(columnType, action: { oldColumnType, newColumnType in
                guard oldColumnType != newColumnType else { return }
                vm.updateColumn(
                    MacColumnConfig(id: config.id, type: newColumnType)
                )
            })
            
            .onChange(of: vm.availableFeeds) { newValue in
                guard case .cloudFeed(_) = columnType else { return }
                if !newValue.contains(where: { $0.id == selectedFeed?.id }) {
                    columnType = .unconfigured
                }
            }
            
            .withNavigationDestinations()
            .onReceive(receiveNotification(.navigateTo)) { notification in
                let destination = notification.object as! NavigationDestination
                guard destination.context == containerID else { return }
                navPath.append(destination.destination)
            }
        }
    }
}
