//
//  Settings+MediaUploadServicePicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/10/2023.
//

import SwiftUI
import NavigationBackport

// Some labels used as value condition checks, so...
let BLOSSOM_LABEL = "Use Blossom server(s)"
let NIP96_LABEL = "Custom File Storage (NIP-96)"

struct MediaUploadServicePicker: View {  
    @Environment(\.theme) private var theme
    @State private var nip96apiUrl:String // Should just use @AppStorage("nip96_api_url") here, but this freezes on desktop. so workaround via init() and .onChange(of: nip96apiUrl).
    
    @ObservedObject private var settings: SettingsStore = .shared
    @State private var nip96configuratorShown = false
    @State private var blossomConfiguratorShown = false
    
    init() {
        let nip96apiUrl = UserDefaults.standard.string(forKey: "nip96_api_url") ?? ""
        _nip96apiUrl = State(initialValue: nip96apiUrl)
    }
    
    var body: some View {
        Picker(selection: $settings.defaultMediaUploadService) {
            ForEach(SettingsStore.mediaUploadServiceOptions) {
                Text($0.name).tag($0)
                    .foregroundColor(theme.primary)
            }
        } label: {
            Text("Upload method", comment:"Setting on settings screen")
        }
        .listRowBackground(theme.background)
        .pickerStyleCompatNavigationLink()
        .onChange(of: settings.defaultMediaUploadService) { newValue in
            if newValue.name == BLOSSOM_LABEL {
                blossomConfiguratorShown = true
                nip96apiUrl = ""
                UserDefaults.standard.set("", forKey: "nip96_api_url")
            }
            else if newValue.name == NIP96_LABEL {
                nip96configuratorShown = true
            }
            else if newValue.name == "nostrcheck.me" {
                nip96apiUrl = "https://nostrcheck.me/api/v2/media"
                UserDefaults.standard.set("https://nostrcheck.me/api/v2/media", forKey: "nip96_api_url")
            }
            else if newValue.name == "nostr.build" {
                nip96apiUrl = "https://nostr.build/api/v2/nip96/upload"
                UserDefaults.standard.set("https://nostr.build/api/v2/nip96/upload", forKey: "nip96_api_url")
            }
            else {
                nip96apiUrl = ""
                UserDefaults.standard.set("", forKey: "nip96_api_url")
            }
        }
        .sheet(isPresented: $nip96configuratorShown) {
            NBNavigationStack {
                Nip96Configurator()
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(isPresented: $blossomConfiguratorShown) {
            NBNavigationStack {
                BlossomServerList()
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .scrollContentBackgroundHidden()
    }
}

#Preview {
    NBNavigationStack {
        Form {
            MediaUploadServicePicker()
        }
    }
    .environmentObject(Themes.default)
}
