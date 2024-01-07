//
//  Settings+MediaUploadServicePicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/10/2023.
//

import SwiftUI
import NavigationBackport

struct MediaUploadServicePicker: View {  
    @EnvironmentObject private var themes:Themes
    @State private var nip96apiUrl:String // Should just use @AppStorage("nip96_api_url") here, but this freezes on desktop. so workaround via init() and .onChange(of: nip96apiUrl).
    
    @ObservedObject private var settings: SettingsStore = .shared
    @State private var nip96configuratorShown = false
    
    init() {
        let nip96apiUrl = UserDefaults.standard.string(forKey: "nip96_api_url") ?? ""
        _nip96apiUrl = State(initialValue: nip96apiUrl)
    }
    
    var body: some View {
        Picker(selection: $settings.defaultMediaUploadService) {
            ForEach(SettingsStore.mediaUploadServiceOptions) {
                Text($0.name).tag($0)
                    .foregroundColor(themes.theme.primary)
            }
        } label: {
            Text("Media upload service", comment:"Setting on settings screen")
        }
        .pickerStyleCompatNavigationLink()
        .onChange(of: settings.defaultMediaUploadService) { newValue in
            if newValue.name == "Custom File Storage (NIP-96)" {
                nip96configuratorShown = true
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
            }
        }
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
