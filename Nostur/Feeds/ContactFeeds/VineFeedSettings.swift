//
//  VineFeedSettings.swift
//  Nostur
//

import SwiftUI

struct VineFeedSettings: View {
    @ObservedObject public var feed: CloudFeed
    var draft: FeedSettingsDraft? = nil

    var body: some View {
        NXForm {
            if let draft {
                MediaFeedSourceSettings(feed: feed, draft: draft)
            }

            Section(header: Text("Feed settings", comment: "Header for feed settings")) {
                Toggle(isOn: Binding(
                    get: { draft?.vineAutoplayAudio ?? true },
                    set: { draft?.vineAutoplayAudio = $0 }
                )) {
                    Text("Play sound automatically")
                    Text("Start Divine videos with sound")
                }

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
        }
        .navigationTitle("Divine Feed settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PreviewContainer({ pe in pe.loadCloudFeeds() }) {
        if let feed = PreviewFetcher.fetchCloudFeed(type: "vine") {
            FeedSettingsSheet(feed: feed)
        }
    }
}
