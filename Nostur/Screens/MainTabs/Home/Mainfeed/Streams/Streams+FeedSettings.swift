//
//  Streams+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI

struct StreamsFeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var streamsVM: StreamsViewModel
    @State var needsReload = false
    @AppStorage("enable_streams_feed") private var enableStreamsFeed: Bool = true
    
    var body: some View {
        NXForm {
            Toggle(isOn: $enableStreamsFeed, label: {
                Text("Show feed in feed selector")
            })
        }
    }
}

import NavigationBackport

struct StreamsFeedSettingsTester: View {

    var body: some View {
        NBNavigationStack {
            StreamsFeedSettings(streamsVM: StreamsViewModel())
                .environmentObject(Themes.default)
        }
        .onAppear {
            Themes.default.loadPurple()
        }
    }
}


#Preview {
    PreviewContainer {
        StreamsFeedSettingsTester()
    }
}

