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

func getNostrCheckMeService() -> MediaUploadService {
    
    let NOSTRCHECK_PUBLIC_API_KEY = Bundle.main.infoDictionary?["NOSTRCHECK_PUBLIC_API_KEY"] as? String ?? ""
    
    return MediaUploadService(name: "nostrcheck.me", request: { imageData, usePNG in
        let url = URL(string: "https://nostrcheck.me/api/v1/media?apikey=\(NOSTRCHECK_PUBLIC_API_KEY)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        let contentType = "multipart/form-data; boundary=\(boundary)"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let body = NSMutableData()
        
        let ext = usePNG ? "png" : "jpeg"
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"mediafile\"; filename=\"image.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/\(ext)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"uploadtype\"\r\n\r\n".data(using: .utf8)!)
        body.append("media".data(using: .utf8)!)
        
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body as Data
        return request
    }, urlFromResponse: { (data, response, _) in
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let status = json["result"] as? Bool,
              status == true,
              let url = json["url"] as? String else {
            
            let httpResponse = response as? HTTPURLResponse
            
            let statusCode = httpResponse?.statusCode ?? -1
            let allHeaderFields = httpResponse?.allHeaderFields ?? [:]
            
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            let jsonDescription = json?.description ?? ""
            L.og.debug("ImageUploadError: statusCode: \(statusCode) headers:\(allHeaderFields) json: \(jsonDescription)")
            throw ImageUploadError.uploadFailure
        }
        L.og.debug("ImageUploadSuccess: json: \(json.description)")
        return url.replacingOccurrences(of: "http://", with: "https://")
    })
}
