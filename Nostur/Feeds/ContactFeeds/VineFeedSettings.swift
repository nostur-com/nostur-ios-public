//
//  VineFeedSettings.swift
//  Nostur
//

import SwiftUI

struct VineFeedSettings: View {
    @ObservedObject public var feed: CloudFeed

    @AppStorage("vine_autoplay_audio_enabled") private var autoplayAudioEnabled = true

    var body: some View {
        NXForm {
            MediaFeedSourceSettings(feed: feed)

            Section(header: Text("Feed settings", comment: "Header for feed settings")) {
                Toggle(isOn: $autoplayAudioEnabled) {
                    Text("Play sound automatically")
                    Text("Start Divine videos with sound")
                }

                Toggle(isOn: Binding(get: {
                    feed.continue
                }, set: { newValue in
                    feed.continue = newValue
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
            FeedSettings(feed: feed)
        }
    }
}
