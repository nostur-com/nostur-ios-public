//
//  ProfileImagesHelpers.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/06/2023.
//

import Foundation
import CryptoKit
import SwiftUI
import Combine

func uploadBannerOrProfilePic(pfp: UIImage?, banner:UIImage?) -> AnyPublisher<[String], Error> {
    var imagePublishers:[AnyPublisher<String, Error>] = []
    
    if let pfp {
        imagePublishers.append( uploadPFPImage(image: pfp) )
    }
    
    if let banner {
        imagePublishers.append( uploadBannerImage(image: banner) )
    }
    return Publishers.MergeMany(imagePublishers)
        .collect()
        .eraseToAnyPublisher()
}

func uploadPFPImage(image: UIImage) -> AnyPublisher<String, Error> {

    // Create a profile pic, preserving aspect ratio, resize to 150x150

    let SIDE:CGFloat = 150
    let size = CGSize(width: SIDE, height: SIDE)
//    let rect = CGRect(origin: CGPoint.zero, size: size)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    
    // Steps.
    // Take smallest of width or height
    // if below 100, upscale to 100
    if image.size.width < image.size.height && image.size.width < SIDE {
        // WIDTH IS TOO SMALL:
        let upscaleFactor = SIDE / image.size.width
        let newHeight = image.size.height * upscaleFactor
        let x = 0.0
        let y = -((newHeight-SIDE)/2).rounded(.down)
        let drawRect = CGRect(x: x, y: y, width: SIDE, height: newHeight)
        image.draw(in: drawRect)
    }
    else if image.size.height < image.size.width && image.size.height < SIDE {
        // HEIGHT IS TOO SMALL:
        let upscaleFactor = SIDE / image.size.height
        let newWidth = image.size.width * upscaleFactor
        let x = -((newWidth-SIDE)/2).rounded(.down)
        let y = 0.0
        let drawRect = CGRect(x: x, y: y, width: newWidth, height: SIDE)
        image.draw(in: drawRect)
    }
    else if image.size.width < image.size.height && image.size.width > SIDE {
        // WIDTH SMALLER THAN HEIGHT, BUT TOO BIG
        let downscaleFactor = image.size.width / SIDE
        let newHeight = image.size.height / downscaleFactor
        let x = 0.0
        let y = -((newHeight-SIDE)/2).rounded(.down)
        let drawRect = CGRect(x: x, y: y, width: SIDE, height: newHeight)
        image.draw(in: drawRect)
    }
    else if image.size.height < image.size.width && image.size.height > SIDE {
        // HEIGHT SMALLER THAN WIDTH, BUT TOO BIG
        let downscaleFactor = image.size.height / SIDE
        let newWidth = image.size.width / downscaleFactor
        let x = -((newWidth-SIDE)/2).rounded(.down)
        let y = 0.0
        let drawRect = CGRect(x: x, y: y, width: newWidth, height: SIDE)
        image.draw(in: drawRect)
    }
    else {
//        let aspect = image.size.width / image.size.height
        let x = 0.0
        let y = 0.0
        let width = SIDE
        let height = SIDE
        let drawRect = CGRect(x: x, y: y, width: width, height: height)
        image.draw(in: drawRect)
    }
    
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
        
    guard let imageData = scaledImage?.jpegData(compressionQuality: 0.8) else {
        return Fail(error: ImageUploadError.conversionFailure).eraseToAnyPublisher()
    }
    
    let url = URL(string: "https://nostur.com/upload2.php")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    let boundary = UUID().uuidString
    let contentType = "multipart/form-data; boundary=\(boundary)"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    
    guard let proof = signedImageProof(imageData: imageData) else { return Fail(error: ImageUploadError.signingFailure).eraseToAnyPublisher() }
    request.setValue(proof.signature, forHTTPHeaderField: "X-Nostur-Signature")
    request.setValue(proof.message, forHTTPHeaderField: "X-Nostur-Message")
    request.setValue(proof.publicKey, forHTTPHeaderField: "X-Nostur-PublicKey")
    
    let body = NSMutableData()
    let fieldName = "image"
    
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    
    request.httpBody = body as Data
    
    let session = URLSession(configuration: .default)
    return session.dataTaskPublisher(for: request)
        .tryMap { data, response -> String in
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let link = json["data"] as? [String: Any],
                  let url = link["link"] as? String else {
//                let httpResponse = response as? HTTPURLResponse
//                print(httpResponse?.statusCode)
//                print(httpResponse?.allHeaderFields)
//                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//                print(json?.description)
                throw ImageUploadError.uploadFailure
            }
            return url
        }
        .eraseToAnyPublisher()
}

