//
//  Tenor.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/05/2023.
//

import Foundation

enum GifAPIError: Error {
    case invalidResponse
    case httpStatus(Int)
}

let GIF_API = if Date.now.timeIntervalSince1970 > 1782597600 { // if date is after june 29 2026
    "api.klipy.com"
} else {
    "tenor.googleapis.com"
}
 
let apikey = if Date.now.timeIntervalSince1970 > 1782597600 { // if date is after june 29 2026
    Bundle.main.infoDictionary?["KLIPY_API_KEY"] as? String ?? ""
} else {
    Bundle.main.infoDictionary?["TENOR_API_KEY"] as? String ?? ""
}

let clientkey = if Date.now.timeIntervalSince1970 > 1782597600 { // Klipy only requires its API key
    ""
} else {
    Bundle.main.infoDictionary?["TENOR_CLIENT_KEY"] as? String ?? ""
}

/**
 Async URL requesting function.
 */
func makeWebRequest<T: Decodable>(urlRequest: URLRequest) async throws -> T {
    var request = urlRequest
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw GifAPIError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
        throw GifAPIError.httpStatus(httpResponse.statusCode)
    }

    return try JSONDecoder().decode(T.self, from: data)
}


// Function for handling a user's selection of a GIF to share.
// In a production application, the GIF id should be the "id" field of the GIF response object that the user selected
// to share. The search term should be the user's last search.
func registerShare(gifId: String, searchTerm: String) {
    guard let url = gifAPIURL(
        path: "registershare",
        queryItems: [
            URLQueryItem(name: "id", value: gifId),
            URLQueryItem(name: "q", value: searchTerm)
        ]
    ) else { return }

    Task {
        do {
            let response: TenorResponse = try await makeWebRequest(urlRequest: URLRequest(url: url))
            tenorShareHandler(response: response)
        } catch {
            L.og.error("GIF share registration error: \(error)")
        }
    }
}

func gifAPIURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = GIF_API
    components.path = "/v2/\(path)"

    var authenticatedQueryItems = [URLQueryItem(name: "key", value: apikey)]
    if !clientkey.isEmpty {
        authenticatedQueryItems.append(URLQueryItem(name: "client_key", value: clientkey))
    }
    authenticatedQueryItems.append(contentsOf: queryItems)
    components.queryItems = authenticatedQueryItems

    return components.url
}


/**
 Web response handler for search requests.
 */
func tenorShareHandler(response: TenorResponse) {
    // no response expected from the registershare endpoint
}

struct AutoCompleteResponse: Codable {
    let results: [String]?
}

struct TenorResponse: Codable {
    let results: [TenorResult]?
    let tags: [TenorCategory]?
}

struct TenorCategory: Codable, Identifiable {
    let path: String
    var id: String { path }
    let image: String
    let name: String
}

struct TenorResult: Codable, Identifiable {
    let content_description: String
    let id: String
    let itemurl: String
    let media_formats: [String: TenorGif]
    let tags: [String]
    let title: String
    let url: String
}

struct TenorGif: Codable {
    let url: String
    let dims: [Int]
    let preview: String
    let size: Int
    let duration: Double
}
