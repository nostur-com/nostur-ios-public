//
//  ContentTypeColumn+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/11/2025.
//

import SwiftUI

struct YakFeedSettings: View {
    @ObservedObject public var feed: CloudFeed
    
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
        
        .navigationTitle("Voice Message feed settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
