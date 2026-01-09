//
//  Blossom.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/01/2026.
//

import Foundation
import NostrEssentials
import Combine

// Blossom uploading usage originally in NewPostModel is a bit messy, this a new clean reusable version

func getBlossomAuthHeader(keys: Keys, blossomFile: BlossomUploadFile) async throws -> String {
    return try getBlossomAuthorizationHeader(keys, sha256hex: blossomFile.sha256)
}

@MainActor
func getBlossomAuthHeader(account: CloudAccount, blossomFile: BlossomUploadFile, timeout: TimeInterval = 10.0) async throws -> String {
    let unsignedNEvent = getUnsignedAuthorizationHeaderEvent(pubkey: account.publicKey, sha256hex: blossomFile.sha256, action: .upload)
    
    if !account.isNC {
        let signedEvent = try account.signEvent(unsignedNEvent)
        guard let authHeader = toHttpAuthHeader(signedEvent) else { throw NSError(domain: "Unable to create base64", code: 999) }
        return authHeader
    }
    else {
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    RemoteSignerManager.shared.requestSignature(forEvent: unsignedNEvent, usingAccount: account) { signedEvent in
                        guard let authHeader = toHttpAuthHeader(signedEvent) else {
                            continuation.resume(throwing: NSError(domain: "Unable to create base64", code: 999))
                            return
                        }
                        continuation.resume(returning: authHeader)
                    }
                }
            }
            
            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SignEventError.timeout
            }
            
            // Return the first result (either success or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

public func nxSignEvent(_ unsignedEvent: NEvent, account: CloudAccount, timeout: TimeInterval = 10.0) async throws -> NEvent {
    return try await withThrowingTaskGroup(of: NEvent.self) { group in
        var unsignedEvent = unsignedEvent
        group.addTask {
            try await withCheckedThrowingContinuation { continuation in
                
                Task { @MainActor in
                    if account.isNC {
                        RemoteSignerManager.shared.requestSignature(forEvent: unsignedEvent, usingAccount: account) { signedEvent in
                            continuation.resume(returning: signedEvent)
                        }
                    }
                    else {
                        guard let pk = account.privateKey, let keys = try? NostrEssentials.Keys(privateKeyHex: pk) else {
                            continuation.resume(throwing: SignEventError.error("Signing Error"))
                            return
                        }
                        if let signedEvent = try? unsignedEvent.sign(keys) {
                            continuation.resume(returning: signedEvent)
                        }
                    }
                }
            }
        }
        
        // Timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw SignEventError.timeout
        }
        
        // Return the first result (either success or timeout)
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

enum SignEventError: Error {
    case error(String)
    case timeout
}

class BlossomUploadFile {
    public var data: Data
    public var contentType: String
    public let sha256: String
    
    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
        self.sha256 = data.sha256().hexEncodedString()
    }
}

// Returns final url
func blossomUpload(authHeader: String, blossomFile: BlossomUploadFile, contentType: String, blossomServer: URL, timeout: TimeInterval = 10.0) async throws -> String {
    return try await withThrowingTaskGroup(of: String.self) { group in
        // Upload task
        group.addTask {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let uploadItem = BlossomUploadItem(data: blossomFile.data, contentType: contentType, authorizationHeader: authHeader, verb: .upload)
                let uploader = BlossomUploader(blossomServer)
                uploader.queued = [uploadItem]
                
                var cancellable: AnyCancellable?
                cancellable = uploader.uploadingPublisher(for: uploadItem)
                    .sink(receiveCompletion: { _ in
                        defer { _ = cancellable } // Keep cancellable alive until completion
                        
                        if uploader.finished, let downloadUrl = uploader.queued.first?.downloadUrl {
                            continuation.resume(returning: downloadUrl)
                        }
                        else {
                            if let uploadState = uploader.queued.first?.state, case .error(let errorMessage) = uploadState {
                                continuation.resume(throwing: BlossomUploadError.error(errorMessage))
                            }
                            else {
                                continuation.resume(throwing: BlossomUploadError.error("Unknown error"))
                            }
                        }
                    }, receiveValue: { uploadItem in
                        uploader.processResponse(uploadItem: uploadItem)
                    })
            }
        }
        
        // Timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw BlossomUploadError.timeout
        }
        
        // Return the first result (either success or timeout)
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

enum BlossomUploadError: Error {
    case error(String) // error message
    case timeout
}

func blossomMirror(authHeader: String, url: String, hash: String, contentType: String, blossomServer: URL, timeout: TimeInterval = 10.0) async throws -> String {
    return try await withThrowingTaskGroup(of: String.self) { group in
        // Mirror task
        group.addTask {
            try await withCheckedThrowingContinuation { continuation in
               
                let config = URLSessionConfiguration.default
                let session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
                    
                var request = URLRequest(url: blossomServer.appendingPathComponent("mirror"))
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
                
                let body = "{\"url\": \"\(url)\"}"
                request.httpBody = body.data(using: .utf8)

                // set content length to body.count
                request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

                Task {
                    do {
                        let (data, response) = try await session.data(for: request)
                        if let httpResponse = response as? HTTPURLResponse {
                            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                                // print response (debug)
//                                if let responseString = String(data: data, encoding: .utf8) {
//                                    print("Blossom mirror response (\(httpResponse.statusCode)): \(responseString)")
//                                }
                                
                                struct MirrorResponse: Codable {
                                    let url: String
//                                    let sha256: String
//                                    let size: Int
//                                    let type: String
//                                    let uploaded: Int
                                }
                                
                                guard let mirrorResponse = try? JSONDecoder().decode(MirrorResponse.self, from: data) else {
                                    continuation.resume(throwing: BlossomMirrorError.error("Failed to decode response"))
                                    return
                                }
                                continuation.resume(returning: mirrorResponse.url)
                            }
                            else {
                                continuation.resume(throwing: BlossomMirrorError.error("HTTP Error: \(httpResponse.statusCode)"))
                            }
                        }
                        else {
                            continuation.resume(throwing: BlossomMirrorError.error("Invalid response type"))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        
        // Timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw BlossomMirrorError.timeout
        }
        
        // Return the first result (either success or timeout)
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

enum BlossomMirrorError: Error {
    case error(String) // error message
    case timeout
}
