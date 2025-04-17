//
//  ImageUploading.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/04/2023.
//

import Foundation
import SwiftUI
import Combine
import ImageIO
import MobileCoreServices

public struct PostedImageMeta: Hashable, Identifiable, Equatable {
    
    static public func == (lhs: Self, rhs: Self) -> Bool {
        lhs.uniqueId == rhs.uniqueId
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uniqueId)
        hasher.combine(index)
        hasher.combine(data)
        hasher.combine(type)
        hasher.combine(isGifPlaceholder)
    }
    
    public var id: String { uniqueId }
    public let index: Int // To keep the correct order in pasted images
    public let data: Data
    public let type: ImageType
    public let uniqueId: String
    
    public var isGifPlaceholder = false // to show spinner why fetching actual GIF (Safari copy paste)

    // Image or first frame if .gif
    public var uiImage: UIImage? {
        if type == .gif {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }
        return UIImage(data: data)
    }
    
    public var aspect: CGFloat {
        guard let uiImage else { return 4/3 }
        return uiImage.size.width / uiImage.size.height
    }
    
    public enum ImageType {
        case jpeg // from pasting
        case png // from PhotosUI
        case gif // animated GIFs
    }
}

func uploadImages(images: [PostedImageMeta]) -> AnyPublisher<[String], Error> {
    let imagePublishers = images.map { uploadImage(image: $0) }
    return Publishers.MergeMany(imagePublishers)
        .collect()
        .eraseToAnyPublisher()
}

func uploadImage(image: PostedImageMeta, maxWidth:CGFloat = 2800.0) -> AnyPublisher<String, Error> {
    
    if image.type == .gif {
        let request = SettingsStore.shared.defaultMediaUploadService.request(image.data, false)
        let session = URLSession(configuration: .default)
        return session.dataTaskPublisher(for: request)
            .tryMap { data, response -> String in
                return try SettingsStore.shared.defaultMediaUploadService.urlFromResponse((data, response, false))
            }
            .eraseToAnyPublisher()
    }
    
    guard let imageData = image.uiImage else {
        return Fail(error: ImageUploadError.conversionFailure).eraseToAnyPublisher()
    }
    
    let scale = imageData.size.width > maxWidth ? imageData.size.width / maxWidth : 1
    let size = CGSize(width: imageData.size.width / scale, height: imageData.size.height / scale)
    
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1 // 1x scale, for 2x use 2, and so on
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let scaledImage = renderer.image { _ in
        imageData.draw(in: CGRect(origin: .zero, size: size))
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

extension UIImage {
    func gifData() -> Data? {
        // If the image was created from GIF data, try to get the original data
        if let imageData = self.pngData() {
            // Check if the data starts with GIF magic number
            if imageData.starts(with: [0x47, 0x49, 0x46]) {
                return imageData
            }
        }
        return nil
    }
}
