//
//  NostrBuildMediaUploadService.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/04/2023.
//

import Foundation

// Something wrong with the response, can't find api. Disabled for now
func getNostrBuildService() -> MediaUploadService {
    return MediaUploadService(name: "nostr.build", request: { imageData, usePNG in
        let url = URL(string: "https://nostr.build/upload.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        let contentType = "multipart/form-data; boundary=\(boundary)"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let body = NSMutableData()
        let fieldName = "image"
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body as Data
        return request
    }, urlFromResponse: { (data, response, _) in
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let responseString = String(data: data, encoding: .utf8),
              responseString.contains("https://")
        else {
//            let httpResponse = response as? HTTPURLResponse
//            let responseText = String(data: data, encoding: .utf8)
            throw ImageUploadError.uploadFailure
        }
        
        guard let url = responseString.firstMatch(of: /https:\/\/nostr\.build\/i\/nostr\.build_[a-zA-Z0-9]+(\.[a-zA-Z]{3,8})/)?.output.0 else {
            throw ImageUploadError.uploadFailure
        }
        
        return String(url)
    })
}
