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
    var request = URLRequest(url: url)
    request.addValue("Nostur/1 Unknown/0.0.0 Unknown/0.0.0", forHTTPHeaderField: "User-Agent")
    // Normal user agent is Nostur/1 CFNetwork/1406.0.4 Darwin/22.4.0, but then youtube doesn't give back metatags we need.
    
    // if youtube, add consent cookie to skip "Before you continue" or we can't load the preview
    if let host = url.host, host.contains("youtube.com") {
        let cookie = HTTPCookie(properties: [
            .domain: "youtube.com",
            .path: "/",
            .name: "CONSENT",
            .value: "YES+999"
        ])!
        request.addValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie")
    }
    
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




struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct SizeModifier: ViewModifier {
    private var sizeView: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        }
    }

    func body(content: Content) -> some View {
        content.overlay(sizeView) // .background does not always work (gives 0,0), but overlay does work??)
    }
}
