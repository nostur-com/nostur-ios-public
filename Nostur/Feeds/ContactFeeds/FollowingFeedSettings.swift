//
//  FollowingFeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2025.
//

import SwiftUI

struct FollowingFeedSettings: View {
    @ObservedObject public var feed: CloudFeed
    var draft: FeedSettingsDraft? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NXForm {
            Section(header: Text("Feed settings", comment: "Header for feed settings")) {
                
                // TOGGLE REPLIES
                Toggle(isOn: Binding(get: {
                    feed.repliesEnabled
                }, set: { newValue in
                    feed.repliesEnabled = newValue
                    feed.markUserEdited()
                })) {
                    Text("Show replies")
                }
                
                // CONTINUE WHERE LEFT OFF
                Toggle(isOn: Binding(get: {
                    feed.continue
                }, set: { newValue in
                    feed.continue = newValue
                    feed.markUserEdited()
                })) {
                    Text("Remember feed")
                    Text("Resume feed from where you left off when you reopen the app")
                }
            }
            
            // Only show specific content types (kinds)
//            NavigationLink(destination: ContentTypesPicker(selectedKinds: $feed.kinds)) {
//                HStack {
//                    Text("Limit content types")
//                    Spacer()
//                    Text(!feed.kinds.isEmpty ? "\(kindsDescription(feed.kinds))" : "All")
//                }
//            }
        }
        
        .navigationTitle("Following Feed settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PreviewContainer({ pe in pe.loadCloudFeeds() }) {
        if let feed = PreviewFetcher.fetchCloudFeed(type: "following") {
            FeedSettingsSheet(feed: feed)
        }
    }
}