// Scales an image to fit within a given height and width
// Preserves aspect ratio
// Fills the entire space, cropping if necessary
func scaleImageToFill(image: UIImage, height: CGFloat, width: CGFloat) -> UIImage? {
    let size = image.size
    let widthRatio = width / size.width
    let heightRatio = height / size.height
    let scaleRatio = max(widthRatio, heightRatio)
    let scaledSize = CGSize(width: (size.width * scaleRatio).rounded(.down), height: (size.height * scaleRatio).rounded(.down))
    let origin = CGPoint(x: (width - scaledSize.width) / 2, y: (height - scaledSize.height) / 2)
    UIGraphicsBeginImageContextWithOptions(CGSize(width: width.rounded(.down), height: height.rounded(.down)), false, 0)
    image.draw(in: CGRect(origin: origin, size: scaledSize))
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return scaledImage
}

func uploadBannerImage(image: UIImage) -> AnyPublisher<String, Error> {
    
    guard let scaledImage = scaleImageToFill(image: image, height: 150, width: 600) else {
        return Fail(error: ImageUploadError.scalingFailure).eraseToAnyPublisher()
    }
    
//    let scaledImage = scaleImageToFill(image: image, height: 300, width: 900)
    
    guard let imageData = scaledImage.jpegData(compressionQuality: 0.8) else {
        return Fail(error: ImageUploadError.conversionFailure).eraseToAnyPublisher()
    }
    
    let url = URL(string: "https://nostur.com/uploadbanner2.php")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    let boundary = UUID().uuidString
    let contentType = "multipart/form-data; boundary=\(boundary)"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    
    guard let proof = signedImageProof(imageData: imageData) else { return Fail(error: ImageUploadError.signingFailure).eraseToAnyPublisher() }
    request.setValue(proof.signature, forHTTPHeaderField: "X-Nostur-Signature")
    request.setValue(proof.message, forHTTPHeaderField: "X-Nostur-Message")
    request.setValue(proof.publicKey, forHTTPHeaderField: "X-Nostur-PublicKey")
    
    let body = NSMutableData()
    let fieldName = "image"
    
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    
    request.httpBody = body as Data
    
    let session = URLSession(configuration: .default)
    return session.dataTaskPublisher(for: request)
        .tryMap { data, response -> String in
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let link = json["data"] as? [String: Any],
                  let url = link["link"] as? String else {
//                let httpResponse = response as? HTTPURLResponse
//                print(httpResponse?.statusCode)
//                print(httpResponse?.allHeaderFields)
//                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//                print(json?.description)
                throw ImageUploadError.uploadFailure
            }
            return url
        }
        .eraseToAnyPublisher()
}

