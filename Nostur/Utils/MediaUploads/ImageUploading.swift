//
//  ImageUploading.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/04/2023.
//

import Foundation
import SwiftUI
import Combine

func uploadImages(images: [UIImage]) -> AnyPublisher<[String], Error> {
    let imagePublishers = images.map { uploadImage(image: $0) }
    return Publishers.MergeMany(imagePublishers)
        .collect()
        .eraseToAnyPublisher()
}

func uploadImage(image: UIImage, maxWidth:CGFloat = 1800.0) -> AnyPublisher<String, Error> {
    let scale = image.size.width > maxWidth ? image.size.width / maxWidth : 1
    let size = CGSize(width: image.size.width / scale, height: image.size.height / scale)
    
    let renderer = UIGraphicsImageRenderer(size: size)
    let scaledImage = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
    guard let imageData = scaledImage.pngData() else {
        return Fail(error: ImageUploadError.conversionFailure).eraseToAnyPublisher()
    }
    
    let request = SettingsStore.shared.defaultMediaUploadService.request(imageData)

    let session = URLSession(configuration: .default)
    return session.dataTaskPublisher(for: request)
        .tryMap { data, response -> String in
            return try SettingsStore.shared.defaultMediaUploadService.urlFromResponse((data, response))
        }
        .eraseToAnyPublisher()
}

enum ImageUploadError: Error {
    case conversionFailure
    case uploadFailure
    case scalingFailure
    case signingFailure
}

enum ImageDeleteError: Error {
    case signingFailure
    case requestFailure
}

struct MediaUploadService: Identifiable, Hashable {
    static func == (lhs: MediaUploadService, rhs: MediaUploadService) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    var id:String { name }
    let name: String
    let request: (_ with: Data) -> URLRequest
    let urlFromResponse: ((Data, URLResponse)) throws -> String
}
