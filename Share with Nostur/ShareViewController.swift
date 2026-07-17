//
//  ShareViewController.swift
//  Share with Nostur
//
//  Created by Fabian Lachman on 13/07/2026.
//

import AVFoundation
import Combine
import ImageIO
import NostrEssentials
import Security
import SwiftUI
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let model = ShareExtensionModel()
    private var hostingController: UIHostingController<ShareExtensionView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = ShareExtensionView(
            model: model,
            cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: ShareExtensionError.cancelled)
            },
            complete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)

        Task {
            await model.load(extensionContext: extensionContext)
        }
    }
}

private struct ShareAccount: Codable, Identifiable, Equatable {
    let pubkey: String
    let name: String
    let pictureURL: String
    let pictureFileURL: String
    let isRemoteSigner: Bool
    let nip46Relay: String
    let remoteSignerPubkey: String
    let writeRelays: [String]

    var id: String { pubkey }

    var remotePictureURL: URL? {
        URL(string: pictureURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var cachedPictureImage: UIImage? {
        let fileString = pictureFileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fileURL = URL(string: fileString), fileURL.isFileURL,
              let imageData = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: imageData)
    }
}

private struct ShareThemeColors {
    private var accentLight: [Double]?
    private var accentDark: [Double]?
    private var listBackgroundLight: [Double]?
    private var listBackgroundDark: [Double]?

    init(defaults: UserDefaults? = nil) {
        accentLight = Self.components(from: defaults, key: "share_theme_accent_light_rgba")
        accentDark = Self.components(from: defaults, key: "share_theme_accent_dark_rgba")
        listBackgroundLight = Self.components(from: defaults, key: "share_theme_list_background_light_rgba")
        listBackgroundDark = Self.components(from: defaults, key: "share_theme_list_background_dark_rgba")
    }

    func accent(for colorScheme: ColorScheme) -> Color {
        color(from: colorScheme == .dark ? accentDark : accentLight) ?? .accentColor
    }

    func listBackground(for colorScheme: ColorScheme) -> Color {
        color(from: colorScheme == .dark ? listBackgroundDark : listBackgroundLight) ?? Color(.systemBackground)
    }

    private func color(from components: [Double]?) -> Color? {
        guard let components, components.count == 4 else { return nil }
        return Color(
            red: components[0],
            green: components[1],
            blue: components[2],
            opacity: components[3]
        )
    }

    private static func components(from defaults: UserDefaults?, key: String) -> [Double]? {
        guard let values = defaults?.array(forKey: key) else { return nil }
        let components = values.compactMap { value -> Double? in
            if let number = value as? NSNumber { return number.doubleValue }
            return value as? Double
        }
        return components.count == 4 ? components : nil
    }
}

@MainActor
private final class ShareExtensionModel: ObservableObject {
    @Published var text = ""
    @Published var sharedURL: URL?
    @Published var mediaPreviews: [ShareMediaPreview] = []
    @Published var mediaUploadStates: [ShareMediaUploadState] = []
    @Published var mediaCount = 0
    @Published var activePubkey = ""
    @Published var activeAccountName = ""
    @Published var activeAccountPictureURL: URL?
    @Published var activeAccountPictureImage: UIImage?
    @Published var shareAccounts: [ShareAccount] = []
    @Published var isLoading = true
    @Published var isPosting = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var shareTheme = ShareThemeColors()

    private var mediaItems: [SharedMediaItem] = []
    private var mediaUploadTask: Task<[ShareMediaMetadata], Error>?
    private var mediaUploadPubkey: String?
    private var uploadedMedia: [ShareMediaMetadata]?
    private var activeAccountIsRemoteSigner = false
    private var activeAccountNip46Relay = ""
    private var activeAccountRemoteSignerPubkey = ""
    private let sharedDefaults = UserDefaults(suiteName: "group.com.nostur.Share")
    private var blossomServerStrings: [String] {
        sharedDefaults?.array(forKey: "blossom_server_list") as? [String] ?? []
    }

    var canPost: Bool {
        guard !isLoading, !isPosting else { return false }
        guard !activePubkey.isEmpty else { return false }
        guard mediaItems.isEmpty || !blossomServerStrings.isEmpty else { return false }
        return !postContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaItems.isEmpty
    }

    var postContent: String {
        var parts: [String] = []
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            parts.append(trimmedText)
        }
        if let sharedURL {
            let urlString = sharedURL.absoluteString
            if !trimmedText.contains(urlString) {
                parts.append(urlString)
            }
        }
        return parts.joined(separator: "\n")
    }

    func load(extensionContext: NSExtensionContext?) async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        text = ""
        sharedURL = nil
        mediaPreviews = []
        mediaUploadStates = []
        mediaCount = 0
        activeAccountPictureImage = nil
        cancelMediaUpload()
        mediaItems = []
        shareTheme = ShareThemeColors(defaults: sharedDefaults)
        shareAccounts = loadSharedAccounts()
        let preferredPubkey = sharedDefaults?.string(forKey: "activeAccountPublicKey") ?? ""
        if let account = shareAccounts.first(where: { $0.pubkey == preferredPubkey }) ?? shareAccounts.first {
            selectAccount(account, persistSelection: false)
        } else {
            loadActiveAccountFromDefaults()
        }

