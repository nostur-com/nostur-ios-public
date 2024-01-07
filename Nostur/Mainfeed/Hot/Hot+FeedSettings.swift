//
//  Hot+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI

struct HotFeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var hotVM:HotViewModel
    @State var needsReload = false
    
    var body: some View {
        Form {
            if #available(iOS 16, *) {
                Section("App theme") {
                    AppThemeSwitcher()
                }
            }
            Section {
                Picker("Time frame", selection: $hotVM.ago) {
                    Text("48h").tag(48)
                    Text("24h").tag(24)
                    Text("12h").tag(12)
                    Text("8h").tag(8)
                    Text("4h").tag(4)
                    Text("2h").tag(2)
                }
                .pickerStyle(.segmented)
            } header: { Text("Hot feed time frame") } footer: { Text("The Hot feed shows posts most liked or reposted by people you follow in the last \(hotVM.ago) hours") }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

import NavigationBackport

struct HotFeedSettingsTester: View {

    var body: some View {
        NBNavigationStack {
            HotFeedSettings(hotVM: HotViewModel())
        }
        .onAppear {
            Themes.default.loadPurple()
        }
    }
}


struct HotFeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            HotFeedSettingsTester()
        }
    }
}

