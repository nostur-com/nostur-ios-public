//
//  ImageUploading.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/04/2023.
//

import Foundation
import SwiftUI
import Combine

public struct PostedImageMeta: Hashable, Identifiable, Equatable {
    static public func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    public let id = UUID()
    public let imageData:UIImage
    public let type:ImageType
    
    public enum ImageType {
        case jpeg // from pasting
        case png // from PhotosUI
    }
}

func uploadImages(images: [PostedImageMeta]) -> AnyPublisher<[String], Error> {
    let imagePublishers = images.map { uploadImage(image: $0) }
    return Publishers.MergeMany(imagePublishers)
        .collect()
        .eraseToAnyPublisher()
}

func uploadImage(image: PostedImageMeta, maxWidth:CGFloat = 2800.0) -> AnyPublisher<String, Error> {
    let scale = image.imageData.size.width > maxWidth ? image.imageData.size.width / maxWidth : 1
    let size = CGSize(width: image.imageData.size.width / scale, height: image.imageData.size.height / scale)
    
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1 // 1x scale, for 2x use 2, and so on
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let scaledImage = renderer.image { _ in
        image.imageData.draw(in: CGRect(origin: .zero, size: size))
    }
    
    guard let imageData = scaledImage.jpegData(compressionQuality: 0.85) else {
        return Fail(error: ImageUploadError.conversionFailure).eraseToAnyPublisher()
    }
    
    let request = SettingsStore.shared.defaultMediaUploadService.request(imageData, false)

    let session = URLSession(configuration: .default)
    return session.dataTaskPublisher(for: request)
        .tryMap { data, response -> String in
            return try SettingsStore.shared.defaultMediaUploadService.urlFromResponse((data, response, false))
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
