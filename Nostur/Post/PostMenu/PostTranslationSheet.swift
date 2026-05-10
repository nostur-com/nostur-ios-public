//
//  PostTranslationSheet.swift
//  Nostur
//

import SwiftUI

struct PostTranslationSheet: View {
    @Environment(\.theme) private var theme
    let nrPost: NRPost
    var rootDismiss: (() -> Void)? = nil
    
    @State private var loadState: LoadState = .loading
    
    private enum LoadState {
        case loading
        case loaded(String)
        case notNeeded
        case failed(String)
    }
    
    var body: some View {
        NXForm {
            Section(header: Text("Translation")) {
                switch loadState {
                case .loading:
                    HStack {
                        ProgressView()
                        Text("Translating...")
                            .foregroundColor(.secondary)
                    }
                case .loaded(let translation):
                    Text(translation)
                        .textSelection(.enabled)
                case .notNeeded:
                    Text("This note is already in the target language.")
                        .foregroundColor(.secondary)
                case .failed(let message):
                    Text(message)
                        .foregroundColor(.red)
                }
            }
            .listRowBackground(theme.background)
            
            if case .loaded(let translation) = loadState {
                Section {
                    Button {
                        UIPasteboard.general.string = translation
                        sendNotification(.anyStatus, (String(localized: "Translation copied to clipboard"), "COPY_TRANSLATION"))
                    } label: {
                        Label("Copy translation", systemImage: "doc.on.doc")
                            .foregroundColor(theme.accent)
                    }
                }
                .listRowBackground(theme.background)
            }
        }
        .nosturNavBgCompat(theme: theme)
        .navigationTitle("Translate")
        .task(id: nrPost.id) {
            await translate()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    rootDismiss?()
                }
            }
        }
    }
    
    private func translate() async {
        do {
            let translation = try await LibreTranslateService.shared.translatePost(id: nrPost.id, text: nrPost.plainText)
            if translation.trimmingCharacters(in: .whitespacesAndNewlines) == nrPost.plainText.trimmingCharacters(in: .whitespacesAndNewlines) {
                loadState = .notNeeded
            }
            else {
                loadState = .loaded(translation)
            }
        }
        catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
