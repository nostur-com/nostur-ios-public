//
//  NostrimgMediaUploadService.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/04/2023.
//

import Foundation

// Same as IMGUR but no Client ID needed

// CURL EXAMPLE
// curl -X POST -H "Content-Type: multipart/form-data" -F "image=@testupload.png" https://nostrimg.com/api/upload | jq
func getNostrimgService() -> MediaUploadService {
    return MediaUploadService(name: "nostrimg.com", request: { imageData in
        let url = URL(string: "https://nostrimg.com/api/upload")!
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
    }, urlFromResponse: { (data, response) in
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let link = json["data"] as? [String: Any],
              let url = link["link"] as? String else {
//            let httpResponse = response as? HTTPURLResponse
//            L.og.debug(httpResponse?.statusCode)
//            L.og.debug(httpResponse?.allHeaderFields)
//            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//            L.og.debug(json?.description)
            throw ImageUploadError.uploadFailure
        }
        return url
    })
}
