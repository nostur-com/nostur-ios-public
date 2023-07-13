//
//  NostrcheckMeService.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import Foundation

// https://github.com/quentintaranpino/nostrcheck-api
// different JSON response as others
// max 5 public uploads per day?
// api key in in form data instead of header


// CURL EXAMPLE
//curl --location 'https://nostrcheck.me/api/media.php' \
//--form 'publicgallery=@"testupload.png"' \
//--form 'apikey="26d075787d261660682fb9d20dbffa538c708b1eda921d0efa2be95fbef4910a"' \
//--form 'type="media"'

func getNostrCheckMeService() -> MediaUploadService {
    
    let NOSTRCHECK_PUBLIC_API_KEY = Bundle.main.infoDictionary?["NOSTRCHECK_PUBLIC_API_KEY"] as? String ?? ""
    
    return MediaUploadService(name: "nostrcheck.me", request: { imageData in
        let url = URL(string: "https://nostrcheck.me/api/media.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        let contentType = "multipart/form-data; boundary=\(boundary)"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let body = NSMutableData()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"publicgallery\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)

        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"type\"\r\n\r\n".data(using: .utf8)!)
        body.append("media".data(using: .utf8)!)
        
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"apikey\"\r\n\r\n".data(using: .utf8)!)
        body.append(NOSTRCHECK_PUBLIC_API_KEY.data(using: .utf8)!)
        
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
        return url
    })
}
