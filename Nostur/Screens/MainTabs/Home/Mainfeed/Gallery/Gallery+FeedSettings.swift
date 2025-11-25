//
//  Gallery+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2023.
//

import SwiftUI

struct GalleryFeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: GalleryViewModel
    @State var needsReload = false
    @AppStorage("enable_gallery_feed") private var enableGalleryFeed: Bool = true
    
    var body: some View {
        NXForm {
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
            
            Toggle(isOn: $enableGalleryFeed, label: {
                Text("Show feed in tab bar")
            })
        }
    }
}

import NavigationBackport

struct GalleryFeedSettingsTester: View {
    
    var body: some View {
        NBNavigationStack {
            GalleryFeedSettings(vm: GalleryViewModel())
                .environmentObject(Themes.default)
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

