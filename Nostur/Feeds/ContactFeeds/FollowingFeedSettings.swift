//
//  FollowingFeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2025.
//

import SwiftUI

struct FollowingFeedSettings: View {
    @ObservedObject public var feed: CloudFeed
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var la: LoggedInAccount
    
    var body: some View {
        NXForm {
            Section(header: Text("Feed settings", comment: "Header for feed settings")) {
                
                // TOGGLE REPLIES
                Toggle(isOn: Binding(get: {
                    feed.repliesEnabled
                }, set: { newValue in
                    feed.repliesEnabled = newValue
                })) {
                    Text("Show replies")
                }
                
                // CONTINUE WHERE LEFT OFF
                Toggle(isOn: Binding(get: {
                    feed.continue
                }, set: { newValue in
                    feed.continue = newValue
                })) {
                    Text("Resume where left")
                    Text("Catch up on missed posts since the last time you opened the feed")
                }
            }
            
            if feed.accountPubkey != nil, !la.account.followingHashtags.isEmpty {
                Section("Included hashtags") {
                    FollowingFeedSettings_Hashtags(hashtags: Array(la.account.followingHashtags), onChange: { hashtags in
                        la.account.followingHashtags = Set(hashtags)
                        la.account.publishNewContactList()
                    })
                }
            }
        }
        
        .navigationTitle("Feed settings")
        .navigationBarTitleDisplayMode(.inline)
        
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in pe.loadCloudFeeds() }) {
        if let feed = PreviewFetcher.fetchCloudFeed(type: "following") {
            FeedSettings(feed: feed)
        }
    }
}
