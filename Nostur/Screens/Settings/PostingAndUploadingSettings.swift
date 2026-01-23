//
//  SpamFilteringSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI
import NavigationBackport

struct PostingAndUploadingSettings: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    
    @AppStorage("nip96_api_url") private var nip96ApiUrl = ""
    @AppStorage("media_upload_service") private var mediaUploadService = ""
    
    @State private var blossomConfiguratorShown = false
    
    var body: some View {
        NXForm {
            Section(header: Text("Media uploading", comment:"Setting heading on settings screen")) {
                
                MediaUploadServicePicker()
                
                if !nip96ApiUrl.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Now using:")
                        Text(nip96ApiUrl)
                            .font(.caption)
                    }
                    .foregroundColor(theme.secondary)
                }
                
                if mediaUploadService == BLOSSOM_LABEL {
                    Button("Configure blossom server(s)") {
                        blossomConfiguratorShown = true
                    }
                    .sheet(isPresented: $blossomConfiguratorShown) {
                        NBNavigationStack {
                            BlossomServerList()
                                .environment(\.theme, theme)
                                .presentationBackgroundCompat(theme.listBackground)
                        }
                        .nbUseNavigationStack(.never)
                        .presentationBackgroundCompat(theme.listBackground)
                    }
                }
            }
            
            Section(header: Text("Posting", comment:"Setting heading on settings screen")) {
                PostingToggle()
            }
        }
    }
}

#Preview {
    PostingAndUploadingSettings()
}
