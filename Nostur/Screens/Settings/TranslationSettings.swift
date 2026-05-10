//
//  TranslationSettings.swift
//  Nostur
//

import SwiftUI

struct TranslationSettings: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared

    var body: some View {
        NXForm {
            Section(header: Text("Translation", comment: "Setting heading on settings screen")) {
                Toggle(isOn: $settings.translationAutoTranslate) {
                    VStack(alignment: .leading) {
                        Text("Automatically translate notes", comment: "Setting on settings screen")
                        Text("Shows translations inline using your configured service", comment: "Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                TextField("Service URL", text: $settings.translationServiceURL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)

                SecureField("API key", text: $settings.translationAPIKey)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                TextField("Source language code", text: $settings.translationSourceLanguage)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                TextField("Target language code", text: $settings.translationTargetLanguage)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .listRowBackground(theme.background)

            Section {
                Text("Use any LibreTranslate-compatible endpoint. The default is translate.nostr.wine. Language values should be ISO codes like en, es, fr, de, or ja; use auto for source when the service supports detection.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .listRowBackground(theme.background)
        }
        .nosturNavBgCompat(theme: theme)
        .navigationTitle("Translation")
    }
}

#Preview("Translation Settings") {
    PreviewContainer {
        NBNavigationStack {
            TranslationSettings()
                .environment(\.theme, Themes.default.theme)
        }
    }
}
