//
//  Settings+MediaUploadServicePicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/10/2023.
//

import SwiftUI

struct MediaUploadServicePicker: View {
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        Picker(selection: $settings.defaultMediaUploadService) {
            ForEach(SettingsStore.mediaUploadServiceOptions) {
                Text($0.name).tag($0)
            }
        } label: {
            Text("Media upload service", comment:"Setting on settings screen")
        }
        .pickerStyle(.navigationLink)
    }
}

#Preview {
    NavigationStack {
        Form {
            MediaUploadServicePicker()
        }
    }
}
