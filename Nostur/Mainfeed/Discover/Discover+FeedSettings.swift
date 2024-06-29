//
//  Discover+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/06/2024.
//

import SwiftUI

struct DiscoverFeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var discoverVM: DiscoverViewModel
    @State var needsReload = false
    
    var body: some View {
        Form {
            if #available(iOS 16, *) {
                Section("App theme") {
                    AppThemeSwitcher()
                }
            }
            Section {
                Picker("Time frame", selection: $discoverVM.ago) {
                    Text("48h").tag(48)
                    Text("24h").tag(24)
                    Text("12h").tag(12)
                    Text("8h").tag(8)
                    Text("4h").tag(4)
                    Text("2h").tag(2)
                }
                .pickerStyle(.segmented)
            } header: { Text("Discover feed time frame") } footer: { Text("The Discover feed shows posts from people you don't follow which are most liked or reposted by people you follow in the last \(discoverVM.ago) hours") }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

import NavigationBackport

struct DiscoverFeedSettingsTester: View {

    var body: some View {
        NBNavigationStack {
            DiscoverFeedSettings(discoverVM: DiscoverViewModel())
        }
        .onAppear {
            Themes.default.loadPurple()
        }
    }
}


struct DiscoverFeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            DiscoverFeedSettingsTester()
        }
    }
}

