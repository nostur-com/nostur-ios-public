//
//  ShareViewController.swift
//  Share with Nostur
//
//  Created by Fabian Lachman on 13/07/2026.
//

import AVFoundation
import Combine
import CryptoKit
import ImageIO
import NostrEssentials
import Security
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@objc(ShareViewController)
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

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        model.reducePreviewMemory()
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

private enum ShareDebugLog {
    static func mark(_ message: String) {
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(message)"
        NSLog("[ShareWithNostur] %@", entry)
        let defaults = UserDefaults(suiteName: "group.com.nostur.Share")
        defaults?.set(entry, forKey: "share_debug_last_step")
        defaults?.synchronize()
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
    @Published var mediaViewModels: [ShareMediaViewModel] = []
//    @Published var mediaCount = 0
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
    /// In-flight upload tasks keyed by `ShareMediaViewModel.id`.
    private var mediaItemUploadTasks: [UUID: Task<ShareMediaMetadata, Error>] = [:]
    /// Completed upload metadata keyed by `ShareMediaViewModel.id`.
    private var uploadedMediaById: [UUID: ShareMediaMetadata] = [:]
    private var mediaUploadPubkey: String?
    /// Bumped only for full-batch invalidation (account switch, reload).
    private var mediaUploadGeneration = 0
    /// Starts at 2; drops to 1 under memory pressure.
    private var maxConcurrentMediaTasks = 2
    /// When true, avoid decoding non-essential images (avatars, large previews).
    @Published private(set) var memoryPressureActive = false
    private var activeAccountIsRemoteSigner = false
    private var activeAccountNip46Relay = ""
    private var activeAccountRemoteSignerPubkey = ""
    /// Write relays for the selected account (source of truth for publish).
    private var writeRelayStrings: [String] = []
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
        // Only append real web links — never file:/// paths from local media shares (macOS Preview/Catalyst).
        if let sharedURL, Self.isShareableWebURL(sharedURL) {
            let urlString = sharedURL.absoluteString
            if !trimmedText.contains(urlString) {
                parts.append(urlString)
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Remote http(s) links only. Local `file://` URLs from Preview/Photos must not become post text.
    fileprivate static func isShareableWebURL(_ url: URL) -> Bool {
        guard !url.isFileURL else { return false }
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func load(extensionContext: NSExtensionContext?) async {
        ShareDebugLog.mark("load start")
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        text = ""
        sharedURL = nil
//        mediaPreviews = []
//        mediaUploadStates = []
//        mediaCount = 0
        activeAccountPictureImage = nil
        memoryPressureActive = false
        maxConcurrentMediaTasks = 2
        cancelMediaUpload(resetStates: true)
        mediaItems = []
        mediaViewModels = []
        
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
            ShareDebugLog.mark("load attachments count=\(attachments.count)")

            try await loadAttachments(attachments)
            ShareDebugLog.mark("load attachments complete media=\(mediaItems.count)")

            if activePubkey.isEmpty {
                errorMessage = "Open Nostur and select an account first."
            } else if !mediaItems.isEmpty && blossomServerStrings.isEmpty {
                errorMessage = "Configure a Blossom server in Nostur settings before sharing media."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        ShareDebugLog.mark("load complete schedule upload")
        scheduleMediaUploadStart()
    }

    func selectAccount(_ account: ShareAccount, persistSelection: Bool = true) {
        let accountChanged = activePubkey != account.pubkey

        activePubkey = account.pubkey
        activeAccountName = account.name
        activeAccountPictureURL = account.remotePictureURL
        activeAccountPictureImage = memoryPressureActive ? nil : account.cachedPictureImage
        activeAccountIsRemoteSigner = account.isRemoteSigner
        activeAccountNip46Relay = account.nip46Relay
        activeAccountRemoteSignerPubkey = account.remoteSignerPubkey
        // Always track this account's relays in-memory (even when not persisting).
        // Prefer the live write_relay_list mirrored by the main app for the active account;
        // fall back to the snapshot embedded in share_accounts (can be stale).
        let liveWriteRelays = sharedDefaults?.array(forKey: "write_relay_list") as? [String] ?? []
        let activeSharedPubkey = (sharedDefaults?.string(forKey: "activeAccountPublicKey") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if account.pubkey == activeSharedPubkey, !liveWriteRelays.isEmpty {
            writeRelayStrings = liveWriteRelays
        } else if !account.writeRelays.isEmpty {
            writeRelayStrings = account.writeRelays
        } else {
            writeRelayStrings = liveWriteRelays
        }
        ShareDebugLog.mark("selectAccount \(account.pubkey.prefix(8)) writeRelays=\(writeRelayStrings.count) fromAccount=\(account.writeRelays.count) live=\(liveWriteRelays.count)")

        if persistSelection, accountChanged {
            cancelMediaUpload(resetStates: true)
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
        // Only overwrite write_relay_list when we have a non-empty list for this account.
        // Prefer live list if this is the main-app active account; otherwise account snapshot.
        let relaysToPersist = !writeRelayStrings.isEmpty ? writeRelayStrings : account.writeRelays
        if !relaysToPersist.isEmpty {
            sharedDefaults?.set(relaysToPersist, forKey: "write_relay_list")
        }
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
        writeRelayStrings = sharedDefaults?.array(forKey: "write_relay_list") as? [String] ?? []
        ShareDebugLog.mark("loadActiveAccountFromDefaults writeRelays=\(writeRelayStrings.count) \(writeRelayStrings)")

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

    func removeMedia(_ item: ShareMediaViewModel) {
        guard !isPosting else { return }

        // Drop from model first so late progress/failure callbacks for this id are ignored.
        mediaItems.removeAll { $0.fileURL == item.fileURL }
        mediaViewModels.removeAll { $0.id == item.id }
        uploadedMediaById[item.id] = nil

        // Cancel only this item's work; leave others running (do not bump generation).
        mediaItemUploadTasks[item.id]?.cancel()
        mediaItemUploadTasks[item.id] = nil

        if mediaItems.isEmpty {
            mediaUploadPubkey = nil
            statusMessage = nil
            errorMessage = nil
            return
        }

        // Free a concurrency slot for any still-pending items without restarting in-flight ones.
        startMediaUploadIfPossible()
        refreshUploadStatusMessage()
    }
    
    func reducePreviewMemory() {
        memoryPressureActive = true
        maxConcurrentMediaTasks = 1
        // Drop non-essential decoded avatar; AsyncImage/placeholder can refill if needed.
        activeAccountPictureImage = nil

        guard !mediaViewModels.isEmpty else {
            ShareDebugLog.mark("memory warning reduced concurrency=1 previews=0")
            return
        }
        ShareDebugLog.mark("memory warning reduce previews count=\(mediaViewModels.count) concurrency=1")

        let maxPixelSize = 160
        mediaViewModels = mediaViewModels.map { vm in
            let thumbnail: UIImage
            if vm.isVideo {
                thumbnail = ShareVideoThumbnailGenerator.thumbnail(from: vm.fileURL, maxPixelSize: maxPixelSize)
            } else {
                thumbnail = ShareImageThumbnailGenerator.thumbnail(from: vm.fileURL, maxPixelSize: maxPixelSize)
            }
            let newPreview = ShareMediaPreview(
                fileURL: vm.fileURL,
                contentType: vm.contentType,
                fallbackImage: thumbnail
            )
            return ShareMediaViewModel(
                id: vm.id,
                preview: newPreview,
                uploadState: vm.uploadState,
                containsLocationMetadata: vm.containsLocationMetadata
            )
        }
    }

    func retryMediaUpload(_ item: ShareMediaViewModel) {
        guard !isPosting else { return }
        
        errorMessage = nil
        statusMessage = nil

        mediaItemUploadTasks[item.id]?.cancel()
        mediaItemUploadTasks[item.id] = nil
        uploadedMediaById[item.id] = nil

        if let index = indexOfViewModel(with: item.id) {
            mediaViewModels[index].uploadState = .idle
        }

        startMediaUploadIfPossible()
    }
    
    private func indexOfViewModel(with id: UUID) -> Int? {
        mediaViewModels.firstIndex { $0.id == id }
    }

    private func scheduleMediaUploadStart() {
        ShareDebugLog.mark("upload scheduled")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            ShareDebugLog.mark("upload schedule fired")
            startMediaUploadIfPossible()
        }
    }

    private func startMediaUploadIfPossible() {
        ShareDebugLog.mark("upload start requested media=\(mediaItems.count) inFlight=\(mediaItemUploadTasks.count) done=\(uploadedMediaById.count)")
        guard !mediaItems.isEmpty, !activePubkey.isEmpty, !blossomServerStrings.isEmpty else {
            ShareDebugLog.mark("upload start skipped missing requirements media=\(mediaItems.count) active=\(!activePubkey.isEmpty) blossom=\(!blossomServerStrings.isEmpty)")
            return
        }

        do {
            ShareDebugLog.mark("upload load signer start")
            let signer = try loadSigner()
            ShareDebugLog.mark("upload load signer complete remote=\(signer.needsRemoteApproval)")
            mediaUploadPubkey = signer.publicKey
            pumpMediaUploads(signer: signer, generation: mediaUploadGeneration)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Starts uploads only for items that still need them (not completed, not failed, not already in flight).
    private func pumpMediaUploads(signer: ShareEventSigner, generation: Int) {
        guard generation == mediaUploadGeneration else { return }

        var slots = max(0, maxConcurrentMediaTasks - mediaItemUploadTasks.count)
        guard slots > 0 else {
            refreshUploadStatusMessage(signer: signer)
            return
        }

        for (viewModel, mediaItem) in zip(mediaViewModels, mediaItems) {
            guard slots > 0 else { break }
            let id = viewModel.id
            if uploadedMediaById[id] != nil { continue }
            if mediaItemUploadTasks[id] != nil { continue }
            if case .failed = viewModel.uploadState { continue }

            startSingleMediaUpload(id: id, mediaItem: mediaItem, signer: signer, generation: generation)
            slots -= 1
        }

        refreshUploadStatusMessage(signer: signer)
    }

    private func startSingleMediaUpload(id: UUID, mediaItem: SharedMediaItem, signer: ShareEventSigner, generation: Int) {
        ShareDebugLog.mark("media \(id) enqueue bytes=\(mediaItem.byteCount) type=\(mediaItem.contentType)")

        // Only zero progress when starting from idle so we never visually reset an in-flight bar.
        if case .idle = mediaViewModels.first(where: { $0.id == id })?.uploadState {
            setUploadProgress(0, forMediaWithId: id, uploadGeneration: generation)
        }

        mediaItemUploadTasks[id] = Task { [weak self] in
            guard let self else { throw CancellationError() }
            do {
                let imeta = try await self.uploadSingleMedia(
                    mediaItem: mediaItem,
                    signer: signer,
                    id: id,
                    generation: generation
                )
                try Task.checkCancellation()
                self.handleSingleMediaUploadSuccess(id: id, imeta: imeta, signer: signer, generation: generation)
                return imeta
            } catch is CancellationError {
                ShareDebugLog.mark("media \(id) cancelled")
                if self.mediaUploadGeneration == generation {
                    self.mediaItemUploadTasks[id] = nil
                }
                throw CancellationError()
            } catch {
                ShareDebugLog.mark("media \(id) task error \(error.localizedDescription)")
                self.handleSingleMediaUploadFailure(id: id, error: error, signer: signer, generation: generation)
                throw error
            }
        }
    }

    private func handleSingleMediaUploadSuccess(id: UUID, imeta: ShareMediaMetadata, signer: ShareEventSigner, generation: Int) {
        guard mediaUploadGeneration == generation else { return }
        mediaItemUploadTasks[id] = nil
        // Item may have been removed while finishing — still free the concurrency slot.
        guard mediaViewModels.contains(where: { $0.id == id }) else {
            pumpMediaUploads(signer: signer, generation: generation)
            return
        }
        uploadedMediaById[id] = imeta
        pumpMediaUploads(signer: signer, generation: generation)
        refreshUploadStatusMessage(signer: signer)
    }

    private func handleSingleMediaUploadFailure(id: UUID, error: Error, signer: ShareEventSigner, generation: Int) {
        guard mediaUploadGeneration == generation else { return }
        mediaItemUploadTasks[id] = nil
        guard mediaViewModels.contains(where: { $0.id == id }) else {
            pumpMediaUploads(signer: signer, generation: generation)
            return
        }
        setUploadFailed(forMediaWithId: id, uploadGeneration: generation)
        errorMessage = error.localizedDescription
        statusMessage = nil
        // Keep other items moving.
        pumpMediaUploads(signer: signer, generation: generation)
    }

    private func refreshUploadStatusMessage(signer: ShareEventSigner? = nil) {
        guard !mediaViewModels.isEmpty else {
            if !isPosting {
                statusMessage = nil
            }
            return
        }

        let completedCount = mediaViewModels.filter { uploadedMediaById[$0.id] != nil }.count
        let total = mediaViewModels.count
        let hasInFlight = mediaViewModels.contains { mediaItemUploadTasks[$0.id] != nil }

        if completedCount == total {
            if !isPosting {
                statusMessage = "Media uploaded."
            }
            return
        }

        guard hasInFlight || completedCount < total else { return }

        if let signer, signer.needsRemoteApproval, hasInFlight {
            statusMessage = "Waiting for remote signer..."
            return
        }

        let mirrorCount = max(0, blossomServerStrings.count - 1)
        if hasInFlight {
            if total == 1 {
                statusMessage = mirrorCount > 0 ? "Uploading and mirroring media..." : "Uploading media..."
            } else {
                statusMessage = mirrorCount > 0
                    ? "Uploading and mirroring media (\(completedCount)/\(total))..."
                    : "Uploading \(total) media items (\(completedCount)/\(total))..."
            }
        }
    }

    /// Full cancel — account switch, reload, or other hard resets. Does not apply to single-item remove.
    private func cancelMediaUpload(resetStates: Bool = false) {
        mediaUploadGeneration += 1
        for task in mediaItemUploadTasks.values {
            task.cancel()
        }
        mediaItemUploadTasks.removeAll()
        mediaUploadPubkey = nil
        uploadedMediaById.removeAll()
        
        if resetStates {
            resetMediaUploadStates()
        }
    }

    private func resetMediaUploadStates() {
        for i in mediaViewModels.indices {
            mediaViewModels[i].uploadState = .idle
        }
    }

    private func mediaMetadataForPosting(signer: ShareEventSigner) async throws -> [ShareMediaMetadata] {
        guard !mediaItems.isEmpty else { return [] }

        if mediaUploadPubkey != signer.publicKey {
            cancelMediaUpload(resetStates: true)
        }

        // Retry any previously failed items when the user posts.
        for index in mediaViewModels.indices {
            if case .failed = mediaViewModels[index].uploadState {
                mediaViewModels[index].uploadState = .idle
                uploadedMediaById[mediaViewModels[index].id] = nil
                mediaItemUploadTasks[mediaViewModels[index].id]?.cancel()
                mediaItemUploadTasks[mediaViewModels[index].id] = nil
            }
        }

        if mediaViewModels.allSatisfy({ uploadedMediaById[$0.id] != nil }), mediaUploadPubkey == signer.publicKey {
            return mediaViewModels.compactMap { uploadedMediaById[$0.id] }
        }

        startMediaUploadIfPossible()

        var results: [ShareMediaMetadata] = []
        results.reserveCapacity(mediaViewModels.count)

        for viewModel in mediaViewModels {
            let id = viewModel.id
            if let imeta = uploadedMediaById[id] {
                results.append(imeta)
                continue
            }

            if let task = mediaItemUploadTasks[id] {
                results.append(try await task.value)
                continue
            }

            // Race: task finished between map clear and this check.
            if let imeta = uploadedMediaById[id] {
                results.append(imeta)
                continue
            }

            // Still missing — kick the queue once more and wait.
            startMediaUploadIfPossible()
            if let task = mediaItemUploadTasks[id] {
                results.append(try await task.value)
            } else if let imeta = uploadedMediaById[id] {
                results.append(imeta)
            } else {
                throw ShareExtensionError.couldNotPrepareMedia
            }
        }

        return results
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

            let publishStartedAt = Date()
            // Re-read mirrored list at publish time so we pick up main-app relay edits
            // made after the share sheet opened (or after a previous share session).
            let activeSharedPubkey = (sharedDefaults?.string(forKey: "activeAccountPublicKey") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if activePubkey == activeSharedPubkey,
               let liveWriteRelays = sharedDefaults?.array(forKey: "write_relay_list") as? [String],
               !liveWriteRelays.isEmpty {
                writeRelayStrings = liveWriteRelays
            }
            // Prefer selected account relays; fall back to shared defaults / built-in list.
            let relayURLs = ShareRelayPublisher.resolveRelayURLs(
                preferred: writeRelayStrings,
                sharedDefaults: sharedDefaults
            )
            ShareDebugLog.mark("publish relays total=\(relayURLs.count) preferred=\(writeRelayStrings.count) urls=\(relayURLs.map(\.absoluteString))")
            let publisher = ShareRelayPublisher(relays: relayURLs)
            let totalRelays = relayURLs.count
            statusMessage = totalRelays == 1
                ? "Publishing to 0/1 relay..."
                : "Publishing to 0/\(totalRelays) relays..."

            let publishedRelays = try await publisher.publish(event: signedEvent) { [weak self] succeeded, total in
                guard let self else { return }
                self.statusMessage = total == 1
                    ? "Publishing to \(succeeded)/1 relay..."
                    : "Publishing to \(succeeded)/\(total) relays..."
            }

            let succeeded = publishedRelays.count
            statusMessage = totalRelays == 1
                ? "Publishing to \(succeeded)/1 relay..."
                : "Publishing to \(succeeded)/\(totalRelays) relays..."

            // Hold the sheet so the user can see the final count before dismiss.
            if succeeded == totalRelays {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } else {
                let elapsed = Date().timeIntervalSince(publishStartedAt)
                let remaining = max(0, 8 - elapsed)
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }

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
        let previewMaxPixelSize = SharePreviewSizing.maxPixelSize(forMediaCount: mediaProviderCount(in: providers))

        for provider in providers {
            // Prefer media over URL: on macOS/Catalyst (e.g. Preview), image providers also
            // conform to public.url with a file:/// path. Treating URL first used to skip media
            // and append the local path as a link in the post.
            if let typeIdentifier = provider.registeredTypeIdentifier(conformingTo: .movie) {
                let fileURL = try await provider.loadPersistentFile(typeIdentifier: typeIdentifier)
                let contentType = UTType(typeIdentifier)?.preferredMIMEType ?? "video/quicktime"
                let preview = ShareVideoThumbnailGenerator.thumbnail(from: fileURL, maxPixelSize: previewMaxPixelSize)
                let containsLocation = await ShareVideoLocationMetadataDetector.containsLocationMetadata(at: fileURL)
                ShareDebugLog.mark(
                    "video location check \(fileURL.lastPathComponent) result=\(containsLocation)"
                )

                let mediaItem = SharedMediaItem(fileURL: fileURL, contentType: contentType, byteCount: fileURL.fileSize)
                let viewModel = ShareMediaViewModel(
                    preview: ShareMediaPreview(fileURL: fileURL, contentType: contentType, fallbackImage: preview),
                    containsLocationMetadata: containsLocation
                )
                
                mediaItems.append(mediaItem)
                mediaViewModels.append(viewModel)
            } else if let typeIdentifier = provider.registeredTypeIdentifier(conformingTo: .image) {
                let fileURL = try await provider.loadPersistentFile(typeIdentifier: typeIdentifier)
                let contentType = UTType(typeIdentifier)?.preferredMIMEType ?? "image/jpeg"
                let preview = ShareImageThumbnailGenerator.thumbnail(from: fileURL, maxPixelSize: previewMaxPixelSize)
                
                let mediaItem = SharedMediaItem(fileURL: fileURL, contentType: contentType, byteCount: fileURL.fileSize)
                let viewModel = ShareMediaViewModel(preview: ShareMediaPreview(fileURL: fileURL, contentType: contentType, fallbackImage: preview))
                
                mediaItems.append(mediaItem)
                mediaViewModels.append(viewModel)
            } else if provider.canLoadObject(ofClass: NSString.self), text.isEmpty {
                text = try await provider.loadString()
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), sharedURL == nil {
                let url = try await provider.loadURL()
                if Self.isShareableWebURL(url) {
                    sharedURL = url
                } else {
                    ShareDebugLog.mark("ignore non-web shared URL \(url.absoluteString)")
                }
            }
        }
    }

    private func mediaProviderCount(in providers: [NSItemProvider]) -> Int {
        providers.reduce(0) { count, provider in
            if provider.registeredTypeIdentifier(conformingTo: .movie) != nil || provider.registeredTypeIdentifier(conformingTo: .image) != nil {
                return count + 1
            }
            return count
        }
    }

    private func uploadSingleMedia(
        mediaItem: SharedMediaItem,
        signer: ShareEventSigner,
        id: UUID,
        generation: Int
    ) async throws -> ShareMediaMetadata {
        ShareDebugLog.mark("media \(id) task start bytes=\(mediaItem.byteCount) type=\(mediaItem.contentType)")

        let blossomServers = blossomServerStrings.compactMap(URL.init(string:))
        guard let server = blossomServers.first else {
            throw ShareExtensionError.noBlossomServer
        }
        let mirrorServers = Array(blossomServers.dropFirst())

        let uploader = ShareBlossomUploader(server: server)
        let progressSink = ShareUploadProgressSink(model: self, uploadGeneration: generation)

        try Task.checkCancellation()

        let imeta = try await uploader.upload(mediaItem: mediaItem, signer: signer) { progress in
            let uploadProgress = mirrorServers.isEmpty ? progress : progress * 0.9
            progressSink.set(uploadProgress, forMediaWithId: id)
        }

        try Task.checkCancellation()
        ShareDebugLog.mark("media \(id) upload complete")

        if mirrorServers.isEmpty {
            progressSink.set(1, forMediaWithId: id)
        } else {
            progressSink.set(0.9, forMediaWithId: id)
            let mirrorSucceeded = await ShareBlossomMirrorer(servers: mirrorServers).mirror(imeta: imeta, signer: signer) { progress in
                progressSink.set(0.9 + (progress * 0.1), forMediaWithId: id)
            }
            try Task.checkCancellation()
            progressSink.set(1, forMediaWithId: id, mirrorFailed: !mirrorSucceeded)
        }

        return imeta
    }

    fileprivate func setUploadProgress(_ progress: Double, forMediaWithId id: UUID, uploadGeneration: Int, mirrorFailed: Bool = false) {
        guard self.mediaUploadGeneration == uploadGeneration else { return }
        guard let index = indexOfViewModel(with: id) else { return }
        mediaViewModels[index].uploadState = .progress(min(max(progress, 0), 1), mirrorFailed: mirrorFailed)
    }

    fileprivate func setUploadFailed(forMediaWithId id: UUID, uploadGeneration: Int) {
        guard self.mediaUploadGeneration == uploadGeneration else { return }
        guard let index = indexOfViewModel(with: id) else { return }
        mediaViewModels[index].uploadState = .failed
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
            if let blurhash = imeta.blurhash, !blurhash.isEmpty {
                parts.append("blurhash \(blurhash)")
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
    private let uploadGeneration: Int

    init(model: ShareExtensionModel, uploadGeneration: Int) {
        self.model = model
        self.uploadGeneration = uploadGeneration
    }

    func set(_ progress: Double, forMediaWithId id: UUID, mirrorFailed: Bool = false) {
        Task { @MainActor in
            model?.setUploadProgress(progress, forMediaWithId: id, uploadGeneration: uploadGeneration, mirrorFailed: mirrorFailed)
        }
    }

    func fail(forMediaWithId id: UUID) {
        Task { @MainActor in
            model?.setUploadFailed(forMediaWithId: id, uploadGeneration: uploadGeneration)
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

    var displayProgress: Double? {
        switch self {
        case .idle:
            return 0.02
        case .progress(let progress, _):
            return progress
        case .failed:
            return nil
        }
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
    let fileURL: URL
    let contentType: String
    let byteCount: Int
}

private enum SharePreviewSizing {
    static func maxPixelSize(forMediaCount count: Int) -> Int {
        switch count {
        case 0...1:
            return 900
        case 2...4:
            return 640
        default:
            return 384
        }
    }
}

private struct ShareMediaPreview: Equatable {
    let fileURL: URL
    let contentType: String
    let fallbackImage: UIImage

    var isGIF: Bool {
        contentType.lowercased() == "image/gif"
    }

    var isVideo: Bool {
        contentType.lowercased().hasPrefix("video/")
    }

    var aspectRatio: CGFloat {
        guard fallbackImage.size.height > 0 else { return 1 }
        return fallbackImage.size.width / fallbackImage.size.height
    }
}

private enum ShareImageThumbnailGenerator {
    private static let resizeLock = NSLock()

    static func thumbnail(from fileURL: URL, maxPixelSize: Int = 512) -> UIImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return placeholder()
        }
        return UIImage(cgImage: cgImage)
    }

    static func resizedJPEGFile(from fileURL: URL, maxPixelSize: Int) throws -> (fileURL: URL, byteCount: Int, dim: String) {
        resizeLock.lock()
        defer { resizeLock.unlock() }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ShareExtensionError.couldNotPrepareMedia
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareWithNosturPreparedMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let destinationURL = directoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ShareExtensionError.couldNotPrepareMedia
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ShareExtensionError.couldNotPrepareMedia
        }

        return (destinationURL, destinationURL.fileSize, "\(cgImage.width)x\(cgImage.height)")
    }

    static func blurhash(from fileURL: URL) -> String? {
        resizeLock.lock()
        defer { resizeLock.unlock() }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return ShareBlurHashEncoder.encode(cgImage: cgImage, components: (4, 3))
    }

    private static func placeholder() -> UIImage {
        let size = CGSize(width: 512, height: 288)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private enum ShareBlurHashEncoder {
    private static let encodeCharacters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

    static func encode(cgImage: CGImage, components: (Int, Int)) -> String? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0,
              components.0 >= 1, components.0 <= 9,
              components.1 >= 1, components.1 <= 9,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var factors: [(Float, Float, Float)] = []
        for y in 0..<components.1 {
            for x in 0..<components.0 {
                let normalisation: Float = (x == 0 && y == 0) ? 1 : 2
                let factor = multiplyBasisFunction(pixels: pixels, width: width, height: height, bytesPerRow: context.bytesPerRow) {
                    normalisation * cos(Float.pi * Float(x) * $0 / Float(width)) * cos(Float.pi * Float(y) * $1 / Float(height))
                }
                factors.append(factor)
            }
        }

        guard let dc = factors.first else { return nil }
        let ac = factors.dropFirst()
        var hash = ""

        let sizeFlag = (components.0 - 1) + (components.1 - 1) * 9
        hash += encode83(sizeFlag, length: 1)

        let maximumValue: Float
        if !ac.isEmpty {
            let actualMaximumValue = ac.map { max(abs($0.0), abs($0.1), abs($0.2)) }.max() ?? 0
            let quantisedMaximumValue = Int(max(0, min(82, floor(actualMaximumValue * 166 - 0.5))))
            maximumValue = Float(quantisedMaximumValue + 1) / 166
            hash += encode83(quantisedMaximumValue, length: 1)
        } else {
            maximumValue = 1
            hash += encode83(0, length: 1)
        }

        hash += encode83(encodeDC(dc), length: 4)
        for factor in ac {
            hash += encode83(encodeAC(factor, maximumValue: maximumValue), length: 2)
        }

        return hash
    }

    private static func multiplyBasisFunction(
        pixels: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        basisFunction: (Float, Float) -> Float
    ) -> (Float, Float, Float) {
        var red: Float = 0
        var green: Float = 0
        var blue: Float = 0
        let buffer = UnsafeBufferPointer(start: pixels, count: height * bytesPerRow)

        for x in 0..<width {
            for y in 0..<height {
                let basis = basisFunction(Float(x), Float(y))
                let offset = x * 4 + y * bytesPerRow
                red += basis * sRGBToLinear(buffer[offset])
                green += basis * sRGBToLinear(buffer[offset + 1])
                blue += basis * sRGBToLinear(buffer[offset + 2])
            }
        }

        let scale = 1 / Float(width * height)
        return (red * scale, green * scale, blue * scale)
    }

    private static func encodeDC(_ value: (Float, Float, Float)) -> Int {
        (linearTosRGB(value.0) << 16) + (linearTosRGB(value.1) << 8) + linearTosRGB(value.2)
    }

    private static func encodeAC(_ value: (Float, Float, Float), maximumValue: Float) -> Int {
        let quantR = Int(max(0, min(18, floor(signPow(value.0 / maximumValue, 0.5) * 9 + 9.5))))
        let quantG = Int(max(0, min(18, floor(signPow(value.1 / maximumValue, 0.5) * 9 + 9.5))))
        let quantB = Int(max(0, min(18, floor(signPow(value.2 / maximumValue, 0.5) * 9 + 9.5))))
        return quantR * 19 * 19 + quantG * 19 + quantB
    }

    private static func signPow(_ value: Float, _ exponent: Float) -> Float {
        copysign(pow(abs(value), exponent), value)
    }

    private static func linearTosRGB(_ value: Float) -> Int {
        let value = max(0, min(1, value))
        if value <= 0.0031308 { return Int(value * 12.92 * 255 + 0.5) }
        return Int((1.055 * pow(value, 1 / 2.4) - 0.055) * 255 + 0.5)
    }

    private static func sRGBToLinear(_ value: UInt8) -> Float {
        let value = Float(value) / 255
        if value <= 0.04045 { return value / 12.92 }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encode83(_ value: Int, length: Int) -> String {
        var result = ""
        for index in 1...length {
            let digit = (value / intPow(83, length - index)) % 83
            result.append(encodeCharacters[digit])
        }
        return result
    }

    private static func intPow(_ base: Int, _ exponent: Int) -> Int {
        (0..<exponent).reduce(1) { value, _ in value * base }
    }
}

private enum ShareVideoThumbnailGenerator {
    static func thumbnail(from fileURL: URL, maxPixelSize: Int = 512) -> UIImage {
        do {
            let asset = AVURLAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return ShareImageThumbnailGenerator.thumbnail(from: fileURL, maxPixelSize: maxPixelSize)
        }
    }
}

/// Lightweight inspection for GPS / location tags. Not a full re-encode.
///
/// Photos may show a place in its UI from library data even when the *shared file*
/// has no location (e.g. share-sheet "Location" option off). We only inspect the
/// bytes that will actually be uploaded.
private enum ShareVideoLocationMetadataDetector {
    private static let iso6709Pattern = try? NSRegularExpression(
        pattern: #"[+-]\d+(?:\.\d+)?[+-]\d+(?:\.\d+)?(?:[+-]\d+(?:\.\d+)?)?/"#
    )

    /// ASCII needles embedded in QuickTime / MP4 location metadata.
    private static let fileSignatureNeedles: [Data] = [
        Data("com.apple.quicktime.location".utf8),
        Data("com.apple.quicktime.location.ISO6709".utf8),
        Data("com.apple.quicktime.location.name".utf8),
        // QuickTime user-data location atom type (©xyz)
        Data([0xA9, 0x78, 0x79, 0x7A]),
        // 3GPP location information box
        Data("loci".utf8)
    ]

    static func containsLocationMetadata(at fileURL: URL) async -> Bool {
        if await assetContainsLocationMetadata(at: fileURL) {
            return true
        }
        // AVFoundation sometimes omits tags that are still present in the container.
        // A bounded byte scan is cheap and catches the common phone-camera keys.
        return fileBytesContainLocationSignature(at: fileURL)
    }

    private static func assetContainsLocationMetadata(at fileURL: URL) async -> Bool {
        let asset = AVURLAsset(url: fileURL)
        let items = await loadAllMetadataItems(from: asset)
        ShareDebugLog.mark("video metadata items=\(items.count) for \(fileURL.lastPathComponent)")

        for item in items {
            if await itemLooksLikeLocation(item) {
                return true
            }
        }
        return false
    }

    private static func loadAllMetadataItems(from asset: AVURLAsset) async -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        do {
            let common = try await asset.load(.commonMetadata)
            items.append(contentsOf: common)

            let metadata = try await asset.load(.metadata)
            items.append(contentsOf: metadata)

            let formats = try await asset.load(.availableMetadataFormats)
            ShareDebugLog.mark("video metadata formats=\(formats.map(\.rawValue).joined(separator: ","))")
            for format in formats {
                let formatItems = try await asset.loadMetadata(for: format)
                items.append(contentsOf: formatItems)
            }
        } catch {
            ShareDebugLog.mark("video metadata load failed: \(error.localizedDescription)")
            // Fallback for older load path if async load throws.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                asset.loadValuesAsynchronously(forKeys: ["commonMetadata", "metadata", "availableMetadataFormats"]) {
                    continuation.resume()
                }
            }
            items.append(contentsOf: asset.commonMetadata)
            items.append(contentsOf: asset.metadata)
            for format in asset.availableMetadataFormats {
                items.append(contentsOf: asset.metadata(forFormat: format))
            }
        }

        return items
    }

    private static func itemLooksLikeLocation(_ item: AVMetadataItem) async -> Bool {
        // Identifier / commonKey / key are usually available without async value loading.
        if item.commonKey == .commonKeyLocation {
            return true
        }

        if let identifier = item.identifier {
            switch identifier {
            case .quickTimeMetadataLocationISO6709,
                 .quickTimeMetadataLocationName,
                 .quickTimeMetadataLocationBody,
                 .quickTimeMetadataLocationNote,
                 .quickTimeMetadataLocationRole,
                 .quickTimeMetadataLocationDate,
                 .quickTimeMetadataLocationHorizontalAccuracyInMeters:
                return true
            default:
                break
            }

            let id = identifier.rawValue.lowercased()
            if id.contains("location") || id.contains("gps") {
                return true
            }
        }

        if let key = item.key, keyIndicatesLocation(key) {
            return true
        }

        // Values often need explicit loading on modern iOS.
        if let stringValue = try? await item.load(.stringValue), stringLooksLikeISO6709(stringValue) {
            return true
        }
        if let stringValue = item.stringValue, stringLooksLikeISO6709(stringValue) {
            return true
        }

        if let dataValue = try? await item.load(.dataValue), dataLooksLikeLocation(dataValue) {
            return true
        }
        if let dataValue = item.dataValue, dataLooksLikeLocation(dataValue) {
            return true
        }

        return false
    }

    private static func keyIndicatesLocation(_ key: any NSCopying & NSObjectProtocol) -> Bool {
        if let string = key as? String {
            let lowered = string.lowercased()
            return lowered.contains("location") || lowered.contains("gps") || string == "©xyz"
        }
        if let string = key as? NSString {
            let lowered = string.lowercased
            return lowered.contains("location") || lowered.contains("gps") || string as String == "©xyz"
        }
        return false
    }

    private static func stringLooksLikeISO6709(_ raw: String) -> Bool {
        let stringValue = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stringValue.isEmpty, let regex = iso6709Pattern else { return false }
        let range = NSRange(stringValue.startIndex..., in: stringValue)
        return regex.firstMatch(in: stringValue, options: [], range: range) != nil
    }

    private static func dataLooksLikeLocation(_ data: Data) -> Bool {
        if let string = String(data: data, encoding: .utf8), stringLooksLikeISO6709(string) {
            return true
        }
        // Short binary blobs are not treated as location without a string form.
        return false
    }

    /// Stream the file in chunks looking for known location metadata signatures.
    private static func fileBytesContainLocationSignature(at fileURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }

        let chunkSize = 1024 * 1024
        let maxOverlap = (fileSignatureNeedles.map(\.count).max() ?? 64) - 1
        var carry = Data()

        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: chunkSize) ?? Data()
            } catch {
                break
            }
            if chunk.isEmpty { break }

            var window = carry
            window.append(chunk)
            for needle in fileSignatureNeedles {
                if window.range(of: needle) != nil {
                    ShareDebugLog.mark("video location signature hit in file bytes")
                    return true
                }
            }
            if window.count > maxOverlap {
                carry = window.suffix(maxOverlap)
            } else {
                carry = window
            }
        }
        return false
    }
}

private struct ShareMediaMetadata {
    let url: String
    let dim: String?
    let hash: String?
    let blurhash: String?
}

private enum ShareFileHasher {
    static func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = CryptoKit.SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct PreparedShareMediaItem {
    let fileURL: URL
    let byteCount: Int
    let contentType: String
    let dim: String?
    let blurhash: String?
    let removeAfterUpload: Bool
}

private struct ShareBlossomUploader {
    let server: URL

    func upload(mediaItem: SharedMediaItem, signer: ShareEventSigner, onProgress: @escaping (Double) -> Void) async throws -> ShareMediaMetadata {
        ShareDebugLog.mark("blossom prepare start bytes=\(mediaItem.byteCount) type=\(mediaItem.contentType)")
        let prepared = try prepare(mediaItem: mediaItem)
        ShareDebugLog.mark("blossom prepare complete bytes=\(prepared.byteCount) type=\(prepared.contentType)")
        defer {
            if prepared.removeAfterUpload {
                try? FileManager.default.removeItem(at: prepared.fileURL)
            }
        }

        ShareDebugLog.mark("blossom hash start bytes=\(prepared.byteCount)")
        let sha256 = try ShareFileHasher.sha256Hex(for: prepared.fileURL)
        ShareDebugLog.mark("blossom hash complete")
        ShareDebugLog.mark("blossom auth start")
        let authHeader = try await signer.blossomAuthorizationHeader(sha256hex: sha256)
        ShareDebugLog.mark("blossom auth complete")
        ShareDebugLog.mark("blossom server test start")
        let blossomType = (try? await testBlossomServer(server, authorization: authHeader, sha256: sha256)) ?? .none
        ShareDebugLog.mark("blossom server test complete type=\(blossomType)")

        switch blossomType {
        case .media, .upload:
            break
        case .unauthorized:
            throw ShareExtensionError.blossomUnauthorized
        case .none:
            throw ShareExtensionError.blossomUnsupported
        }

        ShareDebugLog.mark("blossom upload file start bytes=\(prepared.byteCount)")
        let response = try await upload(prepared: prepared, sha256: sha256, authHeader: authHeader, verb: blossomType, onProgress: onProgress)
        ShareDebugLog.mark("blossom upload file complete")
        let responseURL = response.nip94?.first(where: { $0.type == "url" })?.value ?? response.url
        let responseDim = response.nip94?.first(where: { $0.type == "dim" })?.value ?? prepared.dim
        let responseHash = response.nip94?.first(where: { $0.type == "x" })?.value ?? response.sha256

        let responseBlurhash = response.nip94?.first(where: { $0.type == "blurhash" })?.value ?? prepared.blurhash

        return ShareMediaMetadata(url: responseURL, dim: responseDim, hash: responseHash, blurhash: responseBlurhash)
    }

    private func prepare(mediaItem: SharedMediaItem) throws -> PreparedShareMediaItem {
        let contentType = mediaItem.contentType.lowercased()
        if contentType.hasPrefix("image/"), contentType != "image/gif" {
            ShareDebugLog.mark("blossom resize start max=2800")
            let resized = try ShareImageThumbnailGenerator.resizedJPEGFile(from: mediaItem.fileURL, maxPixelSize: 2800)
            ShareDebugLog.mark("blossom resize complete bytes=\(resized.byteCount) dim=\(resized.dim)")
            // Derive blurhash from the already-resized file to avoid decoding the original again.
            let blurhash = ShareImageThumbnailGenerator.blurhash(from: resized.fileURL)
            return PreparedShareMediaItem(
                fileURL: resized.fileURL,
                byteCount: resized.byteCount,
                contentType: "image/jpeg",
                dim: resized.dim,
                blurhash: blurhash,
                removeAfterUpload: true
            )
        }

        let blurhash = contentType.hasPrefix("image/") ? ShareImageThumbnailGenerator.blurhash(from: mediaItem.fileURL) : nil
        return PreparedShareMediaItem(
            fileURL: mediaItem.fileURL,
            byteCount: mediaItem.byteCount,
            contentType: mediaItem.contentType,
            dim: nil,
            blurhash: blurhash,
            removeAfterUpload: false
        )
    }

    private func upload(prepared: PreparedShareMediaItem, sha256: String, authHeader: String, verb: SupportedBlossomType, onProgress: @escaping (Double) -> Void) async throws -> BlossomUploadResponse {
        let endpoint = verb == .upload ? "upload" : "media"
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let progressDelegate = ShareUploadProgressDelegate(totalBytes: prepared.byteCount, onProgress: onProgress)
        let session = URLSession(configuration: config, delegate: progressDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: server.appendingPathComponent(endpoint))
        request.httpMethod = "PUT"
        request.setValue(prepared.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue(sha256, forHTTPHeaderField: "X-SHA-256")

        let (data, response) = try await withUploadStallTimeout(initialGraceSeconds: 90, stallSeconds: 45, session: session, request: request, fileURL: prepared.fileURL, progressDelegate: progressDelegate)
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

    private func withUploadStallTimeout(initialGraceSeconds: TimeInterval, stallSeconds: TimeInterval, session: URLSession, request: URLRequest, fileURL: URL, progressDelegate: ShareUploadProgressDelegate) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                try await session.upload(for: request, fromFile: fileURL)
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
        NavigationView {
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
        .navigationViewStyle(.stack)
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
                loadAccountImages: !model.memoryPressureActive,
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

                if !model.mediaViewModels.isEmpty {
                    ShareMediaPreviews(
                        viewModels: model.mediaViewModels,
                        accentColor: accentColor,
                        canRemove: model.mediaViewModels.count > 1 && !model.isPosting,
                        isPosting: model.isPosting,
                        removeMedia: model.removeMedia,
                        retryMedia: model.retryMediaUpload
                    )
                }

                if model.mediaViewModels.contains(where: { $0.containsLocationMetadata }) {
                    VideoLocationWarningBanner(
                        multiple: model.mediaViewModels.filter(\.containsLocationMetadata).count > 1
                    )
                }

                if let sharedURL = model.sharedURL, ShareExtensionModel.isShareableWebURL(sharedURL) {
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
    /// When false (memory pressure), skip decoding/loading avatar bitmaps.
    var loadAccountImages = true
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
                    AccountAvatar(
                        image: loadAccountImages ? fallbackImage : nil,
                        pictureURL: loadAccountImages ? fallbackPictureURL : nil
                    )
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(sortedAccounts.enumerated()), id: \.element.pubkey) { index, account in
                            AccountAvatar(
                                image: loadAccountImages ? account.cachedPictureImage : nil,
                                pictureURL: loadAccountImages ? account.remotePictureURL : nil
                            )
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
    let viewModels: [ShareMediaViewModel]
    let accentColor: Color
    let canRemove: Bool
    let isPosting: Bool
    let removeMedia: (ShareMediaViewModel) -> Void
    let retryMedia: (ShareMediaViewModel) -> Void

    private var columnCount: Int {
        viewModels.count == 1 ? 1 : min(viewModels.count, 3)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 5), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(viewModels) { vm in
                MediaThumbnail(
                    preview: vm.preview,
                    uploadState: vm.uploadState,
                    accentColor: accentColor,
                    showRemoveButton: canRemove,
                    showMirrorWarning: !isPosting,
                    remove: { removeMedia(vm) },
                    retry: { retryMedia(vm) }
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
    let showMirrorWarning: Bool
    let remove: () -> Void
    let retry: () -> Void

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: preview.fallbackImage)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.width / preview.aspectRatio)
                .background(Color(.secondarySystemBackground))
                .clipped()
                .contentShape(Rectangle())
                .overlay {
                    if uploadState.hasFailed {
                        ZStack {
                            Color.red.opacity(0.35)
                            Button(action: retry) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Retry upload")
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
                .overlay(alignment: .topLeading) {
                    if preview.isGIF {
                        Text("GIF")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .padding(6)
                            .accessibilityLabel("GIF")
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
                    } else if showMirrorWarning, uploadState.mirrorFailed {
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
                    if let uploadProgress = uploadState.displayProgress {
                        UploadProgressBar(progress: uploadProgress, accentColor: accentColor, failed: uploadState.hasFailed)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                    }
                }
        }
        .aspectRatio(preview.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
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

private extension URL {
    var fileSize: Int {
        let size = (try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return max(size, 0)
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

private struct VideoLocationWarningBanner: View {
    let multiple: Bool

    private var message: String {
        if multiple {
            return "These videos include location data. Others may be able to see where they were recorded after you upload."
        }
        return "This video includes location data. Others may be able to see where it was recorded after you upload."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "location.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

private struct ShareRelayPublisher {
    private static let fallbackRelays = [
        URL(string: "wss://relay.damus.io")!,
        URL(string: "wss://nos.lol")!,
        URL(string: "wss://nostr.wine")!
    ]

    let relays: [URL]

    init(relays: [URL]) {
        self.relays = relays
    }

    /// Prefer the selected account's relay strings; fall back to shared defaults, then built-ins.
    static func resolveRelayURLs(preferred: [String], sharedDefaults: UserDefaults?) -> [URL] {
        let preferredURLs = parseRelayURLs(from: preferred)
        if !preferredURLs.isEmpty { return preferredURLs }

        let sharedStrings = sharedDefaults?.array(forKey: "write_relay_list") as? [String] ?? []
        let sharedURLs = parseRelayURLs(from: sharedStrings)
        if !sharedURLs.isEmpty { return sharedURLs }

        return fallbackRelays
    }

    /// Parse relay URL strings, trimming whitespace and dropping invalid / non-wss / duplicates.
    static func parseRelayURLs(from strings: [String]) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []

        for raw in strings {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let withScheme: String
            if trimmed.hasPrefix("wss://") || trimmed.hasPrefix("ws://") {
                withScheme = trimmed
            } else {
                withScheme = "wss://\(trimmed)"
            }

            // Share extension only uses TLS websocket relays (same filter as main app export).
            guard withScheme.hasPrefix("wss://") else {
                ShareDebugLog.mark("skip non-wss relay \(trimmed)")
                continue
            }

            guard let url = URL(string: withScheme), url.host != nil else {
                ShareDebugLog.mark("skip unparseable relay \(trimmed)")
                continue
            }

            // Dedupe by host+path without trailing slash / case.
            let key = withScheme
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard seen.insert(key).inserted else { continue }
            urls.append(url)
        }

        return urls
    }

    /// Publishes to all write relays in parallel. `onProgress` is called on the main actor
    /// after each successful send with `(succeededCount, totalRelays)`.
    func publish(
        event: Event,
        onProgress: @MainActor @escaping (_ succeeded: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> [URL] {
        guard let message = ClientMessage(type: .EVENT, event: event).json() else {
            throw ShareExtensionError.couldNotEncodeEvent
        }

        let relayList = relays
        let total = relayList.count
        guard total > 0 else {
            throw ShareExtensionError.noRelayAcceptedEvent
        }

        let results = await withTaskGroup(of: URL?.self) { group in
            for relay in relayList {
                group.addTask {
                    do {
                        try await self.publish(message: message, to: relay)
                        return relay
                    } catch {
                        ShareDebugLog.mark("relay publish fail \(relay.absoluteString) \(error.localizedDescription)")
                        return nil
                    }
                }
            }

            var published: [URL] = []
            for await relay in group {
                if let relay {
                    published.append(relay)
                    let succeeded = published.count
                    await onProgress(succeeded, total)
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
    case couldNotPrepareMedia
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
        case .couldNotPrepareMedia:
            return "Could not prepare media for upload."
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

    func loadPersistentFile(typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { fileURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let fileURL else {
                    continuation.resume(throwing: ShareExtensionError.invalidPrivateKey)
                    return
                }

                do {
                    let directoryURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ShareWithNosturMedia", isDirectory: true)
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

                    let fileExtension = fileURL.pathExtension.isEmpty
                        ? (UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat")
                        : fileURL.pathExtension
                    let destinationURL = directoryURL
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(fileExtension)

                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}


private struct ShareMediaViewModel: Identifiable {
    let id: UUID
    let preview: ShareMediaPreview
    var uploadState: ShareMediaUploadState
    /// True when file-level GPS/location metadata was detected (videos only today).
    let containsLocationMetadata: Bool

    init(
        id: UUID = UUID(),
        preview: ShareMediaPreview,
        uploadState: ShareMediaUploadState = .idle,
        containsLocationMetadata: Bool = false
    ) {
        self.id = id
        self.preview = preview
        self.uploadState = uploadState
        self.containsLocationMetadata = containsLocationMetadata
    }
    
    var fileURL: URL { preview.fileURL }
    var contentType: String { preview.contentType }
    var isVideo: Bool { preview.isVideo }
    var isGIF: Bool { preview.isGIF }
    var aspectRatio: CGFloat { preview.aspectRatio }
}