func signedImageProof(imageData:Data) -> (signature: String, message: String, publicKey: String)? {
    guard let privateKeyHexString = account()?.privateKey else { return nil }
    guard let nostrPubkeyHex = account()?.publicKey else { return nil }
    
    // Current profile/pic banner backend runs php, there is no easy way to verify schnorr signatures in
    // php yet, so use Curve25519, works out of the box in both swift and php.
    // TODO: Eventually replace with nostr schnorr verification when there is proper php support so we dont have to derive an extra key
    
    guard let privateKeyData:Data = try? privateKeyHexString.hexa() else { return nil }
    // Create a SymmetricKey from the Schnorr private key data
    let symmetricKey = SymmetricKey(data: privateKeyData)

    
    // Use HKDF to derive a Curve25519 private key
    let info = "Curve25519 private key".data(using: .utf8)!
    let salt = "Salty " + nostrPubkeyHex
    guard let saltData = salt.data(using: .utf8) else { return nil }

    let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: symmetricKey, salt: saltData, info: info, outputByteCount: 32)

    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: derivedKey) else { return nil }

    let publicKey = privateKey.publicKey
    let publicKeyData = publicKey.rawRepresentation
    let publicKeyHexString = publicKeyData.map { String(format: "%02hhx", $0) }.joined()
    
    
    let sha256data = SHA256.hash(data: imageData)
    let sha256string = String(bytes:sha256data.bytes)

    let message = "\(Int64(Date().timeIntervalSince1970).description)|\(sha256string)"
    let messageData = message.data(using: .utf8)!

    let signature = try! privateKey.signature(for: messageData)
    let signatureHexString = signature.map { String(format: "%02hhx", $0) }.joined()

    // Send `signatureHexString`, `message`, and `publicKeyHexString` to the server

    return (signature: signatureHexString, message: message, publicKey: publicKeyHexString)
}

// same as signedImageProof but without imageData, we just hash of the word DELETE
func signedDeleteProof(pk privateKeyHexString:String, pubkey nostrPubkeyHex:String) -> (signature: String, message: String, publicKey: String)? {
    
    // Current profile/pic banner backend runs php, there is no easy way to verify schnorr signatures in
    // php yet, so use Curve25519, works out of the box in both swift and php.
    // TODO: Eventually replace with nostr schnorr verification when there is proper php support so we dont have to derive an extra key
    
    guard let privateKeyData:Data = try? privateKeyHexString.hexa() else { return nil }
    // Create a SymmetricKey from the Schnorr private key data
    let symmetricKey = SymmetricKey(data: privateKeyData)

    
    // Use HKDF to derive a Curve25519 private key
    let info = "Curve25519 private key".data(using: .utf8)!
    let salt = "Salty " + nostrPubkeyHex
    guard let saltData = salt.data(using: .utf8) else { return nil }

    let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: symmetricKey, salt: saltData, info: info, outputByteCount: 32)

    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: derivedKey) else { return nil }
//    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) else { return nil }

    let publicKey = privateKey.publicKey
    let publicKeyData = publicKey.rawRepresentation
    let publicKeyHexString = publicKeyData.map { String(format: "%02hhx", $0) }.joined()
    
    
    let sha256data = SHA256.hash(data: "DELETE".data(using: .utf8)!)
    let sha256string = String(bytes:sha256data.bytes)

    let message = "\(Int64(Date().timeIntervalSince1970).description)|\(sha256string)"
    let messageData = message.data(using: .utf8)!

    let signature = try! privateKey.signature(for: messageData)
    let signatureHexString = signature.map { String(format: "%02hhx", $0) }.joined()

    // Send `signatureHexString`, `message`, and `publicKeyHexString` to the server

    return (signature: signatureHexString, message: message, publicKey: publicKeyHexString)
}

func deletePFPandBanner(pk: String, pubkey:String) {

    let url = URL(string: "https://nostur.com/wipeprofileandbanner.php")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    guard let proof = signedDeleteProof(pk: pk, pubkey:pubkey) else { return }
    request.setValue(proof.signature, forHTTPHeaderField: "X-Nostur-Signature")
    request.setValue(proof.message, forHTTPHeaderField: "X-Nostur-Message")
    request.setValue(proof.publicKey, forHTTPHeaderField: "X-Nostur-PublicKey")
    
    let session = URLSession(configuration: .default)
    let task = session.dataTask(with: request) { data, response, error in
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
              else {
            L.og.error("error deleting profile and banner")
            return
        }
        L.og.info("banner/profile delete request sent successfully")
    }
    task.resume()
}