        do {
            let attachments = extensionContext?.inputItems
                .compactMap { $0 as? NSExtensionItem }
                .flatMap { $0.attachments ?? [] } ?? []

            try await loadAttachments(attachments)

            if activePubkey.isEmpty {
                errorMessage = "Open Nostur and select an account first."
            } else if !mediaItems.isEmpty && blossomServerStrings.isEmpty {
                errorMessage = "Configure a Blossom server in Nostur settings before sharing media."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        startMediaUploadIfPossible()
    }

    func selectAccount(_ account: ShareAccount, persistSelection: Bool = true) {
        activePubkey = account.pubkey
        activeAccountName = account.name
        activeAccountPictureURL = account.remotePictureURL
        activeAccountPictureImage = account.cachedPictureImage
        activeAccountIsRemoteSigner = account.isRemoteSigner
        activeAccountNip46Relay = account.nip46Relay
        activeAccountRemoteSignerPubkey = account.remoteSignerPubkey

        if persistSelection {
            cancelMediaUpload()
            startMediaUploadIfPossible()
        }

        guard persistSelection else { return }
        sharedDefaults?.set(account.pubkey, forKey: "activeAccountPublicKey")
        sharedDefaults?.set(account.name, forKey: "activeAccountName")
        sharedDefaults?.set(account.pictureURL, forKey: "activeAccountPictureURL")
        sharedDefaults?.set(account.pictureFileURL, forKey: "activeAccountPictureFileURL")
        sharedDefaults?.set(account.isRemoteSigner, forKey: "activeAccountIsRemoteSigner")
        sharedDefaults?.set(account.nip46Relay, forKey: "activeAccountNip46Relay")
        sharedDefaults?.set(account.remoteSignerPubkey, forKey: "activeAccountRemoteSignerPubkey")
        sharedDefaults?.set(account.writeRelays, forKey: "write_relay_list")
        sharedDefaults?.synchronize()
    }

    private func loadSharedAccounts() -> [ShareAccount] {
        guard let data = sharedDefaults?.data(forKey: "share_accounts"),
              let accounts = try? JSONDecoder().decode([ShareAccount].self, from: data) else { return [] }
        return accounts
    }

    private func loadActiveAccountFromDefaults() {
        activePubkey = sharedDefaults?.string(forKey: "activeAccountPublicKey") ?? ""
        activeAccountName = sharedDefaults?.string(forKey: "activeAccountName") ?? ""
        activeAccountIsRemoteSigner = sharedDefaults?.bool(forKey: "activeAccountIsRemoteSigner") ?? false
        activeAccountNip46Relay = sharedDefaults?.string(forKey: "activeAccountNip46Relay") ?? ""
        activeAccountRemoteSignerPubkey = sharedDefaults?.string(forKey: "activeAccountRemoteSignerPubkey") ?? ""

        let accountPictureString = (sharedDefaults?.string(forKey: "activeAccountPictureURL") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        activeAccountPictureURL = URL(string: accountPictureString)
        let accountPictureFileString = (sharedDefaults?.string(forKey: "activeAccountPictureFileURL") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fileURL = URL(string: accountPictureFileString), fileURL.isFileURL,
           let imageData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: imageData) {
            activeAccountPictureImage = image
        }
    }

    func removeMedia(at index: Int) {
        guard !isPosting else { return }
        guard mediaItems.indices.contains(index) else { return }

        cancelMediaUpload()
        mediaItems.remove(at: index)
        if mediaPreviews.indices.contains(index) {
            mediaPreviews.remove(at: index)
        }
        if mediaUploadStates.indices.contains(index) {
            mediaUploadStates.remove(at: index)
        }
        mediaCount = mediaItems.count
        startMediaUploadIfPossible()
    }

    private func startMediaUploadIfPossible() {
        guard mediaUploadTask == nil else { return }
        guard !mediaItems.isEmpty, !activePubkey.isEmpty, !blossomServerStrings.isEmpty else { return }

        do {
            let signer = try loadSigner()
            let uploadPubkey = signer.publicKey
            mediaUploadPubkey = uploadPubkey
            uploadedMedia = nil
            mediaUploadTask = Task { [weak self] in
                guard let self else { return [] }
                do {
                    let imetas = try await self.uploadMediaIfNeeded(signer: signer)
                    if self.mediaUploadPubkey == uploadPubkey {
                        self.uploadedMedia = imetas
                        self.mediaUploadTask = nil
                        if !self.isPosting {
                            self.statusMessage = "Media uploaded."
                        }
                    }
                    return imetas
                } catch {
                    if !(error is CancellationError), self.mediaUploadPubkey == uploadPubkey {
                        self.mediaUploadTask = nil
                        self.errorMessage = error.localizedDescription
                        self.statusMessage = nil
                    }
                    throw error
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelMediaUpload() {
        mediaUploadTask?.cancel()
        mediaUploadTask = nil
        mediaUploadPubkey = nil
        uploadedMedia = nil
    }

    private func mediaMetadataForPosting(signer: ShareEventSigner) async throws -> [ShareMediaMetadata] {
        guard !mediaItems.isEmpty else { return [] }

        if mediaUploadPubkey != signer.publicKey {
            cancelMediaUpload()
        }

        if let uploadedMedia, mediaUploadPubkey == signer.publicKey {
            return uploadedMedia
        }

        startMediaUploadIfPossible()
        guard let mediaUploadTask else {
            return try await uploadMediaIfNeeded(signer: signer)
        }

        let imetas = try await mediaUploadTask.value
        uploadedMedia = imetas
        self.mediaUploadTask = nil
        return imetas
    }

    func post() async -> Bool {
        guard canPost else { return false }

        isPosting = true
        errorMessage = nil
        statusMessage = "Signing..."

        do {
            let signer = try loadSigner()
            let imetas = try await mediaMetadataForPosting(signer: signer)
            let finalContent = content(with: imetas)
            let event = Event(pubkey: signer.publicKey, content: finalContent, kind: 1, tags: postTags(from: imetas, pubkey: signer.publicKey))
            let signedEvent = try await signer.sign(event)

            statusMessage = "Publishing..."
            let publishedRelays = try await ShareRelayPublisher().publish(event: signedEvent)
            statusMessage = "Posted to \(publishedRelays.count) relay\(publishedRelays.count == 1 ? "" : "s")."
            isPosting = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            isPosting = false
            return false
        }
    }

    private func loadAttachments(_ providers: [NSItemProvider]) async throws {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), sharedURL == nil {
                sharedURL = try await provider.loadURL()
            } else if provider.canLoadObject(ofClass: NSString.self), text.isEmpty {
                text = try await provider.loadString()
            } else if let typeIdentifier = provider.registeredTypeIdentifier(conformingTo: .movie) {
                let data = try await provider.loadFileData(typeIdentifier: typeIdentifier)
                let contentType = UTType(typeIdentifier)?.preferredMIMEType ?? "video/quicktime"
                let preview = ShareVideoThumbnailGenerator.thumbnail(from: data, contentType: contentType)
                mediaItems.append(SharedMediaItem(data: data, contentType: contentType))
                mediaCount = mediaItems.count
                mediaPreviews.append(ShareMediaPreview(data: data, contentType: contentType, fallbackImage: preview))
                mediaUploadStates.append(.idle)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let data = try await provider.loadData(typeIdentifier: UTType.image.identifier)
                let contentType = provider.registeredTypeIdentifiers
                    .compactMap { UTType($0)?.preferredMIMEType }
                    .first { $0.hasPrefix("image/") } ?? "image/jpeg"
                mediaItems.append(SharedMediaItem(data: data, contentType: contentType))
                mediaCount = mediaItems.count
                if let preview = UIImage(data: data) {
                    mediaPreviews.append(ShareMediaPreview(data: data, contentType: contentType, fallbackImage: preview))
                    mediaUploadStates.append(.idle)
                }
            }
        }
    }

    private func uploadMediaIfNeeded(signer: ShareEventSigner) async throws -> [ShareMediaMetadata] {
        guard !mediaItems.isEmpty else { return [] }
        let blossomServers = blossomServerStrings.compactMap(URL.init(string:))
        guard let server = blossomServers.first else {
            throw ShareExtensionError.noBlossomServer
        }
        let mirrorServers = Array(blossomServers.dropFirst())

        statusMessage = mediaItems.count == 1 ? "Uploading media..." : "Uploading \(mediaItems.count) media items..."

        let uploader = ShareBlossomUploader(server: server)
        let progressSink = ShareUploadProgressSink(model: self)
        let uploadItems = Array(mediaItems.enumerated())
        let maxConcurrentMediaTasks = 2
        var nextItemIndex = 0
        var imetas = Array<ShareMediaMetadata?>(repeating: nil, count: mediaItems.count)

        func addNextMediaTask(to group: inout ThrowingTaskGroup<(Int, ShareMediaMetadata), Error>) {
            guard nextItemIndex < uploadItems.count else { return }
            let (index, mediaItem) = uploadItems[nextItemIndex]
            nextItemIndex += 1

            group.addTask {
                do {
                    progressSink.set(0, forMediaAt: index)

                    let imeta = try await uploader.upload(mediaItem: mediaItem, signer: signer) { progress in
                        let uploadProgress = mirrorServers.isEmpty ? progress : progress * 0.9
                        progressSink.set(uploadProgress, forMediaAt: index)
                    }

                    if mirrorServers.isEmpty {
                        progressSink.set(1, forMediaAt: index)
                    } else {
                        progressSink.set(0.9, forMediaAt: index)
                        let mirrorSucceeded = await ShareBlossomMirrorer(servers: mirrorServers).mirror(imeta: imeta, signer: signer) { progress in
                            progressSink.set(0.9 + (progress * 0.1), forMediaAt: index)
                        }
                        progressSink.set(1, forMediaAt: index, mirrorFailed: !mirrorSucceeded)
                    }

                    return (index, imeta)
                } catch {
                    progressSink.fail(forMediaAt: index)
                    throw error
                }
            }
        }

        statusMessage = signer.needsRemoteApproval ? "Waiting for remote signer..." : (mirrorServers.isEmpty ? "Uploading media..." : "Uploading and mirroring media...")
        try await withThrowingTaskGroup(of: (Int, ShareMediaMetadata).self) { group in
            for _ in 0..<min(maxConcurrentMediaTasks, uploadItems.count) {
                addNextMediaTask(to: &group)
            }

            while let (index, imeta) = try await group.next() {
                imetas[index] = imeta
                addNextMediaTask(to: &group)
            }
        }

        return imetas.compactMap { $0 }
    }

    fileprivate func setUploadProgress(_ progress: Double, forMediaAt index: Int, mirrorFailed: Bool = false) {
        guard mediaUploadStates.indices.contains(index) else { return }
        mediaUploadStates[index] = .progress(min(max(progress, 0), 1), mirrorFailed: mirrorFailed)
    }

    fileprivate func setUploadFailed(forMediaAt index: Int) {
        guard mediaUploadStates.indices.contains(index) else { return }
        mediaUploadStates[index] = .failed
    }

    private func content(with imetas: [ShareMediaMetadata]) -> String {
        var parts = postContent
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        for imeta in imetas {
            if !parts.contains(imeta.url) {
                parts.append(imeta.url)
            }
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func postTags(from imetas: [ShareMediaMetadata], pubkey: String) -> [Tag] {
        var tags = imetas.map { imeta in
            var parts = ["imeta", "url \(imeta.url)"]
            if let dim = imeta.dim, !dim.isEmpty {
                parts.append("dim \(dim)")
            }
            if let hash = imeta.hash, !hash.isEmpty {
                parts.append("sha256 \(hash)")
            }
            return Tag(parts)
        }

        if shouldAppendClientTag(for: pubkey) {
            tags.append(Tag(["client", shareNIP89AppName, shareNIP89AppReference]))
        }

        return tags
    }

    private func shouldAppendClientTag(for pubkey: String) -> Bool {
        guard sharedDefaults?.bool(forKey: "post_user_agent_enabled") ?? true else { return false }
        let excluded = Set((sharedDefaults?.string(forKey: "excluded_user_agent_pubkeys") ?? "").split(separator: " ").map(String.init))
        return !excluded.contains(pubkey)
    }

    private var shareNIP89AppName: String {
        let name = sharedDefaults?.string(forKey: "nip89_app_name") ?? ""
        return name.isEmpty ? "Nostur" : name
    }

    private var shareNIP89AppReference: String {
        sharedDefaults?.string(forKey: "nip89_app_reference") ?? ""
    }

    private func loadSigner() throws -> ShareEventSigner {
        if activeAccountIsRemoteSigner {
            guard let relay = URL(string: activeAccountNip46Relay), ["wss", "ws"].contains(relay.scheme?.lowercased() ?? "") else {
                throw ShareExtensionError.remoteSignerRelayUnavailable
            }
            guard !activeAccountRemoteSignerPubkey.isEmpty else {
                throw ShareExtensionError.remoteSignerPubkeyUnavailable
            }
            let sessionPrivateKey = try loadPrivateKey(service: "nc", accounts: [activeAccountRemoteSignerPubkey, activePubkey])
            return .remote(ShareRemoteSignerAccount(
                publicKey: activePubkey,
                relay: relay,
                remoteSignerPubkey: activeAccountRemoteSignerPubkey,
                sessionPrivateKey: sessionPrivateKey
            ))
        }

        let privateKey = try loadPrivateKey(service: "nostur.com.Nostur", accounts: [activePubkey])
        let keys = try Keys(privateKeyHex: privateKey)
        return .local(keys)
    }

    private func loadPrivateKey(service: String, accounts: [String]) throws -> String {
        var lastStatus: OSStatus = errSecItemNotFound
        for account in accounts where !account.isEmpty {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess {
                guard let data = result as? Data,
                      let privateKey = String(data: data, encoding: .utf8),
                      !privateKey.isEmpty else {
                    throw ShareExtensionError.invalidPrivateKey
                }
                return privateKey
            }
            lastStatus = status
        }

        throw ShareExtensionError.privateKeyUnavailable(lastStatus)
    }
}

private final class ShareUploadProgressSink: @unchecked Sendable {
    private weak var model: ShareExtensionModel?

    init(model: ShareExtensionModel) {
        self.model = model
    }

    func set(_ progress: Double, forMediaAt index: Int, mirrorFailed: Bool = false) {
        Task { @MainActor in
            model?.setUploadProgress(progress, forMediaAt: index, mirrorFailed: mirrorFailed)
        }
    }

    func fail(forMediaAt index: Int) {
        Task { @MainActor in
            model?.setUploadFailed(forMediaAt: index)
        }
    }
}

private enum ShareMediaUploadState: Equatable {
    case idle
    case progress(Double, mirrorFailed: Bool)
    case failed

    var progress: Double? {
        guard case .progress(let progress, _) = self else { return nil }
        return progress
    }

    var hasFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var mirrorFailed: Bool {
        guard case .progress(_, let mirrorFailed) = self else { return false }
        return mirrorFailed
    }
}

private enum ShareEventSigner {
    case local(Keys)
    case remote(ShareRemoteSignerAccount)

    var publicKey: String {
        switch self {
        case .local(let keys):
            return keys.publicKeyHex
        case .remote(let account):
            return account.publicKey
        }
    }

    var needsRemoteApproval: Bool {
        if case .remote = self { return true }
        return false
    }

    func sign(_ event: Event) async throws -> Event {
        switch self {
        case .local(let keys):
            var eventToSign = event
            return try eventToSign.sign(keys)
        case .remote(let account):
            return try await ShareNIP46Signer(account: account).sign(event)
        }
    }

    func blossomAuthorizationHeader(sha256hex: String) async throws -> String {
        switch self {
        case .local(let keys):
            return try getBlossomAuthorizationHeader(keys, sha256hex: sha256hex)
        case .remote:
            let expirationTimestamp = Int(Date().timeIntervalSince1970) + 300
            let event = Event(pubkey: publicKey, content: "Upload", kind: 24242, tags: [
                Tag(["t", "upload"]),
                Tag(["x", sha256hex]),
                Tag(["expiration", expirationTimestamp.description])
            ])
            let signedEvent = try await sign(event)
            let jsonString = try ShareEventJSON.encode(signedEvent)
            guard let jsonData = jsonString.data(using: .utf8, allowLossyConversion: true) else {
                throw ShareExtensionError.couldNotEncodeEvent
            }
            return "Nostr \(jsonData.base64EncodedString())"
        }
    }
}

private struct ShareRemoteSignerAccount: Sendable {
    let publicKey: String
    let relay: URL
    let remoteSignerPubkey: String
    let sessionPrivateKey: String
}

private struct ShareNIP46Signer {
    let account: ShareRemoteSignerAccount
    private let timeout: TimeInterval = 12

    func sign(_ event: Event) async throws -> Event {
        try await withThrowingTaskGroup(of: Event.self) { group in
            group.addTask {
                try await signWithRemoteSigner(event)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ShareExtensionError.remoteSignerTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func signWithRemoteSigner(_ event: Event) async throws -> Event {
        let sessionKeys = try Keys(privateKeyHex: account.sessionPrivateKey)
        let commandId = "sign-event-\(UUID().uuidString)"
        let eventJson = try ShareEventJSON.encode(event)
        let request = ShareNCRequest(id: commandId, method: "sign_event", params: [eventJson])
        let requestJsonData = try JSONEncoder().encode(request)
        guard let requestJson = String(data: requestJsonData, encoding: .utf8) else {
            throw ShareExtensionError.couldNotEncodeEvent
        }
        guard let encrypted = Keys.encryptDirectMessageContent44(
            withPrivatekey: sessionKeys.privateKeyHex,
            pubkey: account.remoteSignerPubkey,
            content: requestJson
        ) else {
            throw ShareExtensionError.remoteSignerEncryptionFailed
        }

        var requestEvent = Event(pubkey: sessionKeys.publicKeyHex, content: encrypted, kind: 24133, tags: [
            Tag(["p", account.remoteSignerPubkey])
        ])
        requestEvent = try requestEvent.sign(sessionKeys)

        guard let eventMessage = ClientMessage(type: .EVENT, event: requestEvent).json() else {
            throw ShareExtensionError.couldNotEncodeEvent
        }

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: account.relay)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        try await task.send(.string(subscriptionMessage(sessionPubkey: sessionKeys.publicKeyHex)))
        try await task.send(.string(eventMessage))

        while !Task.isCancelled {
            let message = try await task.receive()
            guard let responseEvent = try responseEvent(from: message, sessionPubkey: sessionKeys.publicKeyHex) else {
                continue
            }
            guard let decrypted = Keys.decryptDirectMessageContent(
                withPrivateKey: account.sessionPrivateKey,
                pubkey: responseEvent.pubkey,
                content: responseEvent.content
            ) ?? Keys.decryptDirectMessageContent44(
                withPrivateKey: account.sessionPrivateKey,
                pubkey: responseEvent.pubkey,
                content: responseEvent.content
            ) else {
                continue
            }

            let response = try JSONDecoder().decode(ShareNCResponse.self, from: Data(decrypted.utf8))
            guard response.id == commandId else { continue }
            if let error = response.error {
                throw ShareExtensionError.remoteSignerRejected(error)
            }
            guard let result = response.result else {
                throw ShareExtensionError.remoteSignerInvalidResponse
            }
            return try JSONDecoder().decode(Event.self, from: Data(result.utf8))
        }

        throw ShareExtensionError.remoteSignerTimeout
    }

    private func subscriptionMessage(sessionPubkey: String) -> String {
        "[\"REQ\",\"NC-\(UUID().uuidString)\",{\"authors\":[\"\(account.remoteSignerPubkey)\"],\"#p\":[\"\(sessionPubkey)\"],\"kinds\":[24133]}]"
    }

    private func responseEvent(from message: URLSessionWebSocketTask.Message, sessionPubkey: String) throws -> Event? {
        let data: Data
        switch message {
        case .string(let string):
            data = Data(string.utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 3,
              json.first as? String == "EVENT",
              let eventObject = json[2] as? [String: Any] else {
            return nil
        }

        guard eventObject["kind"] as? Int == 24133,
              eventObject["pubkey"] as? String == account.remoteSignerPubkey,
              hasPTag(for: sessionPubkey, in: eventObject) else {
            return nil
        }

        let eventData = try JSONSerialization.data(withJSONObject: eventObject)
        return try JSONDecoder().decode(Event.self, from: eventData)
    }

    private func hasPTag(for pubkey: String, in eventObject: [String: Any]) -> Bool {
        guard let tags = eventObject["tags"] as? [[Any]] else { return false }
        return tags.contains { tag in
            tag.count >= 2 && tag[0] as? String == "p" && tag[1] as? String == pubkey
        }
    }
}

private struct ShareNCRequest: Codable {
    let id: String
    let method: String
    let params: [String]
}

private struct ShareNCResponse: Codable {
    let id: String
    let result: String?
    let error: String?
}

private enum ShareEventJSON {
    static func encode(_ event: Event) throws -> String {
        let data = try JSONEncoder().encode(event)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ShareExtensionError.couldNotEncodeEvent
        }
        return string
    }
}

private struct SharedMediaItem {
    let data: Data
    let contentType: String
}

private struct ShareMediaPreview: Equatable {
    let data: Data
    let contentType: String
    let fallbackImage: UIImage

    var isGIF: Bool {
        contentType.lowercased() == "image/gif" || data.prefix(3) == Data([0x47, 0x49, 0x46])
    }

    var isVideo: Bool {
        contentType.lowercased().hasPrefix("video/")
    }

    var aspectRatio: CGFloat {
        guard fallbackImage.size.height > 0 else { return 1 }
        return fallbackImage.size.width / fallbackImage.size.height
    }
}

private enum ShareVideoThumbnailGenerator {
    static func thumbnail(from data: Data, contentType: String) -> UIImage {
        let fileExtension = UTType(mimeType: contentType)?.preferredFilenameExtension ?? "mov"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        do {
            try data.write(to: fileURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let asset = AVURLAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1200, height: 1200)

            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return placeholder()
        }
    }

    private static func placeholder() -> UIImage {
        let size = CGSize(width: 1200, height: 675)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private struct ShareMediaMetadata {
    let url: String
    let dim: String?
    let hash: String?
}

private struct PreparedShareMediaItem {
    let data: Data
    let contentType: String
    let dim: String?
}

private struct ShareBlossomUploader {
    let server: URL

    func upload(mediaItem: SharedMediaItem, signer: ShareEventSigner, onProgress: @escaping (Double) -> Void) async throws -> ShareMediaMetadata {
        let prepared = prepare(mediaItem: mediaItem)
        let sha256 = prepared.data.sha256().hexEncodedString()
        let authHeader = try await signer.blossomAuthorizationHeader(sha256hex: sha256)
        let blossomType = (try? await testBlossomServer(server, authorization: authHeader, sha256: sha256)) ?? .none

        switch blossomType {
        case .media, .upload:
            break
        case .unauthorized:
            throw ShareExtensionError.blossomUnauthorized
        case .none:
            throw ShareExtensionError.blossomUnsupported
        }

        let response = try await upload(prepared: prepared, sha256: sha256, authHeader: authHeader, verb: blossomType, onProgress: onProgress)
        let responseURL = response.nip94?.first(where: { $0.type == "url" })?.value ?? response.url
        let responseDim = response.nip94?.first(where: { $0.type == "dim" })?.value ?? prepared.dim
        let responseHash = response.nip94?.first(where: { $0.type == "x" })?.value ?? response.sha256

        return ShareMediaMetadata(url: responseURL, dim: responseDim, hash: responseHash)
    }

    private func prepare(mediaItem: SharedMediaItem) -> PreparedShareMediaItem {
        guard mediaItem.contentType != "image/gif", let uiImage = UIImage(data: mediaItem.data) else {
            return PreparedShareMediaItem(data: mediaItem.data, contentType: mediaItem.contentType, dim: nil)
        }

        let maxWidth: CGFloat = 2800
        let resized = uiImage.resizedForShare(maxWidth: maxWidth)
        let data = resized.jpegData(compressionQuality: 0.85) ?? mediaItem.data
        let dim = "\(Int(resized.size.width))x\(Int(resized.size.height))"
        return PreparedShareMediaItem(data: data, contentType: "image/jpeg", dim: dim)
    }

    private func upload(prepared: PreparedShareMediaItem, sha256: String, authHeader: String, verb: SupportedBlossomType, onProgress: @escaping (Double) -> Void) async throws -> BlossomUploadResponse {
        let endpoint = verb == .upload ? "upload" : "media"
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let progressDelegate = ShareUploadProgressDelegate(totalBytes: prepared.data.count, onProgress: onProgress)
        let session = URLSession(configuration: config, delegate: progressDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: server.appendingPathComponent(endpoint))
        request.httpMethod = "PUT"
        request.setValue(prepared.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue(sha256, forHTTPHeaderField: "X-SHA-256")

        let (data, response) = try await withUploadStallTimeout(initialGraceSeconds: 90, stallSeconds: 45, session: session, request: request, data: prepared.data, progressDelegate: progressDelegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareExtensionError.blossomUploadFailed
        }

        guard (200...202).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ShareExtensionError.blossomUnauthorized
            }
            throw ShareExtensionError.blossomUploadFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BlossomUploadResponse.self, from: data)
    }

    private func withUploadStallTimeout(initialGraceSeconds: TimeInterval, stallSeconds: TimeInterval, session: URLSession, request: URLRequest, data: Data, progressDelegate: ShareUploadProgressDelegate) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                try await session.upload(for: request, from: data)
            }
            group.addTask {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    if progressDelegate.hasTimedOut(initialGraceSeconds: initialGraceSeconds, stallSeconds: stallSeconds) {
                        session.invalidateAndCancel()
                        throw ShareExtensionError.blossomUploadTimeout
                    }
                }
                throw CancellationError()
            }

            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}

private final class ShareUploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let totalBytes: Int
    private let onProgress: (Double) -> Void
    private let lock = NSLock()
    private let startedAt = Date()
    private var lastProgressDate: Date?
    private var lastProgressBytes: Int64 = 0

    init(totalBytes: Int, onProgress: @escaping (Double) -> Void) {
        self.totalBytes = totalBytes
        self.onProgress = onProgress
    }

    func hasTimedOut(initialGraceSeconds: TimeInterval, stallSeconds: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let lastProgressDate {
            return now.timeIntervalSince(lastProgressDate) >= stallSeconds
        }
        return now.timeIntervalSince(startedAt) >= initialGraceSeconds
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let expected = totalBytesExpectedToSend > 0 ? Double(totalBytesExpectedToSend) : Double(totalBytes)
        guard expected > 0 else { return }
        lock.lock()
        if totalBytesSent > lastProgressBytes {
            lastProgressBytes = totalBytesSent
            lastProgressDate = Date()
        } else if totalBytesSent > 0, lastProgressDate == nil {
            lastProgressDate = Date()
        }
        lock.unlock()
        onProgress(min(max(Double(totalBytesSent) / expected, 0), 1))
    }
}

private struct ShareBlossomMirrorer {
    let servers: [URL]

    func mirror(imeta: ShareMediaMetadata, signer: ShareEventSigner, onProgress: @escaping (Double) -> Void = { _ in }) async -> Bool {
        guard !servers.isEmpty else {
            onProgress(1)
            return true
        }
        guard let hash = imeta.hash, !hash.isEmpty else {
            onProgress(1)
            return false
        }
        guard let authHeader = try? await signer.blossomAuthorizationHeader(sha256hex: hash) else {
            onProgress(1)
            return false
        }

        let totalServers = servers.count
        return await withTaskGroup(of: Bool.self) { group in
            for server in servers {
                group.addTask {
                    do {
                        try await mirror(url: imeta.url, to: server, authHeader: authHeader)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var completedServers = 0
            var allSucceeded = true
            for await didSucceed in group {
                completedServers += 1
                allSucceeded = allSucceeded && didSucceed
                onProgress(Double(completedServers) / Double(totalServers))
            }
            return allSucceeded
        }
    }

    private func mirror(url: String, to server: URL, authHeader: String) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: server.appendingPathComponent("mirror"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let bodyData = try JSONEncoder().encode(MirrorRequest(url: url))
        request.httpBody = bodyData
        request.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...202).contains(httpResponse.statusCode) else {
            throw ShareExtensionError.blossomMirrorFailed
        }
    }

    private struct MirrorRequest: Encodable {
        let url: String
    }
}

private extension UIImage {
    func resizedForShare(maxWidth: CGFloat) -> UIImage {
        guard size.width > maxWidth else { return self }

        let scale = maxWidth / size.width
        let targetSize = CGSize(width: maxWidth, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private struct ShareExtensionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: ShareExtensionModel
    let cancel: () -> Void
    let complete: () -> Void

    private var accentColor: Color {
        model.shareTheme.accent(for: colorScheme)
    }

    private var listBackground: Color {
        model.shareTheme.listBackground(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    ShareComposeBody(
                        model: model,
                        accentColor: accentColor
                    )
                    .padding()
                }

                if let message = model.errorMessage {
                    MessageBar(text: message, color: .red, backgroundColor: listBackground)
                } else if let message = model.statusMessage {
                    MessageBar(text: message, color: .secondary, backgroundColor: listBackground)
                }
            }
            .background(listBackground)
            .tint(accentColor)
            .navigationTitle("Share with Nostur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await model.post() {
                                complete()
                            }
                        }
                    } label: {
                        if model.isPosting {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .accessibilityLabel("Post")
                    .disabled(!model.canPost)
                    .opacity(model.canPost ? 1 : 0.25)
                }
            }
            .overlay {
                if model.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
    }
}

private struct ShareComposeBody: View {
    @ObservedObject var model: ShareExtensionModel
    let accentColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ShareAccountSwitcher(
                activePubkey: model.activePubkey,
                accounts: model.shareAccounts,
                fallbackImage: model.activeAccountPictureImage,
                fallbackPictureURL: model.activeAccountPictureURL,
                onSelect: { account in model.selectAccount(account) }
            )

            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $model.text)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if model.text.isEmpty {
                            Text("What do you want to say?")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .disabled(model.isPosting)

                if !model.mediaPreviews.isEmpty {
                    ShareMediaPreviews(
                        previews: model.mediaPreviews,
                        uploadStates: model.mediaUploadStates,
                        accentColor: accentColor,
                        canRemove: model.mediaPreviews.count > 1 && !model.isPosting,
                        removeMedia: model.removeMedia
                    )
                }

                if let sharedURL = model.sharedURL {
                    LinkPreview(url: sharedURL)
                }
            }
        }
    }
}

private struct ShareAccountSwitcher: View {
    let activePubkey: String
    let accounts: [ShareAccount]
    let fallbackImage: UIImage?
    let fallbackPictureURL: URL?
    let onSelect: (ShareAccount) -> Void

    @State private var expanded = false

    private let size: CGFloat = 50

    private var sortedAccounts: [ShareAccount] {
        accounts.sorted { lhs, rhs in
            if lhs.pubkey == activePubkey { return true }
            if rhs.pubkey == activePubkey { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay(alignment: .topLeading) {
                if sortedAccounts.isEmpty {
                    AccountAvatar(image: fallbackImage, pictureURL: fallbackPictureURL)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(sortedAccounts.enumerated()), id: \.element.pubkey) { index, account in
                            AccountAvatar(image: account.cachedPictureImage, pictureURL: account.remotePictureURL)
                                .onTapGesture {
                                    accountTapped(account)
                                }
                                .opacity(index == 0 || expanded ? 1.0 : (index > 3 ? 0.0 : 0.2))
                                .zIndex(-Double(index))
                                .offset(y: expanded || index == 0 ? 0 : Double(index) * -(size - 2))
                                .animation(.easeOut(duration: 0.2), value: expanded)
                                .id(account.pubkey)
                        }
                    }
                    .fixedSize()
                }
            }
    }

    private func accountTapped(_ account: ShareAccount) {
        if !expanded, sortedAccounts.count > 1 {
            withAnimation {
                expanded = true
            }
        } else {
            withAnimation {
                onSelect(account)
                expanded = false
            }
        }
    }

}

private struct AccountAvatar: View {
    let image: UIImage?
    let pictureURL: URL?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: pictureURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackImage
                    }
                }
            }
        }
        .frame(width: 50, height: 50)
        .background(Color(.secondarySystemBackground))
        .clipShape(Circle())
    }

    private var fallbackImage: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
            .padding(2)
    }
}

