//
//  LibreTranslateService.swift
//  Nostur
//

import CryptoKit
import Foundation

enum LibreTranslateError: LocalizedError {
    case invalidServiceURL
    case emptyText
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServiceURL:
            return String(localized: "Invalid translation service URL")
        case .emptyText:
            return String(localized: "There is no text to translate")
        case .invalidResponse:
            return String(localized: "The translation service returned an invalid response")
        case .requestFailed(let message):
            return message
        }
    }
}

actor LibreTranslateService {
    static let shared = LibreTranslateService()

    private let maxConcurrentRequests = 3
    private var cache: [String: String] = [:]
    private var activeRequests = 0
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    private struct TranslateRequest: Encodable {
        let q: String
        let source: String
        let target: String
        let api_key: String
    }

    private struct TranslateResponse: Decodable {
        let translatedText: String
    }

    func translatePost(id: String, text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibreTranslateError.emptyText }

        let target = normalizedTargetLanguage()
        let cacheKey = "\(id)|\(target)|\(stableCacheDigest(trimmed))"
        if let cached = cache[cacheKey] {
            return cached
        }

        let source = normalizedSourceLanguage()
        if source != "auto", source == target {
            cache[cacheKey] = trimmed
            return trimmed
        }

        await acquireRequestSlot()
        defer { releaseRequestSlot() }

        let translated = try await translate(trimmed, source: source, target: target, apiKey: normalizedAPIKey())
        cache[cacheKey] = translated
        return translated
    }

    private func normalizedTargetLanguage() -> String {
        let language = SettingsStore.shared.translationTargetLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return language.isEmpty ? "en" : language
    }

    private func normalizedSourceLanguage() -> String {
        let language = SettingsStore.shared.translationSourceLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return language.isEmpty ? "auto" : language
    }

    private func normalizedAPIKey() -> String {
        SettingsStore.shared.translationAPIKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func endpoint(_ path: String) throws -> URL {
        let rawURL = SettingsStore.shared.translationServiceURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let baseURL = URL(string: rawURL), let scheme = baseURL.scheme, ["http", "https"].contains(scheme) else {
            throw LibreTranslateError.invalidServiceURL
        }
        if baseURL.lastPathComponent == path {
            return baseURL
        }
        return baseURL.appendingPathComponent(path)
    }

    private func translate(_ text: String, source: String, target: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: try endpoint("translate"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TranslateRequest(q: text, source: source, target: target, api_key: apiKey))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw LibreTranslateError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? String(localized: "Translation request failed")
            throw LibreTranslateError.requestFailed(message)
        }

        return try JSONDecoder().decode(TranslateResponse.self, from: data).translatedText
    }

    private func acquireRequestSlot() async {
        if activeRequests < maxConcurrentRequests {
            activeRequests += 1
            return
        }

        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    private func releaseRequestSlot() {
        if requestWaiters.isEmpty {
            activeRequests -= 1
        }
        else {
            requestWaiters.removeFirst().resume()
        }
    }

    private func stableCacheDigest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
