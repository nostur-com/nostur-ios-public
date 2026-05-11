//
//  PostTranslationInline.swift
//  Nostur
//

import SwiftUI

struct PostTranslationInline: View {
    @Environment(\.theme) private var theme
    let nrPost: NRPost

    @State private var loadState: LoadState = .idle

    private enum LoadState {
        case idle
        case loading
        case loaded(String)
        case notNeeded
        case failed
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle:
                EmptyView()
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Translating...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            case .loaded(let translation):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Translation", systemImage: "globe")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(translation)
                        .font(.body)
                        .foregroundColor(theme.primary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(theme.secondaryBackground)
                .cornerRadius(8)
                .padding(.top, 8)
            case .notNeeded:
                EmptyView()
            case .failed:
                HStack(spacing: 8) {
                    Label("Translation unavailable", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await retryTranslate() }
                    }
                    .font(.footnote)
                }
                .padding(.top, 8)
            }
        }
        .task(id: nrPost.id) {
            await translate()
        }
    }

    private func translate() async {
        guard case .idle = loadState else { return }
        let original = nrPost.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            loadState = .notNeeded
            return
        }

        loadState = .loading
        do {
            let translation = try await LibreTranslateService.shared.translatePost(id: nrPost.id, text: original)
            if translation.trimmingCharacters(in: .whitespacesAndNewlines) == original {
                loadState = .notNeeded
            }
            else {
                loadState = .loaded(translation)
            }
        }
        catch {
            loadState = .failed
        }
    }

    private func retryTranslate() async {
        loadState = .idle
        await translate()
    }
}
