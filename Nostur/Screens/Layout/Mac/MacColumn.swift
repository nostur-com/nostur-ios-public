//
//  MacColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/10/2025.
//

import SwiftUI
import NavigationBackport

@available(iOS 16.0, *)
struct MacColumn: View {
    @ObservedObject private var vm: MacColumnsVM = .shared
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    
    // Doesn't get updates propagated, so only use for initial setup
    var config: MacColumnConfig
    
    @State private var columnType = MacColumnType.unconfigured // use instead of config.type
    @State private var selectedFeed: CloudFeed?
    @State private var navPath = NBNavigationPath()
    
    var body: some View {
        NBNavigationStack(path: $navPath) {
            ZStack {
                theme.listBackground
                
                switch columnType {
                case .unconfigured:
                    Text("unconfigured")
                case .cloudFeed:
                    CloudFeedColumn(selectedFeed: $selectedFeed)
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
            
            .withFeedSelectorToolbarMenu(feeds: vm.availableFeeds, selectedFeed: $selectedFeed)
            
            .onAppear {
                columnType = config.type
                
                if let cloudFeedId = config.cloudFeedId {
                    selectedFeed = vm.availableFeeds.first(where: { $0.id?.uuidString == cloudFeedId })
                }
            }
            
            .onValueChange(selectedFeed, action: { oldSelectedFeed, newSelectedFeed in
                guard oldSelectedFeed != newSelectedFeed else { return }
                if let newSelectedFeed {
                    vm.updateColumn(
                        MacColumnConfig(id: config.id, type: .cloudFeed, cloudFeedId: newSelectedFeed.id?.uuidString)
                    )
                    columnType = .cloudFeed
                }
                else {
                    vm.updateColumn(
                        MacColumnConfig(id: config.id, type: .unconfigured, cloudFeedId: nil)
                    )
                    columnType = .unconfigured
                }
            })
            
            .onChange(of: vm.availableFeeds) { newValue in
                if !newValue.contains(where: { $0.id == selectedFeed?.id }) {
                    columnType = .unconfigured
                    selectedFeed = nil
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
    


@available(iOS 16.0, *)
struct CloudFeedColumn: View {
    @Environment(\.macColumnsState) private var vm
    @Binding var selectedFeed: CloudFeed?
    @State private var columnConfig: NXColumnConfig?
    
    var body: some View {
        Container {
            if columnConfig == nil {
                ProgressView()
                    .onAppear {
                        if let selectedFeed {
                            columnConfig = NXColumnConfig(id: selectedFeed.subscriptionId, columnType: selectedFeed.feedType, accountPubkey: selectedFeed.accountPubkey, name: selectedFeed.name_)
                        }
                    }
            }
            else if let columnConfig {
                AvailableWidthContainer {
                    NXColumnView(config: columnConfig, isVisible: true)
                }
            }
        }
                
        .onChange(of: selectedFeed) { newSelectedFeed in
            guard let newSelectedFeed else { return }
            self.columnConfig = NXColumnConfig(
                id: newSelectedFeed.subscriptionId,
                columnType: newSelectedFeed.feedType,
                accountPubkey: newSelectedFeed.accountPubkey,
                name: newSelectedFeed.name_
            )
        }
    }
    
    func load() {
        
    }
}
