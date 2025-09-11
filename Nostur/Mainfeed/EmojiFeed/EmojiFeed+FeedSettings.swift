//
//  EmojiFeed+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI

struct EmojiFeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: EmojiFeedViewModel
    @State var needsReload = false
    @AppStorage("enable_emoji_feed") private var enableEmojiFeed: Bool = true
    
    var body: some View {
        Form {
            Section {
                Picker("Configure feed type", selection: $vm.emojiType) {
                    Text("😂").tag("😂")
                    Text("😡").tag("😡")
                }
                .pickerStyle(.segmented)
            } header: { Text("Configure feed") } footer: { Text("Outrage feed may or may not be available in a future release") }
            .disabled(true)
            
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
            } header: { Text("Emoji feed time frame") } footer: { Text("The Emoji feed shows posts from anyone which are reacted to with specific emojis by people you follow in the last \(vm.ago) hours") }
            
            Toggle(isOn: $enableEmojiFeed, label: {
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

struct EmojiFeedSettingsTester: View {

    var body: some View {
        NBNavigationStack {
            EmojiFeedSettings(vm: EmojiFeedViewModel())
                .environmentObject(Themes.default)
        }
        .onAppear {
            Themes.default.loadPurple()
        }
    }
}


struct EmojiFeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            EmojiFeedSettingsTester()
        }
    }
}

