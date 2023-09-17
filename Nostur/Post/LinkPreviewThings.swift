//
//  LinkPreviews.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/04/2023.
//

import SwiftUI
import Foundation

// Fetch and parse meta og tags
func fetchMetaTags(url: URL, completion: @escaping (Result<[String: String], Error>) -> Void) {
    // if youtube, use https://youtube.com/oembed?url= to fetch metadata (less than 1 KB, vs ~800 KB regular youtube page)
    if let host = url.host, (host.contains("youtube.com") || host.contains("youtu.be")) {
        guard let urlAsQueryString = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return }
        guard let url = URL(string: String(format:"https://youtube.com/oembed?url=%@", urlAsQueryString)) else { return }
        let request = URLRequest(url: url)
    
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(.failure(error!))
                return
            }
            guard let json = String(data: data, encoding: .utf8) else {
                completion(.failure(NSError(domain: "Invalid JSON", code: 0, userInfo: nil)))
                return
            }
            let metaTags = parseYoutube(json: json)
            completion(.success(metaTags))
        }
        task.resume()
        
        
        return
    }
    
    let request = URLRequest(url: url)
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        guard let data = data, error == nil else {
            completion(.failure(error!))
            return
        }
        guard let html = String(data: data, encoding: .utf8) else {
            completion(.failure(NSError(domain: "Invalid HTML", code: 0, userInfo: nil)))
            return
        }
        let metaTags = parseMetaTags(html: html)
        completion(.success(metaTags))
    }
    task.resume()
}

struct YouTubeOembedJson: Codable {
    var title:String? // "title": "#272 - Fragiliteit van het individu, Nederland in recessie en recordwinsten Banken"
    var thumbnail_url:String? // "thumbnail_url": "https://i.ytimg.com/vi/JoOAzgRvjU0/hqdefault.jpg"
    var author_name:String? // "author_name": "Satoshi Radio"
}

func parseYoutube(json: String) -> [String: String] {
    var metaTags = [String: String]()

    let decoder = JSONDecoder()
    guard let jsonData = json.data(using: .utf8), let yt = try? decoder.decode(YouTubeOembedJson.self, from: jsonData) else {
        return metaTags
    }
    
    if let title = yt.title {
        metaTags["title"] = title
    }
    
    if let author_name = yt.author_name {
        metaTags["description"] = author_name
    }
    
    if let thumbnail_url = yt.thumbnail_url {
        metaTags["image"] = thumbnail_url
    }

    return metaTags
}

func parseMetaTags(html: String) -> [String: String] {
    let html = html.count > 300000 ? String(html.prefix(300000)) : html
    var metaTags = [String: String]()
    let pattern = #"<meta\s+(?:property=|name=)"(?:og|twitter):(.*?)"\s+content="([^"]+)(?:"\s|"[^>]*?\/?>)"#
    let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
    
    for match in matches {
        let propertyRange = match.range(at: 1)
        let contentRange = match.range(at: 2)
        let property = (html as NSString).substring(with: propertyRange)
        
        if ["image", "title", "description"].contains(property) {
            let content = (html as NSString).substring(with: contentRange)
            metaTags[property] = property == "image" ? content : content.htmlUnescape()
        }
    }
    
    // fallback title
    if metaTags["title"] == nil, let titleMatch = html.firstMatch(of: /<title(?:.*)>([^<]*)<\/title>/.ignoresCase())?.output {
        metaTags["fallback_title"] = String(titleMatch.1).htmlUnescape()
    }
    
    return metaTags
}
