//
//  Settings+MacTextSizePicker.swift
//  Nostur
//
//  Mac Catalyst only: in-app text size (system Dynamic Type is unreliable on Catalyst).
//

import SwiftUI

struct MacTextSizePicker: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        Picker(selection: $settings.macTextSize) {
            ForEach(SettingsStore.MacTextSizeOption.allCases) { option in
                Text(option.label)
                    .tag(option.rawValue)
                    .foregroundColor(theme.primary)
            }
        } label: {
            Text("Text size", comment: "Setting on settings screen (Mac)")
        }
        .pickerStyleCompatNavigationLink()
    }
}

import NavigationBackport

#Preview {
    NBNavigationStack {
        Form {
            MacTextSizePicker()
        }
    }
}
