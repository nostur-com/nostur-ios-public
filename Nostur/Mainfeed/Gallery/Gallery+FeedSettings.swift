//
//  Gallery+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2023.
//

import SwiftUI

struct GalleryFeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm:GalleryViewModel
    @State var needsReload = false
    
    var body: some View {
        Form {
            Section("App theme") {
                AppThemeSwitcher()
            }
            Section {
                Picker("Time frame", selection: $vm.ago) {
                    Text("48h").tag(48)
                    Text("24h").tag(24)
                    Text("12h").tag(12)
                    Text("8h").tag(8)
                    Text("4h").tag(4)
                    Text("2h").tag(2)
                }
                .pickerStyle(.segmented)
            } header: { Text("Gallery feed time frame") } footer: { Text("The Gallery feed shows pictures most liked or reposted by people you follow in the last \(vm.ago) hours") }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct GalleryFeedSettingsTester: View {
    
    var body: some View {
        NavigationStack {
            GalleryFeedSettings(vm: GalleryViewModel())
        }
        .onAppear {
            Themes.default.loadPurple()
        }
    }
}


struct GalleryFeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            GalleryFeedSettingsTester()
        }
    }
}

