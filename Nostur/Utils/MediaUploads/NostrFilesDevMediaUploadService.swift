//
//  NostrimgMediaUploadService.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/06/2023.
//

import Foundation

// Same as IMGUR but no Client ID needed

// CURL EXAMPLE
// curl -X POST -F file=@nostrich.jpg https://nostrfiles.dev/upload_image
// response:
// {"url":"http://nostrfiles.dev/uploads/GlrRZcm6styM6G5sYWZz.png"}

func getNostrFilesDevService() -> MediaUploadService {
    return MediaUploadService(name: "nostrfiles.dev", request: { imageData in
        let url = URL(string: "https://nostrfiles.dev/upload_image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        let contentType = "multipart/form-data; boundary=\(boundary)"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let body = NSMutableData()
        let fieldName = "file"
        
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
              let url = json["url"] as? String else {
//            let httpResponse = response as? HTTPURLResponse
//            L.og.debug(httpResponse?.statusCode)
//            L.og.debug(httpResponse?.allHeaderFields)
//            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//            L.og.debug(json?.description)
            throw ImageUploadError.uploadFailure
        }
        return url.replacingOccurrences(of: "http://", with: "https://")
    })
}
