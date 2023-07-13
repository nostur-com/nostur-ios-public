//
//  VoidCatMediaUploadService.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/04/2023.
//

import Foundation

// Same as IMGUR but no Client ID needed
// link will be just the image url but need to replace http with https

//  CURL EXAMPLE
// curl -X POST 'https://void.cat/upload?cli=true' \
// -H 'accept: */*' \
// -H 'V-Content-Type: image/png' \
// --data-binary "@testupload.png"

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
//            L.og.debug(httpResponse?.statusCode)
//            L.og.debug(httpResponse?.allHeaderFields)
//            let responseText = String(data: data, encoding: .utf8)
//            L.og.debug(responseText?.description)
            throw ImageUploadError.uploadFailure
        }
        return responseString.replacingOccurrences(of: "http://", with: "https://") + ".jpg"
    })
}
