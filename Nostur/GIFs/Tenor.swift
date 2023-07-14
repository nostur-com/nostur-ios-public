//
//  Tenor.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/05/2023.
//

import Foundation
 
let apikey = Bundle.main.infoDictionary?["TENOR_API_KEY"] as? String ?? ""
let clientkey = Bundle.main.infoDictionary?["TENOR_CLIENT_KEY"] as? String ?? ""

/**
 Async URL requesting function.
 */
func makeWebRequest<T: Decodable>(urlRequest: URLRequest, callback: @escaping (T) -> ()) {
    // Make the async request and pass the resulting JSON object to the callback
    let task = URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
        do {
            let decoder = JSONDecoder()
            if let data {
                let result = try decoder.decode(T.self, from: data)
                callback(result)
            }
        } catch {
            L.og.error("Tenor gif error: \(error)")
        }
    }
    task.resume()
}


// Function for handling a user's selection of a GIF to share.
// In a production application, the GIF id should be the "id" field of the GIF response object that the user selected
// to share. The search term should be the user's last search.
func registerShare(gifId: String, searchTerm: String) {
    
    // Register the user's share - using the default locale of en_US
    let shareRequest = URLRequest(url: URL(string: String(format: "https://tenor.googleapis.com/v2/registershare?key=%@&client_key=%@&id=%@&q=%@",
                                                          apikey,
                                                          clientkey,
                                                          gifId,
                                                          searchTerm))!)
    makeWebRequest(urlRequest: shareRequest, callback: tenorShareHandler)
    
    // Data will be loaded by each request's callback
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
