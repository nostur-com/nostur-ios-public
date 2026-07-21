//
//  Settings+ReplyThreadFormatPicker.swift
//  Nostur
//
//  Reply thread layout under post detail: nested tree or classic flat list.
//

import SwiftUI

struct ReplyThreadFormatPicker: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        Picker(selection: $settings.nestedRepliesEnabled) {
            Text("Nested", comment: "Reply thread format: indent replies under the post they respond to")
                .tag(true)
                .foregroundColor(theme.primary)
            Text("Flat", comment: "Reply thread format: list all replies in a single level")
                .tag(false)
                .foregroundColor(theme.primary)
        } label: {
            Text("Reply thread format", comment: "Setting on settings screen")
        }
        .pickerStyleCompatNavigationLink()
    }
}

import NavigationBackport

#Preview {
    NBNavigationStack {
        Form {
            ReplyThreadFormatPicker()
        }
    }
}