private struct ShareMediaPreviews: View {
    let previews: [ShareMediaPreview]
    let uploadStates: [ShareMediaUploadState]
    let accentColor: Color
    let canRemove: Bool
    let removeMedia: (Int) -> Void

    private var columnCount: Int {
        previews.count == 1 ? 1 : min(previews.count, 3)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 5), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(Array(previews.enumerated()), id: \.offset) { index, preview in
                MediaThumbnail(
                    preview: preview,
                    uploadState: uploadStates.indices.contains(index) ? uploadStates[index] : .idle,
                    accentColor: accentColor,
                    showRemoveButton: canRemove,
                    remove: { removeMedia(index) }
                )
            }
        }
    }
}

private struct MediaThumbnail: View {
    let preview: ShareMediaPreview
    let uploadState: ShareMediaUploadState
    let accentColor: Color
    let showRemoveButton: Bool
    let remove: () -> Void

    var body: some View {
        GeometryReader { proxy in
            thumbnailContent
                .frame(width: proxy.size.width, height: proxy.size.width / preview.aspectRatio)
                .background(Color(.secondarySystemBackground))
                .clipped()
                .contentShape(Rectangle())
                .overlay {
                    if uploadState.hasFailed {
                        ZStack {
                            Color.red.opacity(0.35)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .overlay {
                    if preview.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Circle().fill(.black.opacity(0.45)))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showRemoveButton {
                        Button(action: remove) {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.black)
                                .background(Circle().foregroundStyle(.white))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .padding(5)
                    } else if uploadState.mirrorFailed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Color.orange)
                            .clipShape(Circle())
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let uploadProgress = uploadState.progress {
                        UploadProgressBar(progress: uploadProgress, accentColor: accentColor, failed: uploadState.hasFailed)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                    }
                }
        }
        .aspectRatio(preview.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if preview.isGIF {
            AnimatedGIFPreview(data: preview.data)
        } else {
            Image(uiImage: preview.fallbackImage)
                .resizable()
                .scaledToFit()
        }
    }
}

private struct AnimatedGIFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.image = Self.animatedImage(from: data)
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        imageView.image = Self.animatedImage(from: data)
    }

