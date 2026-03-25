//
//  DMFileMessageSupport.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/03/2026.
//

import Foundation
import CryptoKit

// MARK: - File Message Info (parsed from kind 15 event tags)

struct FileMessageInfo {
    let url: String              // encrypted file URL (from event content)
    let mimeType: String         // from "file-type" tag
    let encryptionAlgorithm: String // "aes-gcm"
    let decryptionKey: Data      // from "decryption-key" tag (hex decoded)
    let decryptionNonce: Data    // from "decryption-nonce" tag (hex decoded)
    let encryptedHash: String?   // "x" tag
    let originalHash: String?    // "ox" tag
    let fileSize: Int?           // "size" tag
    let dimensions: String?      // "dim" tag (e.g. "1920x1080")
    let blurhash: String?        // "blurhash" tag
    
    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }
    
    var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }
    
    var fileExtension: String {
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "application/pdf": return "pdf"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "xlsx"
        case "application/vnd.ms-excel": return "xls"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        case "application/msword": return "doc"
        case "text/plain": return "txt"
        case "text/csv": return "csv"
        default:
            // Try to extract from mime type
            if let subtype = mimeType.split(separator: "/").last {
                return String(subtype)
            }
            return "bin"
        }
    }
    
    var displayName: String {
        fileExtension.uppercased()
    }
    
    var formattedFileSize: String? {
        guard let fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }
    
    /// Parse FileMessageInfo from an NEvent's tags and content
    static func from(nEvent: NEvent) -> FileMessageInfo? {
        let tags = nEvent.tags
        
        guard let fileType = tags.first(where: { $0.type == "file-type" })?.value else { return nil }
        guard let algorithm = tags.first(where: { $0.type == "encryption-algorithm" })?.value, algorithm == "aes-gcm" else { return nil }
        guard let keyHex = tags.first(where: { $0.type == "decryption-key" })?.value,
              let key = Data(hexString: keyHex), key.count == 32 else { return nil }
        guard let nonceHex = tags.first(where: { $0.type == "decryption-nonce" })?.value,
              let nonce = Data(hexString: nonceHex), nonce.count == 12 else { return nil }
        
        let url = nEvent.content
        guard !url.isEmpty, url.hasPrefix("http") else { return nil }
        
        return FileMessageInfo(
            url: url,
            mimeType: fileType,
            encryptionAlgorithm: algorithm,
            decryptionKey: key,
            decryptionNonce: nonce,
            encryptedHash: tags.first(where: { $0.type == "x" })?.value,
            originalHash: tags.first(where: { $0.type == "ox" })?.value,
            fileSize: tags.first(where: { $0.type == "size" }).flatMap { Int($0.value) },
            dimensions: tags.first(where: { $0.type == "dim" })?.value,
            blurhash: tags.first(where: { $0.type == "blurhash" })?.value
        )
    }
}

// MARK: - AES-GCM Encryption Result

struct EncryptedFileResult {
    let encryptedData: Data       // Combined: nonce (12 bytes) + ciphertext + tag (16 bytes) -- actually we store nonce separately
    let key: Data                 // 32 bytes AES-256 key
    let nonce: Data               // 12 bytes GCM nonce
    let originalHash: String      // sha256 hex of original file
    let encryptedHash: String     // sha256 hex of encrypted data (what gets uploaded)
    let fileSize: Int             // size of encrypted data
}

// MARK: - Encrypt / Decrypt

/// Encrypt file data with AES-256-GCM using a random key and nonce
func encryptFileForDM(data: Data) throws -> EncryptedFileResult {
    let key = SymmetricKey(size: .bits256)
    let nonce = AES.GCM.Nonce()
    
    let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
    
    // sealedBox.ciphertext + tag = the encrypted payload to upload
    let encryptedData = sealedBox.ciphertext + sealedBox.tag
    
    let keyData = key.withUnsafeBytes { Data($0) }
    let nonceData = Data(nonce)
    
    let originalHash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    let encryptedHash = SHA256.hash(data: encryptedData).compactMap { String(format: "%02x", $0) }.joined()
    
    return EncryptedFileResult(
        encryptedData: encryptedData,
        key: keyData,
        nonce: nonceData,
        originalHash: originalHash,
        encryptedHash: encryptedHash,
        fileSize: encryptedData.count
    )
}

/// Decrypt file data received from a kind 15 file message
func decryptFileFromDM(encryptedData: Data, key: Data, nonce: Data) throws -> Data {
    let symmetricKey = SymmetricKey(data: key)
    let gcmNonce = try AES.GCM.Nonce(data: nonce)
    
    // encryptedData = ciphertext + tag (last 16 bytes)
    guard encryptedData.count > 16 else {
        throw DMFileError.invalidData
    }
    let ciphertext = encryptedData.prefix(encryptedData.count - 16)
    let tag = encryptedData.suffix(16)
    
    let sealedBox = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: ciphertext, tag: tag)
    return try AES.GCM.open(sealedBox, using: symmetricKey)
}

enum DMFileError: Error, LocalizedError {
    case invalidData
    case downloadFailed
    case encryptionFailed
    case uploadFailed(String)
    case blossomNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidData: return "Invalid encrypted data"
        case .downloadFailed: return "Failed to download file"
        case .encryptionFailed: return "Failed to encrypt file"
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .blossomNotConfigured: return "Blossom server not configured"
        }
    }
}

// MARK: - Data hex init helper

extension Data {
    init?(hexString: String) {
        let hex = hexString.dropFirst(hexString.hasPrefix("0x") ? 2 : 0)
        guard hex.count % 2 == 0 else { return nil }
        
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
