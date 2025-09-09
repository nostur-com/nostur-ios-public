//
//  PictureFeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2025.
//

import SwiftUI

struct PictureFeedSettings: View {
    @ObservedObject public var feed: CloudFeed
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var la: LoggedInAccount
    
    var body: some View {
        NXForm {
            Section(header: Text("Feed settings", comment: "Header for feed settings")) {
                
                // CONTINUE WHERE LEFT OFF
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
        if let feed = PreviewFetcher.fetchCloudFeed(type: "picture") {
            FeedSettings(feed: feed)
        }
    }
}