    private static func animatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else { return UIImage(data: data) }

        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDuration(at: index, source: source)
        }

        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func frameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
        let fallbackDuration = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return fallbackDuration
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let clampedDelay = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval
        let duration = unclampedDelay ?? clampedDelay ?? fallbackDuration
        return duration < 0.02 ? fallbackDuration : duration
    }
}

private struct UploadProgressBar: View {
    let progress: Double
    let accentColor: Color
    var failed = false

    private var visibleProgress: Double {
        min(max(progress, 0.05), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.35))
                Capsule()
                    .fill(failed ? Color.red : accentColor)
                    .frame(width: proxy.size.width * visibleProgress)
                    .animation(.easeOut(duration: 0.18), value: visibleProgress)
            }
        }
        .frame(height: 4)
        .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
    }
}

private struct LinkPreview: View {
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(url.host(percentEncoded: false) ?? "Link")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(url.absoluteString)
                .font(.callout)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MessageBar: View {
    let text: String
    let color: Color
    let backgroundColor: Color

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(backgroundColor)
    }
}

private struct ShareRelayPublisher {
    private let fallbackRelays = [
        URL(string: "wss://relay.damus.io")!,
        URL(string: "wss://nos.lol")!,
        URL(string: "wss://nostr.wine")!
    ]

