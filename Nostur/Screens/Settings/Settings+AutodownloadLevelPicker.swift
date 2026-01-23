//
//  Settings+AutodownloadLevelPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/10/2023.
//

import SwiftUI

struct AutodownloadLevelPicker: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        Picker(selection: $settings.autoDownloadFrom) {
            ForEach(AutodownloadLevel.allCases, id:\.self) {
                Text($0.localized).tag($0.rawValue)
                    .foregroundColor(theme.primary)
            }
        } label: {
            Text("Media downloading", comment:"Setting on settings screen")
        }
        .pickerStyleCompatNavigationLink()
    }
}

import NavigationBackport

#Preview {
    NBNavigationStack {
        Form {
            AutodownloadLevelPicker()
        }
    }
}
