//
//  RelayInformationCard.swift
//  Nostur
//
//  Created by Codex on 17/04/2026.
//

import SwiftUI

struct RelayInformationCard: View {
    @Environment(\.theme) private var theme

    let relayUrl: String
    var onInfoLoaded: ((RelayInformationDocument) -> Void)? = nil
    var showDismissButton: Bool = false
    var onDismiss: (() -> Void)? = nil

    @State private var info: RelayInformationDocument?
    @State private var showFullDescription = false
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let info {
                VStack(alignment: .leading, spacing: 8) {
                    if let title = sanitized(info.name), !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                    }

                    if let description = sanitized(info.description), !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(showFullDescription ? nil : 5)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)

                        if shouldShowMoreButton(for: description) {
                            Button(showFullDescription ? "Less" : "More") {
                                showFullDescription.toggle()
                            }
                            .font(.subheadline)
                            .foregroundColor(theme.accent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, showDismissButton ? 22 : 0)
                .overlay(alignment: .topTrailing) {
                    if showDismissButton {
                        Button {
                            onDismiss?()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                        .padding(.trailing, 1)
                    }
                }
                .padding(12)
                .background(theme.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.lineColor, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            else if loadFailed {
                EmptyView()
            }
            else {
                EmptyView()
            }
        }
        .task(id: relayUrl) {
            await loadRelayInfo()
        }
    }

    @MainActor
    private func loadRelayInfo() async {
        info = nil
        loadFailed = false

        guard let document = await fetchRelayInformationDocument(for: relayUrl) else {
            loadFailed = true
            return
        }
        guard !Task.isCancelled else { return }

        withAnimation {
            info = document
        }
        onInfoLoaded?(document)
    }

    private func shouldShowMoreButton(for description: String) -> Bool {
        description.count > 280
    }

    private func sanitized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
}

struct RelayInformationDocument: Sendable {
    let name: String?
    let description: String?

    var hasVisibleContent: Bool {
        let hasName = !(name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasDescription = !(description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasName || hasDescription
    }

    static func parse(from data: Data) -> RelayInformationDocument? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let name = (json["name"] as? String) ?? (json["title"] as? String)
        let description = (json["description"] as? String) ?? (json["about"] as? String)

        let document = RelayInformationDocument(name: name, description: description)
        return document.hasVisibleContent ? document : nil
    }
}

func fetchRelayInformationDocument(for relayUrl: String) async -> RelayInformationDocument? {
    await RelayInformationLoader.shared.load(for: relayUrl)
}

actor RelayInformationLoader {
    static let shared = RelayInformationLoader()

    private var cache: [String: RelayInformationDocument] = [:]
    private var inFlight: [String: Task<RelayInformationDocument?, Never>] = [:]

    func load(for relayUrl: String) async -> RelayInformationDocument? {
        if let cached = cache[relayUrl] {
            return cached
        }

        if let existingTask = inFlight[relayUrl] {
            return await existingTask.value
        }

        let fetchTask = Task { await fetchRelayInformationDocumentUncached(for: relayUrl) }
        inFlight[relayUrl] = fetchTask

        let fetched = await fetchTask.value
        inFlight[relayUrl] = nil

        if let fetched {
            cache[relayUrl] = fetched
        }

        return fetched
    }
}

private func fetchRelayInformationDocumentUncached(for relayUrl: String) async -> RelayInformationDocument? {
    let candidates = relayInformationRequestCandidates(from: relayUrl)
    let acceptHeaders = [
        "application/nostr+json",
        "application/nostr+json, application/json;q=0.9, */*;q=0.8"
    ]

    for url in candidates {
        for acceptHeader in acceptHeaders {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            request.setValue(acceptHeader, forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode)
                else {
                    continue
                }

                if let parsed = RelayInformationDocument.parse(from: data) {
                    return parsed
                }
            } catch {
                continue
            }
        }
    }

    return nil
}

private func relayInformationRequestCandidates(from relayUrl: String) -> [URL] {
    guard var components = URLComponents(string: relayUrl) else { return [] }

    switch components.scheme?.lowercased() {
    case "wss":
        components.scheme = "https"
    case "ws":
        components.scheme = "http"
    case "https", "http":
        break
    default:
        return []
    }

    var urls: [URL] = []
    if let baseURL = components.url {
        urls.append(baseURL)
    }

    if components.path.isEmpty {
        var withSlash = components
        withSlash.path = "/"
        if let slashURL = withSlash.url {
            urls.append(slashURL)
        }
    }

    var seen: Set<String> = []
    return urls.filter { seen.insert($0.absoluteString).inserted }
}