    private var relays: [URL] {
        let sharedRelayStrings = UserDefaults(suiteName: "group.com.nostur.Share")?
            .array(forKey: "write_relay_list") as? [String] ?? []
        let sharedRelays = sharedRelayStrings.compactMap(URL.init(string:))
        return sharedRelays.isEmpty ? fallbackRelays : sharedRelays
    }

    func publish(event: Event) async throws -> [URL] {
        guard let message = ClientMessage(type: .EVENT, event: event).json() else {
            throw ShareExtensionError.couldNotEncodeEvent
        }

        let results = await withTaskGroup(of: URL?.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        try await publish(message: message, to: relay)
                        return relay
                    } catch {
                        return nil
                    }
                }
            }

            var published: [URL] = []
            for await relay in group {
                if let relay {
                    published.append(relay)
                }
            }
            return published
        }

        guard !results.isEmpty else {
            throw ShareExtensionError.noRelayAcceptedEvent
        }

        return results
    }

    private func publish(message: String, to relay: URL) async throws {
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: relay)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        try await withSendTimeout(seconds: 4, task: task, message: message)
    }

    private func withSendTimeout(seconds: TimeInterval, task: URLSessionWebSocketTask, message: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await task.send(.string(message))
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                task.cancel(with: .goingAway, reason: nil)
                throw ShareExtensionError.relayTimeout
            }

            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}

