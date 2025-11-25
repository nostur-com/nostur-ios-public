//
//  Zapped+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/03/2025.
//

import SwiftUI

struct ZappedFeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var zappedVM: ZappedViewModel
    @State var needsReload = false
    @AppStorage("enable_zapped_feed") private var enableZappedFeed: Bool = true
    
    var body: some View {
        NXForm {
            Section {
                Picker("Time frame", selection: $zappedVM.ago) {
                    Text("48h").tag(48)
                    Text("24h").tag(24)
                    Text("12h").tag(12)
                    Text("8h").tag(8)
                    Text("4h").tag(4)
                    Text("2h").tag(2)
                }
                .pickerStyle(.segmented)
            } header: { Text("Zapped feed time frame") } footer: { Text("The Zapped feed shows posts from anyone which are most zapped by people you follow in the last \(zappedVM.ago) hours") }
            
            Toggle(isOn: $enableZappedFeed, label: {
                Text("Show feed in tab bar")
            })
        }
    }
}

import NavigationBackport

struct ZappedFeedSettingsTester: View {

    var body: some View {
        NBNavigationStack {
            ZappedFeedSettings(zappedVM: ZappedViewModel())
                .environmentObject(Themes.default)
        }
        .onAppear {
            Themes.default.loadPurple()
        }
    }
}


struct ZappedFeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            ZappedFeedSettingsTester()
        }
    }
}

