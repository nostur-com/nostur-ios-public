//
//  VoidCatMediaUploadService.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/04/2023.
//

import Foundation

// Same as IMGUR but no Client ID needed
// link will be just the image url but need to replace http with https
func getVoidCatService() -> MediaUploadService {
    return MediaUploadService(name: "void.cat", request: { imageData in
        let url = URL(string: "https://void.cat/upload?cli=true")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("image/jpg", forHTTPHeaderField: "V-Content-Type")

        request.httpBody = imageData
        return request
    }, urlFromResponse: { (data, response) in
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let responseString = String(data: data, encoding: .utf8),
              responseString.contains("http")
        else {
//            let httpResponse = response as? HTTPURLResponse
//            print(httpResponse?.statusCode)
//            print(httpResponse?.allHeaderFields)
//            let responseText = String(data: data, encoding: .utf8)
//            print(responseText?.description)
            throw ImageUploadError.uploadFailure
        }
        return responseString.replacingOccurrences(of: "http://", with: "https://") + ".jpg"
    })
}
