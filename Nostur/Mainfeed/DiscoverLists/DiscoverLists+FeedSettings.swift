//
//  DiscoverLists+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/04/2025.
//

import SwiftUI

struct DiscoverListsFeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var discoverListsVM: DiscoverListsViewModel
    @State var needsReload = false
    @AppStorage("enable_discover_lists_feed") private var enableDiscoverListsFeed: Bool = true
    
    var body: some View {
        Form {
            Toggle(isOn: $enableDiscoverListsFeed, label: {
                Text("Show feed in tab bar")
            })
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                  dismiss()
                }
            }
        }
    }
}

import NavigationBackport

struct DiscoverListsFeedSettingsTester: View {

    var body: some View {
        NBNavigationStack {
            DiscoverListsFeedSettings(discoverListsVM: DiscoverListsViewModel())
                .environmentObject(Themes.default)
        }
        .onAppear {
            Themes.default.loadPurple()
        }
    }
}


struct DiscoverListsFeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            DiscoverListsFeedSettingsTester()
        }
    }
}

