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

func uploadImage(image: UIImage, maxWidth:CGFloat = 2800.0) -> AnyPublisher<String, Error> {
    let scale = image.size.width > maxWidth ? image.size.width / maxWidth : 1
    let size = CGSize(width: image.size.width / scale, height: image.size.height / scale)
    
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1 // 1x scale, for 2x use 2, and so on
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let scaledImage = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
    
    let usePNG = false // hasTransparency(image: image) // TODO: Disabled for now
    
//    guard let imageData = usePNG ? scaledImage.pngData() : scaledImage.jpegData(compressionQuality: 0.85) else {
//        return Fail(error: ImageUploadError.conversionFailure).eraseToAnyPublisher()
//    }
    
    guard let imageData = scaledImage.jpegData(compressionQuality: 0.85) else {
        return Fail(error: ImageUploadError.conversionFailure).eraseToAnyPublisher()
    }
    
    let request = SettingsStore.shared.defaultMediaUploadService.request(imageData, usePNG)

    let session = URLSession(configuration: .default)
    return session.dataTaskPublisher(for: request)
        .tryMap { data, response -> String in
            return try SettingsStore.shared.defaultMediaUploadService.urlFromResponse((data, response, usePNG))
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
    let request: (_ with: Data, _ usePNG:Bool) -> URLRequest
    let urlFromResponse: ((Data, URLResponse, Bool)) throws -> String
}


func hasTransparency(image: UIImage) -> Bool {
    guard let cgImage = image.cgImage else {
        return false
    }
    
    let alphaInfo = cgImage.alphaInfo
    
    // Check if the alpha info indicates transparency
    return alphaInfo == .first || alphaInfo == .last || alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
}
