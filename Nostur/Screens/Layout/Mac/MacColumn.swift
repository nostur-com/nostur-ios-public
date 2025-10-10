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
    @Environment(\.theme) private var theme
    let availableFeeds: [CloudFeed]
    @State private var selectedFeed: CloudFeed? = nil
    @State private var navPath = NBNavigationPath()
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
