//
//  ImgurMediaUploadService.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/04/2023.
//

import Foundation

// needs registered Client ID
let IMGUR_CLIENT_ID = "1145d64320a5242"

func getImgurService() -> MediaUploadService {
    return MediaUploadService(name: "imgur.com", request: { imageData in
        let url = URL(string: "https://api.imgur.com/3/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Client-ID \(IMGUR_CLIENT_ID)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        let contentType = "multipart/form-data; boundary=\(boundary)"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let body = NSMutableData()
        let fieldName = "image"
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
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
//            print(httpResponse?.statusCode)
//            print(httpResponse?.allHeaderFields)
//            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//            print(json?.description)
            throw ImageUploadError.uploadFailure
        }
        return url
    })
}