private enum ShareExtensionError: LocalizedError {
    case cancelled
    case privateKeyUnavailable(OSStatus)
    case invalidPrivateKey
    case couldNotEncodeEvent
    case noBlossomServer
    case blossomUnsupported
    case blossomUnauthorized
    case blossomUploadFailed
    case blossomUploadTimeout
    case blossomMirrorFailed
    case noRelayAcceptedEvent
    case relayTimeout
    case remoteSignerUnavailable
    case remoteSignerRelayUnavailable
    case remoteSignerPubkeyUnavailable
    case remoteSignerEncryptionFailed
    case remoteSignerInvalidResponse
    case remoteSignerRejected(String)
    case remoteSignerTimeout

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Share cancelled."
        case .privateKeyUnavailable(let status):
            return "No local private key is available for the active account. Keychain status: \(status)."
        case .invalidPrivateKey:
            return "The active account private key could not be read."
        case .couldNotEncodeEvent:
            return "Could not encode the Nostr event."
        case .noBlossomServer:
            return "Configure a Blossom server in Nostur settings before sharing media."
        case .blossomUnsupported:
            return "The configured Blossom server does not support uploads."
        case .blossomUnauthorized:
            return "The Blossom server rejected the upload authorization."
        case .blossomUploadFailed:
            return "Media upload failed."
        case .blossomUploadTimeout:
            return "Media upload did not make progress and timed out."
        case .blossomMirrorFailed:
            return "Media mirror failed."
        case .noRelayAcceptedEvent:
            return "No relay accepted the post."
        case .relayTimeout:
            return "Relay timed out."
        case .remoteSignerUnavailable:
            return "Remote signer details are unavailable. Open Nostur once, then try sharing again."
        case .remoteSignerRelayUnavailable:
            return "Remote signer relay is unavailable. Open the remote signer account in Nostur, then try sharing again."
        case .remoteSignerPubkeyUnavailable:
            return "Remote signer public key is unavailable. Open the remote signer account in Nostur, then try sharing again."
        case .remoteSignerEncryptionFailed:
            return "Could not encrypt the remote signing request."
        case .remoteSignerInvalidResponse:
            return "The remote signer returned an invalid response."
        case .remoteSignerRejected(let message):
            return "Remote signer rejected the request: \(message)"
        case .remoteSignerTimeout:
            return "Remote signer timed out."
        }
    }
}

private extension NSItemProvider {
    func registeredTypeIdentifier(conformingTo type: UTType) -> String? {
        registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: type) == true
        }
    }

    func loadString() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            loadObject(ofClass: NSString.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let string = object as? String {
                    continuation.resume(returning: string)
                } else if let string = object as? NSString {
                    continuation.resume(returning: string as String)
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    func loadURL() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadObject(ofClass: NSURL.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = object as? URL {
                    continuation.resume(returning: url)
                } else if let url = object as? NSURL {
                    continuation.resume(returning: url as URL)
                } else {
                    continuation.resume(throwing: ShareExtensionError.couldNotEncodeEvent)
                }
            }
        }
    }

    func loadData(typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ShareExtensionError.invalidPrivateKey)
                }
            }
        }
    }

    func loadFileData(typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { fileURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let fileURL, let data = try? Data(contentsOf: fileURL) {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ShareExtensionError.invalidPrivateKey)
                }
            }
        }
    }
}
