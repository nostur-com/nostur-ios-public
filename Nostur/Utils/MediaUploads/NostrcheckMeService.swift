//
//  NostrcheckMeService.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import Foundation

// https://github.com/quentintaranpino/nostrcheck-api-ts
// Supports  NIP98 HTTP Auth.
//
// CURL EXAMPLE
// curl --location 'https://nostrcheck.me/api/v1/media?apikey=API_KEY' \
// --form 'mediafile=@"pngtest1.png"' \
// --form 'uploadtype="media"'

// TODO: implement  NIP98 HTTP Auth
func getNostrCheckMeService() -> MediaUploadService {
    
    let NOSTRCHECK_PUBLIC_API_KEY = Bundle.main.infoDictionary?["NOSTRCHECK_PUBLIC_API_KEY"] as? String ?? ""
    
    return MediaUploadService(name: "nostrcheck.me", request: { imageData in
        let url = URL(string: "https://nostrcheck.me/api/v1/media?apikey=\(NOSTRCHECK_PUBLIC_API_KEY)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        let contentType = "multipart/form-data; boundary=\(boundary)"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let body = NSMutableData()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"mediafile\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)

        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"uploadtype\"\r\n\r\n".data(using: .utf8)!)
        body.append("media".data(using: .utf8)!)
        
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body as Data
        return request
    }, urlFromResponse: { (data, response) in
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let status = json["status"] as? Bool,
              status == true,
              let url = json["URL"] as? String else {
//            let httpResponse = response as? HTTPURLResponse
//            L.og.debug(httpResponse?.statusCode ?? "")
//            L.og.debug(httpResponse?.allHeaderFields ?? "")
//            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//            L.og.debug(json?.description ?? "")
            throw ImageUploadError.uploadFailure
        }
        return url.replacingOccurrences(of: "http://", with: "https://")
    })
}
