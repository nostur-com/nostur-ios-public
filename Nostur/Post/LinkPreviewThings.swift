//
//  LinkPreviews.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/04/2023.
//

import SwiftUI
import Foundation

// Fetch and parse meta og tags. Never download file bodies to make link previews.
func fetchMetaTags(url: URL, completion: @escaping (Result<[String: String], Error>) -> Void) {
    fetchMetaTags(url: url, configuration: .ephemeral, completion: completion)
}

func fetchMetaTags(url: URL, configuration: URLSessionConfiguration, completion: @escaping (Result<[String: String], Error>) -> Void) {
    guard !LinkPreviewResponseLoader.isFileDownload(url) else {
        completion(.success([:]))
        return
    }
    let youtube = url.host.map { $0 == "youtube.com" || $0.hasSuffix(".youtube.com") || $0 == "youtu.be" } ?? false
    var requestURL = url
    if youtube {
        var components = URLComponents(string: "https://youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "format", value: "json")]
        guard let oembed = components.url else { return }
        requestURL = oembed
    }
    LinkPreviewResponseLoader(url: url, youtube: youtube, completion: completion)
        .start(requestURL: requestURL, configuration: configuration)
}

/// Delegate delivery and parsing share one background executor per request.
/// Reject binary responses at headers and retain only a bounded HTML prefix.
final class LinkPreviewResponseLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let maximumBytes = 512 * 1024
    private let url: URL
    private let youtube: Bool
    private var completion: ((Result<[String: String], Error>) -> Void)?
    private var session: URLSession?
    private var bytes = Data()

    init(url: URL, youtube: Bool, completion: @escaping (Result<[String: String], Error>) -> Void) {
        self.url = url
        self.youtube = youtube
        self.completion = completion
    }

    static func isFileDownload(_ url: URL) -> Bool {
        ["dmg", "pkg", "zip", "exe", "msi", "deb", "rpm", "tar", "gz", "7z", "pdf"].contains(url.pathExtension.lowercased())
    }

    func start(requestURL: URL, configuration: URLSessionConfiguration) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        var request = URLRequest(url: requestURL)
        request.setValue(youtube ? "application/json" : "text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        session.dataTask(with: request).resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let mime = response.mimeType?.lowercased(),
              youtube ? (mime == "application/json" || mime.hasSuffix("+json")) : (mime == "text/html" || mime == "application/xhtml+xml") else {
            completionHandler(.cancel)
            finish(.success([:]))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard completion != nil else { return }
        bytes.append(data.prefix(Self.maximumBytes - bytes.count))
        if bytes.count == Self.maximumBytes {
            dataTask.cancel()
            finishParsedBody()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard completion != nil else { return }
        if let error { finish(.failure(error)) }
        else { finishParsedBody() }
    }

    private func finishParsedBody() {
        let body = String(decoding: bytes, as: UTF8.self)
        finish(.success(youtube ? parseYoutube(json: body) : parseMetaTags(html: body, url: url)))
    }

    private func finish(_ result: Result<[String: String], Error>) {
        guard let completion else { return }
        self.completion = nil
        bytes = Data()
        session?.invalidateAndCancel()
        session = nil
        completion(result)
    }
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

func parseMetaTags(html: String, url: URL) -> [String: String] {
//    15.00 ms    0.1%    11.00 ms            parseMetaTags(html:)
//    4.00 ms    0.0%    0 s             specialized Collection.prefix(_:)
    let html = html.count > 300000 ? String(html.prefix(300000)) : html
    var metaTags = [String: String]()
    let matches = LinkPreviewCache.shared.metaTagsRegex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
    
    for match in matches {
        let propertyRange = match.range(at: 1)
        let contentRange = match.range(at: 2)
        let property = (html as NSString).substring(with: propertyRange)
        
        if ["image", "title", "description"].contains(property) {
            let content = (html as NSString).substring(with: contentRange)
            
            if property == "image" {
                if content.starts(with: "/") {
                    if let imageUrl = URL(string: content, relativeTo: url) {
                        metaTags[property] = imageUrl.absoluteString
                            .replacingOccurrences(of: "&amp;", with: "&")
                    }
                }
                else {
                    metaTags[property] = content
                        .replacingOccurrences(of: "&amp;", with: "&")
                }
            }
            else{
                metaTags[property] = content.htmlUnescape()
            }
        }
    }
    
    if metaTags["title"] == nil {
        if let titleMatch = LinkPreviewCache.shared.titleRegex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
            let titleRange = titleMatch.range(at: 1)
            let title = (html as NSString).substring(with: titleRange)
            metaTags["fallback_title"] = title.htmlUnescape()
        }
    }
    
    return metaTags
}
