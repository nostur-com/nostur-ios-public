//
//  Settings+AutodownloadLevelPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/10/2023.
//

import SwiftUI

struct AutodownloadLevelPicker: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        Picker(selection: $settings.autoDownloadFrom) {
            ForEach(AutodownloadLevel.allCases, id:\.self) {
                Text($0.localized).tag($0.rawValue)
                    .foregroundColor(themes.theme.primary)
            }
        } label: {
            Text("Restrict media downloading", comment:"Setting on settings screen")
        }
        .pickerStyle(.navigationLink)
    }
}

#Preview {
    NavigationStack {
        Form {
            AutodownloadLevelPicker()
        }
    }
}
