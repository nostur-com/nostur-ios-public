//
//  DMFileCache.swift
//  Nostur
//

import Foundation
import CryptoKit

actor DMFileCache {
    static let shared = DMFileCache()

    struct ConversationUsage: Identifiable, Sendable {
        let id: String
        let bytes: Int64
        let fileCount: Int
        let isKept: Bool
    }

    static let maxSizeKey = "dm_file_cache_max_size_mb"
    static let keptConversationsKey = "dm_file_cache_kept_conversations"
    static let defaultMaxSizeMB = 500

    private let fileManager = FileManager.default
    private let rootURL: URL

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        rootURL = caches.appendingPathComponent("DMFiles", isDirectory: true)
    }

    func cachedFileURL(fileInfo: FileMessageInfo, conversationId: String) -> URL? {
        let url = fileURL(fileInfo: fileInfo, conversationId: conversationId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    func data(fileInfo: FileMessageInfo, conversationId: String) async throws -> Data {
        if let cachedURL = cachedFileURL(fileInfo: fileInfo, conversationId: conversationId) {
            return try Data(contentsOf: cachedURL, options: .mappedIfSafe)
        }

        guard let remoteURL = URL(string: fileInfo.url) else {
            throw DMFileError.uploadFailed("Invalid URL: \(fileInfo.url)")
        }
        let (encryptedData, response) = try await URLSession.shared.data(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DMFileError.uploadFailed("HTTP \(statusCode)")
        }

        let decryptedData = try decryptFileFromDM(
            encryptedData: encryptedData,
            key: fileInfo.decryptionKey,
            nonce: fileInfo.decryptionNonce
        )
        if let originalHash = fileInfo.originalHash {
            let actualHash = SHA256.hash(data: decryptedData).map { String(format: "%02x", $0) }.joined()
            guard actualHash.caseInsensitiveCompare(originalHash) == .orderedSame else {
                throw DMFileError.invalidData
            }
        }

        let destination = fileURL(fileInfo: fileInfo, conversationId: conversationId)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try decryptedData.write(to: destination, options: .atomic)
        try? conversationId.data(using: .utf8)?.write(
            to: destination.deletingLastPathComponent().appendingPathComponent("conversation-id"),
            options: .atomic
        )
        trimIfNeeded()
        return decryptedData
    }

    func previewURL(fileInfo: FileMessageInfo, conversationId: String) async throws -> URL {
        if let cached = cachedFileURL(fileInfo: fileInfo, conversationId: conversationId) {
            return cached
        }
        _ = try await data(fileInfo: fileInfo, conversationId: conversationId)
        return fileURL(fileInfo: fileInfo, conversationId: conversationId)
    }

    func usage() -> [ConversationUsage] {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let kept = keptConversationIds

        return directories.compactMap { directory in
            let marker = directory.appendingPathComponent("conversation-id")
            guard let data = try? Data(contentsOf: marker),
                  let conversationId = String(data: data, encoding: .utf8) else { return nil }
            let files = regularFiles(in: directory)
            let bytes = files.reduce(Int64(0)) { result, url in
                result + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0)
            }
            return ConversationUsage(
                id: conversationId,
                bytes: bytes,
                fileCount: files.count,
                isKept: kept.contains(conversationId)
            )
        }
        .sorted { $0.bytes > $1.bytes }
    }

    func totalSize() -> Int64 {
        usage().reduce(0) { $0 + $1.bytes }
    }

    func clear(conversationId: String) throws {
        let directory = conversationDirectory(conversationId)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    func clearAllExceptKept() throws {
        for item in usage() where !item.isKept {
            try clear(conversationId: item.id)
        }
    }

    func setKept(_ kept: Bool, conversationId: String) {
        var ids = keptConversationIds
        if kept { ids.insert(conversationId) } else { ids.remove(conversationId) }
        UserDefaults.standard.set(Array(ids), forKey: Self.keptConversationsKey)
    }

    func isKept(conversationId: String) -> Bool {
        keptConversationIds.contains(conversationId)
    }

    func trimIfNeeded() {
        let maximumBytes = Int64(maxSizeMB) * 1_024 * 1_024
        var files = usage()
            .filter { !$0.isKept }
            .flatMap { regularFiles(in: conversationDirectory($0.id)) }
            .compactMap { url -> (URL, Int64, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
                return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.2 < $1.2 }
        var bytes = totalSize()
        while bytes > maximumBytes, !files.isEmpty {
            let file = files.removeFirst()
            try? fileManager.removeItem(at: file.0)
            bytes -= file.1
        }
        removeEmptyConversationDirectories()
    }

    private var maxSizeMB: Int {
        let value = UserDefaults.standard.integer(forKey: Self.maxSizeKey)
        return value > 0 ? value : Self.defaultMaxSizeMB
    }

    private var keptConversationIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.keptConversationsKey) ?? [])
    }

    private func fileURL(fileInfo: FileMessageInfo, conversationId: String) -> URL {
        let source = fileInfo.originalHash ?? fileInfo.encryptedHash ?? fileInfo.url
        let name = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return conversationDirectory(conversationId)
            .appendingPathComponent(name)
            .appendingPathExtension(fileInfo.fileExtension)
    }

    private func conversationDirectory(_ conversationId: String) -> URL {
        let name = SHA256.hash(data: Data(conversationId.utf8)).map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(name, isDirectory: true)
    }

    private func regularFiles(in directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            $0.lastPathComponent != "conversation-id" &&
            ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false)
        } ?? []
    }

    private func removeEmptyConversationDirectories() {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for directory in directories where regularFiles(in: directory).isEmpty {
            try? fileManager.removeItem(at: directory)
        }
    }
}
