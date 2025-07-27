//
//  NewPostModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/06/2023.
//

import Foundation
import SwiftUI
import Combine
import NostrEssentials

public final class TypingTextModel: ObservableObject {
    var draft: String {
        get { Drafts.shared.draft  }
        set {
            DispatchQueue.main.async {
                Drafts.shared.draft = newValue
            }
        }
    }
    
    var restoreDraft: String {
        get { Drafts.shared.restoreDraft  }
        set {
            DispatchQueue.main.async {
                Drafts.shared.restoreDraft = newValue
            }
        }
    }
    
    @Published var text: String = "" {
        didSet {
            draft = text
        }
    }
    @Published var pastedImages: [PostedImageMeta] = []
    @Published var pastedVideos: [PostedVideoMeta] = []
    
    @Published var voiceRecording: VoiceRecording?
    
    public var compressedVideoFiles: [URL] = [] // need a place to track tmp files created so we can clean up after upload
    @Published var selectedMentions: Set<NRContact> = [] // will become p-tags in the final post
    @Published var unselectedMentions: Set<NRContact> = [] // unselected from reply-p's, but maybe mentioned as nostr:npub, so should not be put back in p
    @Published var sending = false
    @Published var uploading = false
    private var subscriptions = Set<AnyCancellable>()
    
    init() {
        if !draft.isEmpty { // Restore after Cancel
            let isMentionPrefix = draft.hasPrefix("@") && draft.count < 20
            if !isMentionPrefix {
                text = draft
            }
        }
        restoreDraft = ""
    }
}

func enableAuthAndSendChallengeOnSingleRelay(usingAccount: CloudAccount? = nil) {
    guard let singleRelay = Drafts.shared.lockToThisRelay else { return }
    if ( !(ConnectionPool.shared.connections[singleRelay.id]?.isConnected ?? true) ) {
        ConnectionPool.shared.connections[singleRelay.id]?.connect()
    }
    ConnectionPool.shared.connections[singleRelay.id]?.relayData.setAuth(true)
    ConnectionPool.shared.connections[singleRelay.id]?.sendAuthResponse(usingAccount: usingAccount, force: true)
}

public final class NewPostModel: ObservableObject {
    
    @Published var lockToSingleRelay: Bool = false {
        didSet {
            if lockToSingleRelay {
                enableAuthAndSendChallengeOnSingleRelay(usingAccount: activeAccount)
            }
        }
    }
    
    // For remote included images we need to download and fetch dimensions/blurhash
    var remoteIMetas: [String: iMetaInfo] = [:]
    
    @AppStorage("nip96_api_url") private var nip96apiUrl = ""
    public var uploader = Nip96Uploader()
    
    public var typingTextModel = TypingTextModel()
    private var mentioning = false
    @Published var showMentioning = false // To reduce rerendering, use this flag instead of (vm.mentioning && !vm.filteredContactSearchResults.isEmpty)
    private var term: String = ""
    var nEvent: NEvent?
    var lastHit: String = "NOHIT"
    var textView: SystemTextView?
    
    @Published var uploadError: String?
    var requiredP: String? = nil
    @Published var availableContacts: Set<NRContact> = [] // are available to toggle on/off for notifications
    
    @Published var previewNEvent: NEvent? // needed for AutoPilot preview (and probably should use this more and reduce use of Event)
    @Published var previewNRPost: NRPost?
    @Published var gifSheetShown = false
    
    @Published var contactSearchResults: [NRContact] = []
    @Published var activeAccount: CloudAccount? = nil {
        didSet {
            if lockToSingleRelay {
                enableAuthAndSendChallengeOnSingleRelay(usingAccount: activeAccount)
            }
        }
    }
    
    @Published var selectedAuthor: Contact? // To include in 9802 highlight
    
    private var subscriptions = Set<AnyCancellable>()
    
    public init(dueTime: TimeInterval = 0.2) {
        self.typingTextModel.$text
            .removeDuplicates()
            .debounce(for: .seconds(dueTime), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                Importer.shared.delayProcessing()
                self?.textChanged(value)
            })
            .store(in: &subscriptions)
    }
    
    var filteredContactSearchResults: [NRContact] {
        let wot = WebOfTrust.shared
        if WOT_FILTER_ENABLED() {
            return contactSearchResults
                // WoT enabled, so put in-WoT before non-WoT
                .sorted(by: { wot.isAllowed($0.pubkey) && !wot.isAllowed($1.pubkey) })
                // Put following before non-following
                .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
                // TODO: Put mentioned in thread before all
        }
        else {
            // WoT disabled, just following before non-following
            return contactSearchResults
                .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
                // TODO: Put mention in thread before all
        }
    }
    
    static let rules: [HighlightRule] = [
        HighlightRule(pattern: NewPostModel.mentionRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(Themes.default.theme.accent)),
            TextFormattingRule(fontTraits: .traitBold)
        ]),
        HighlightRule(pattern: NewPostModel.typingRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(Themes.default.theme.accent)),
            TextFormattingRule(fontTraits: .traitBold)
        ])
    ]
    static let typingRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\x{2063}\\x{2064}[^\\x{2063}\\x{2064}]+\\x{2064}\\x{2063}|(?<![/\\?])#)", options: [])
    static let mentionRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\w+|(?<![/\\?])#\\S+)", options: [])
    
    func sendNow(isNC: Bool, pubkey: String, account: CloudAccount, replyTo: ReplyTo? = nil, quotePost: QuotePost? = nil, onDismiss: @escaping () -> Void) async {
        Importer.shared.delayProcessing()
        if (!typingTextModel.pastedImages.isEmpty || !typingTextModel.pastedVideos.isEmpty || typingTextModel.voiceRecording != nil) {
            Task { @MainActor in
                typingTextModel.uploading = true
            }
            
            // Convert older api url to nip96 endpoint
            if (nip96apiUrl.isEmpty && SettingsStore.shared.defaultMediaUploadService.name == "nostrcheck.me") { // upgrade nostrcheck.me v1 to v2
                nip96apiUrl = "https://nostrcheck.me/api/v2/media"
            }
            
            if (nip96apiUrl.isEmpty && SettingsStore.shared.defaultMediaUploadService.name == "nostr.build") { 
                nip96apiUrl = "https://nostr.build/api/v2/nip96/upload"
            }
            
            if SettingsStore.shared.defaultMediaUploadService.name == BLOSSOM_LABEL {
                guard let blossomServer = SettingsStore.shared.blossomServerList.first, let blossomServerURL = URL(string: blossomServer) else {
                    sendNotification(.anyStatus, ("Blossom server list is empty", "NewPost"))
                    return
                }
                // TODO: remove hashing same data over and over, clean up a bit
                
                let maxWidth: CGFloat = 2800.0
                // [(resizedImage, type, blurhash, index, unsignedAuthHeaderEvent)]
                let uploadItems: [(Data, String, String?, Int, NEvent)] = typingTextModel.pastedImages
                    .compactMap { imageMeta in // Resize images

                        // .GIF
                        if imageMeta.type == .gif {
                            // Resize first for faster blurhash
                            if let scaledImage = UIImage(data: imageMeta.data) {
                                let resized = scaledImage.resized(to: CGSize(width: 32, height: 32))
                                let blurhash: String? = resized.blurHash(numberOfComponents: (4, 3))
                                
                                let unsignedAuthHeaderEvent = getUnsignedAuthorizationHeaderEvent(pubkey: pubkey, sha256hex: imageMeta.data.sha256().hexEncodedString())
                                
                                return (imageMeta.data, PostedImageMeta.ImageType.gif.rawValue, blurhash, imageMeta.index, unsignedAuthHeaderEvent)
                            }
                            
                            let unsignedAuthHeaderEvent = getUnsignedAuthorizationHeaderEvent(pubkey: pubkey, sha256hex: imageMeta.data.sha256().hexEncodedString())
                            
                            return (imageMeta.data, PostedImageMeta.ImageType.gif.rawValue, nil, imageMeta.index, unsignedAuthHeaderEvent)
                        }
                        
                        // NOT .GIF
                        guard let imageData = imageMeta.uiImage else { return nil }
                        let scale = imageData.size.width > maxWidth ? imageData.size.width / maxWidth : 1
                        let size = CGSize(width: imageData.size.width / scale, height: imageData.size.height / scale)
                        
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1 // 1x scale, for 2x use 2, and so on
                        let renderer = UIGraphicsImageRenderer(size: size, format: format)
                        let scaledImage = renderer.image { _ in
                            imageData.draw(in: CGRect(origin: .zero, size: size))
                        }
                        
                        if let scaledData = scaledImage.jpegData(compressionQuality: 0.85) {
                            // Resize first for faster blurhash
                            let resized = scaledImage.resized(to: CGSize(width: 32, height: 32))
                            let blurhash: String? = resized.blurHash(numberOfComponents: (4, 3))
                            
                            let unsignedAuthHeaderEvent = getUnsignedAuthorizationHeaderEvent(pubkey: pubkey, sha256hex: scaledData.sha256().hexEncodedString())
                            
                            return (scaledData, PostedImageMeta.ImageType.jpeg.rawValue, blurhash, imageMeta.index, unsignedAuthHeaderEvent)
                        }
                        return nil
                    } + typingTextModel.pastedVideos
                    .compactMap { videoMeta in // compress
                        let compressedURL = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".mp4")
                        typingTextModel.compressedVideoFiles.append(compressedURL)
                        if let url = compressVideoSynchronously(inputURL: videoMeta.videoURL, outputURL: compressedURL), let compressedVideoData = try? Data(contentsOf: url) {
                                         
                            let unsignedAuthHeaderEvent = getUnsignedAuthorizationHeaderEvent(pubkey: pubkey, sha256hex: compressedVideoData.sha256().hexEncodedString())
                            
                            return (compressedVideoData, "video/mp4", nil, typingTextModel.pastedImages.count + videoMeta.index, unsignedAuthHeaderEvent)
                        }
                        
                        // Version without compression: TODO: Add toggle for compression ON/OFF
//                        if let compressedVideoData = try? Data(contentsOf: videoMeta.videoURL) {
//                            return (compressedVideoData, typingTextModel.pastedImages.count + videoMeta.index)
//                        }
                        return nil
                    }
                
                let unsignedAuthHeaderEvents: [NEvent] = uploadItems.map { $0.4 }
                
                batchSignEvents(unsignedAuthHeaderEvents, account: account) { signedEventsDict in
                    let blossomUploader = BlossomUploader(blossomServerURL)
                    blossomUploader.queued = uploadItems.compactMap { tuple in
                        if let signedEvent = signedEventsDict[tuple.4.id], let authHeader = toHttpAuthHeader(signedEvent) {
                            return BlossomUploadItem(data: tuple.0, index: tuple.3, contentType: tuple.1, authorizationHeader: authHeader)
                        } else {
                            sendNotification(.anyStatus, ("Problem with remote signer", "NewPost"))
                            return nil
                        }
                    }
                    
                    blossomUploader.onFinish = {
                        let imetas: [Nostur.Imeta] = blossomUploader.queued
                            .compactMap {
                                guard let url = $0.downloadUrl else { return nil }
                                return Imeta(url: url, dim: $0.dim, hash: $0.sha256processed, blurhash: $0.blurhash)
                            }
                        
                        Task { @MainActor in
                            self._sendNow(imetas: imetas, replyTo: replyTo, quotePost: quotePost, onDismiss: onDismiss)
                        }
                        
                        if SettingsStore.shared.blossomServerList.count > 1 { // Mirror uploads to other blossom servers
                            
                            // Need new auth header because the file we mirror has a different hash after processing
                            let unsignedAuthHeaderEventsTuple: [(NEvent, BlossomUploadItem)] = blossomUploader.queued.compactMap { uploadItem in
                                guard let sha256processed = uploadItem.sha256processed else { return nil }
                                return (getUnsignedAuthorizationHeaderEvent(pubkey: pubkey, sha256hex: sha256processed), uploadItem)
                            }
                            
                            let unsignedAuthHeaderEvents: [NEvent] = unsignedAuthHeaderEventsTuple.map { $0.0 }
                            
                            batchSignEvents(unsignedAuthHeaderEvents, account: account) { signedEventsDict in
                                // For every mirror server, upload each file again
                                
                                for server in SettingsStore.shared.blossomServerList.dropFirst(1) {
                                    guard let blossomServer = URL(string: server) else { continue }
                                    let mirrorUploader = BlossomUploader(blossomServer)
                                    for tuple in unsignedAuthHeaderEventsTuple {
                                        
                                        if let signedEvent = signedEventsDict[tuple.0.id], let authHeader = toHttpAuthHeader(signedEvent) {
                                            let uploadItem: BlossomUploadItem = tuple.1
                                            uploadItem.authorizationHeader = authHeader
                                            Task {
                                                try await mirrorUploader.mirrorUpload(uploadItem: uploadItem, authorizationHeader: authHeader)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // clean up video tmp files (compressed videos)
                        for videoURL in self.typingTextModel.compressedVideoFiles {
                            try? FileManager.default.removeItem(at: videoURL)
                        }
                    }
                    
                    blossomUploader.uploadingPublishers(for: blossomUploader.queued)
                        .receive(on: RunLoop.main)
                        .sink(receiveCompletion: { result in
                            switch result {
                            case .failure(let error as URLError) where error.code == .userAuthenticationRequired:
                                L.og.error("Error uploading images (401): \(error.localizedDescription)")
                                self.uploadError = "Media upload authorization error"
                                sendNotification(.anyStatus, ("Media upload authorization error", "NewPost"))
                            case .failure(let error):
                                L.og.error("Error uploading images: \(error.localizedDescription)")
                                self.uploadError = "Image upload error"
                                sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                            case .finished:
#if DEBUG
                                L.og.debug("All images uploaded successfully")
#endif
                                break
                            }
                        }, receiveValue: { uploadItems in
                            for uploadItem in uploadItems {
                                blossomUploader.processResponse(uploadItem: uploadItem)
                            }
                        })
                        .store(in: &self.subscriptions)
                }
            }
            else if !nip96apiUrl.isEmpty { // new nip96 media services
                guard let nip96apiURL = URL(string: nip96apiUrl) else {
                    sendNotification(.anyStatus, ("Problem with Custom File Storage Server", "NewPost"))
                    return
                }
                let boundary = UUID().uuidString
                
                let maxWidth: CGFloat = 2800.0
                // [(resizedImage, type, blurhash, index, unsignedAuthHeaderEvent)]
                let uploadItems: [(Data, String, String?, Int, NEvent)] = typingTextModel.pastedImages
                    .compactMap({ (imageMeta: PostedImageMeta) -> (Data, String, String?, Int, NEvent)? in // Resize images
                        
                        // .GIF
                        if imageMeta.type == .gif {
                            
                            let filename = "media.gif"
                            let contentType = contentType(for: filename)
                            let httpBody = makeHttpBody(mediaData: imageMeta.data, contentType: contentType, boundary: boundary)
                            let sha256hex = httpBody.sha256().hexEncodedString()
                            let unsignedAuthHeaderEvent = getUnsignedAuthorizationHeaderEvent96(pubkey: pubkey, sha256hex: sha256hex, method: "POST", apiUrl: nip96apiURL)
                            
                            // Resize first for faster blurhash
                            if let scaledImage = UIImage(data: imageMeta.data) {
                                let resized = scaledImage.resized(to: CGSize(width: 32, height: 32))
                                let blurhash: String? = resized.blurHash(numberOfComponents: (4, 3))
 
                                return (imageMeta.data, PostedImageMeta.ImageType.gif.rawValue, blurhash, imageMeta.index, unsignedAuthHeaderEvent)
                            }
                            
                            return (imageMeta.data, PostedImageMeta.ImageType.gif.rawValue, nil, imageMeta.index, unsignedAuthHeaderEvent)
                        }
                        
                        // NOT .GIF
                        guard let imageData = imageMeta.uiImage else { return nil }
                        let scale = imageData.size.width > maxWidth ? imageData.size.width / maxWidth : 1
                        let size = CGSize(width: imageData.size.width / scale, height: imageData.size.height / scale)
                        
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1 // 1x scale, for 2x use 2, and so on
                        let renderer = UIGraphicsImageRenderer(size: size, format: format)
                        let scaledImage = renderer.image { _ in
                            imageData.draw(in: CGRect(origin: .zero, size: size))
                        }
                        
                        if let scaledData = scaledImage.jpegData(compressionQuality: 0.85) {
                            // Resize first for faster blurhash
                            let resized = scaledImage.resized(to: CGSize(width: 32, height: 32))
                            let blurhash: String? = resized.blurHash(numberOfComponents: (4, 3))
                            
                            let filename = "media.jpg"
                            let contentType = contentType(for: filename)
                            let httpBody = makeHttpBody(mediaData: scaledData, contentType: contentType, boundary: boundary)
                            let sha256hex = httpBody.sha256().hexEncodedString()
                            let unsignedAuthHeaderEvent = getUnsignedAuthorizationHeaderEvent96(pubkey: pubkey, sha256hex: sha256hex, method: "POST", apiUrl: nip96apiURL)
                            
                            return (scaledData, PostedImageMeta.ImageType.jpeg.rawValue, blurhash, imageMeta.index, unsignedAuthHeaderEvent)
                        }
                        return nil
                    }) + typingTextModel.pastedVideos
                    .compactMap({ (videoMeta: PostedVideoMeta) -> (Data, String, String?, Int, NEvent)? in // compress
                        let compressedURL = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".mp4")
                        typingTextModel.compressedVideoFiles.append(compressedURL)
                        if let url = compressVideoSynchronously(inputURL: videoMeta.videoURL, outputURL: compressedURL), let compressedVideoData = try? Data(contentsOf: url) {
                            
                            let filename = "media.mp4"
                            let contentType = contentType(for: filename)
                            let httpBody = makeHttpBody(mediaData: compressedVideoData, contentType: contentType, boundary: boundary)
                            let sha256hex = httpBody.sha256().hexEncodedString()
                            let unsignedAuthHeaderEvent = getUnsignedAuthorizationHeaderEvent96(pubkey: pubkey, sha256hex: sha256hex, method: "POST", apiUrl: nip96apiURL)
                            
                            return (compressedVideoData, "video/mp4", nil, (typingTextModel.pastedImages.count + videoMeta.index), unsignedAuthHeaderEvent)
                        }
                        
                        // Version without compression: TODO: Add toggle for compression ON/OFF
//                        if let compressedVideoData = try? Data(contentsOf: videoMeta.videoURL) {
//                            return (compressedVideoData, typingTextModel.pastedImages.count + videoMeta.index)
//                        }
                        return nil
                    })

                let unsignedAuthHeaderEvents: [NEvent] = uploadItems.map { $0.4 }
                
                batchSignEvents(unsignedAuthHeaderEvents, account: account) { signedEventsDict in
                    // TODO: Note, self.upload, different from blossom uploader
                    self.uploader.queued = uploadItems.compactMap { tuple in
                        if let signedEvent = signedEventsDict[tuple.4.id], let authHeader = toHttpAuthHeader(signedEvent) {
                            let filename = switch(tuple.1) {
                            case PostedImageMeta.ImageType.jpeg.rawValue:
                                "media.jpg"
                            case PostedImageMeta.ImageType.png.rawValue:
                                "media.png"
                            case "video/mp4":
                                "media.mp4"
                            default:
                                "media"
                            }
                            return MediaRequestBag(apiUrl: nip96apiURL, method: "POST", uploadtype: "media", filename: filename, mediaData: tuple.0, index: tuple.3, authorizationHeader: authHeader, boundary: boundary, blurhash: tuple.2)
                        } else {
                            sendNotification(.anyStatus, ("Problem with remote signer", "NewPost"))
                            return nil
                        }
                    }
                    
                    self.uploader.onFinish = {
                        let imetas: [Nostur.Imeta] = self.uploader.queued
                            .compactMap {
                                guard let url = $0.downloadUrl else { return nil }
                                return Imeta(url: url, dim: $0.dim, hash: $0.sha256, blurhash: $0.blurhash)
                            }
                        
                        Task { @MainActor in
                            self._sendNow(imetas: imetas, replyTo: replyTo, quotePost: quotePost, onDismiss: onDismiss)
                        }
                        
                        // clean up video tmp files (compressed videos)
                        for videoURL in self.typingTextModel.compressedVideoFiles {
                            try? FileManager.default.removeItem(at: videoURL)
                        }
                    }
                    
                    self.uploader.uploadingPublishers(for: self.uploader.queued)
                        .receive(on: RunLoop.main)
                        .sink(receiveCompletion: { result in
                            switch result {
                            case .failure(let error as URLError) where error.code == .userAuthenticationRequired:
                                L.og.error("Error uploading images (401): \(error.localizedDescription)")
                                self.uploadError = "Media upload authorization error"
                                sendNotification(.anyStatus, ("Media upload authorization error", "NewPost"))
                            case .failure(let error):
                                L.og.error("Error uploading images: \(error.localizedDescription)")
                                self.uploadError = "Image upload error"
                                sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                            case .finished:
#if DEBUG
                                L.og.debug("All images uploaded successfully")
#endif
                                break
                            }
                        }, receiveValue: { mediaRequestBags in
                            for mediaRequestBag in mediaRequestBags {
                                self.uploader.processResponse(mediaRequestBag: mediaRequestBag)
                            }
                        })
                        .store(in: &self.subscriptions)
                }
            }
            else { // old media upload services
                uploadImages(images: typingTextModel.pastedImages)
                    .receive(on: RunLoop.main)
                    .sink(receiveCompletion: { result in
                        switch result {
                        case .failure(let error):
                            L.og.error("Error uploading images: \(error.localizedDescription)")
                            self.uploadError = "Image upload error"
                            sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                        case .finished:
#if DEBUG
                            L.og.debug("All images uploaded successfully")
#endif
                            break
                        }
                    }, receiveValue: { urls in
                        if (self.typingTextModel.pastedImages.count == urls.count) {
                            let imetas = urls.map { Imeta(url: $0) }
                            Task { @MainActor in
                                self._sendNow(imetas: imetas, replyTo: replyTo, quotePost: quotePost, onDismiss: onDismiss)
                            }
                        }
                    })
                    .store(in: &subscriptions)
            }
        }
        else {
            Task { @MainActor in
                self._sendNow(imetas: [], replyTo: replyTo, quotePost: quotePost, onDismiss: onDismiss)
            }
        }
    }
    
    @MainActor
    private func _sendNow(imetas: [Imeta], replyTo: ReplyTo? = nil, quotePost: QuotePost? = nil, onDismiss: @escaping () -> Void) {
        Importer.shared.delayProcessing()
        guard let account = activeAccount else { return }
        account.lastLoginAt = .now
        guard isFullAccount(account) else { showReadOnlyMessage(); return }
        
        
        guard var finalEvent = buildFinalEvent(imetas: imetas, replyTo: replyTo, quotePost: quotePost) else { return }
        
        // Need draft here because it might be cleared before we need it because async later
        self.typingTextModel.restoreDraft = self.typingTextModel.draft
        
        let lockToThisRelay: RelayData? = Drafts.shared.lockToThisRelay
        
        let cancellationId = UUID()
        if account.isNC {
            finalEvent = finalEvent.withId()
            
            // Save unsigned event:
            let bgContext = bg()
            bgContext.perform {
                let savedEvent = Event.saveEvent(event: finalEvent, flags: "nsecbunker_unsigned", context: bgContext)
                savedEvent.cancellationId = cancellationId
                DispatchQueue.main.async {
                    if let lockToThisRelay = lockToThisRelay, self.lockToSingleRelay {
                        sendNotification(.newSingleRelayPostSaved, (savedEvent, lockToThisRelay))
                    }
                    else {
                        sendNotification(.newPostSaved, savedEvent)
                    }
                }
                DataProvider.shared().bgSave()
                
                DispatchQueue.main.async {
                    NSecBunkerManager.shared.requestSignature(forEvent: finalEvent, usingAccount: account, whenSigned: { signedEvent in
                        bg().perform {
                            savedEvent.sig = signedEvent.signature
                            savedEvent.flags = "awaiting_send"
                            savedEvent.cancellationId = cancellationId
//                            savedEvent.updateNRPost.send(savedEvent)
                            ViewUpdates.shared.updateNRPost.send(savedEvent)
                            DispatchQueue.main.async {
                                _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId, lockToThisRelay: Drafts.shared.lockToThisRelay)
                            }
                        }
                    })
                }
            }
        }
        else if let signedEvent = try? account.signEvent(finalEvent) {
            let bgContext = bg()
            bgContext.perform {
                let savedEvent = Event.saveEvent(event: signedEvent, flags: "awaiting_send", context: bgContext)
                savedEvent.cancellationId = cancellationId
                // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                if finalEvent.kind == .reaction {
                    Event.updateReactionTo(savedEvent, context: bg()) // TODO: Revert this on 'undo'
                }
                
                DataProvider.shared().bgSave()
                if ([1,6,20,9802,30023,34235].contains(savedEvent.kind)) {
                    DispatchQueue.main.async {
                        if let lockToThisRelay = lockToThisRelay, self.lockToSingleRelay {
                            sendNotification(.newSingleRelayPostSaved, (savedEvent, lockToThisRelay))
                        }
                        else {
                            sendNotification(.newPostSaved, savedEvent)
                        }
                    }
                }
            }
            _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId, lockToThisRelay: Drafts.shared.lockToThisRelay)
        }
        
        if let replyTo, !replyTo.nrPost.isRestricted { // Rebroadcast if not restricted
            bg().perform {
                guard let bgEvent = replyTo.nrPost.event else { return }
                let replyToNEvent = bgEvent.toNEvent()
                let replyToId = bgEvent.id
                DispatchQueue.main.async {
                    sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyToId))
                    // Republish post being replied to
                    Unpublisher.shared.publishNow(replyToNEvent)
                }
            }
        }
        if let quotePost, !quotePost.nrPost.isRestricted { // Rebroadcast if not restricted
            bg().perform {
                guard let bgEvent = quotePost.nrPost.event else { return }
                let quotingNEvent = bgEvent.toNEvent()
                let quotingEventId = bgEvent.id
                DispatchQueue.main.async {
                    sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: quotingEventId))
                    // Republish post being quoted
                    Unpublisher.shared.publishNow(quotingNEvent)
                }
            }
        }
        onDismiss()
        sendNotification(.didSend)
    }
    
    private func buildFinalEvent(imetas: [Imeta], replyTo: ReplyTo? = nil, quotePost: QuotePost? = nil, isPreviewContext: Bool = false) -> NEvent? {
        guard var nEvent = self.nEvent else { return nil }
        guard let account = activeAccount else { return nil }
        let publicKey = account.publicKey

        nEvent.publicKey = publicKey
        var pTags: [String] = []
        nEvent.createdAt = NTimestamp.init(date: Date())
        
        if nEvent.kind == .highlight {
            if let selectedAuthor = selectedAuthor {
                nEvent.tags.append(NostrTag(["p", selectedAuthor.pubkey]))
            }
        }
        
        var content: String = typingTextModel.text // put this eventually in .content or comment tag, depending on kind 9802 or not
        
        // Handle images
        if !imetas.isEmpty || !remoteIMetas.isEmpty {
             
            // imetas from local uploaded / pasted images
            for imeta in imetas {
                
                // don't add image urls in .content for kind:20
                if nEvent.kind != .picture {
                    content += "\n\(imeta.url)"
                }
                
                var imetaParts: [String] = ["imeta", "url \(imeta.url)"]
                if let dim = imeta.dim, !dim.isEmpty {
                    imetaParts.append("dim \(dim)")
                }
                if let blurhash = imeta.blurhash, !blurhash.isEmpty {
                    imetaParts.append("blurhash \(blurhash)")
                }
                if let hash = imeta.hash, !hash.isEmpty {
                    imetaParts.append("sha256 \(hash)")
                }

                nEvent.tags.append(NostrTag(imetaParts))
            }
            
            // imetas from included image urls (generated from MediaContentView)
            for (key: imageUrl, value: imeta) in remoteIMetas {
                if content.contains(imageUrl) {
                    
                    var imetaParts: [String] = ["imeta", "url \(imageUrl)"]
                    if let size = imeta.size {
                        imetaParts.append("dim \(Int(size.width.rounded(.up)))x\(Int(size.height.rounded(.up)))")
                    }
                    if let blurHash = imeta.blurHash, !blurHash.isEmpty {
                        imetaParts.append("blurhash \(blurHash)")
                    }
                    
                    nEvent.tags.append(NostrTag(imetaParts))
                    
                }
            }
        }
        
        // Handle preview images
        if isPreviewContext {
            // Preview doesn't have image urls yet (is before upload), so we still render from local
            
            // kind:20 (images on top)
            if nEvent.kind == .picture {
                var images = ""
                for index in typingTextModel.pastedImages.indices {
                    images = images + "\n--@!^@\(index)@^!@--"
                }
                
                // More than 1 image? Put text first
                if typingTextModel.pastedImages.count > 1 {
                    content = content + images
                }
                else { // Else picture first, text caption below
                    content = images + content
                }
            }
            else { // other kinds (images below content)
                for index in typingTextModel.pastedImages.indices {
                    content = content + "\n--@!^@\(index)@^!@--"
                }
                
                for index in typingTextModel.pastedVideos.indices {
                    content = content + "\n-V-@!^@\(index)@^!@-V-"
                }
                
            }
        }
        
        // Typed @mentions to nostr:npub
        if #available(iOS 16.0, *) {
            content = replaceMentionsWithNpubs(content, selected: typingTextModel.selectedMentions)
        }
        else {
            content = replaceMentionsWithNpubs15(content, selected: typingTextModel.selectedMentions)
        }
        
        // @npubs to nostr:npub and return pTags
        let (contentNpubsReplaced, atNpubs) = replaceAtWithNostr(content)
        content = contentNpubsReplaced
        let atPtags = atNpubs.compactMap { Keys.hex(npub: $0) }
        
        // Scan for any nostr:npub and return pTags
        let npubs = getNostrNpubs(content)
        let nostrNpubTags = npubs.compactMap { Keys.hex(npub: $0) }
        
        // Scan for any nostr:note1 or nevent1 and return q tags
        let qTags = Set(getQuoteTags(content)) // TODO: Should resolve p-tags from quoted events and include those too.
        
        // #hashtags to .t tags
        nEvent = putHashtagsInTags(nEvent, content: content)

        var unselectedPtags = typingTextModel.unselectedMentions.map { $0.pubkey }
        
        // always include the .p of pubkey we are replying to (not required by spec, but more healthy for nostr)
        if let requiredP = requiredP {
            pTags.append(requiredP)
            unselectedPtags.removeAll(where: { $0 == requiredP })
        }
        
        if let replyTo, let replyToMain = replyTo.nrPost.event?.toMain()  {
            // pTags from replyTo.pTags
            let replyToPTags = replyToMain.pTags() + [replyToMain.pubkey]
            pTags.append(contentsOf: replyToPTags)
        }
        
        // Merge and deduplicate all p pubkeys, remove all unselected p pubkeys and turn into NostrTag
        let nostrTags = Set(pTags + atPtags + nostrNpubTags)
            .subtracting(Set(unselectedPtags))
            .map { NostrTag(["p", $0]) }
        
        nEvent.tags.append(contentsOf: nostrTags)
        
        // If we are quote reposting, include the quoted post as nostr:nevent at the end
        if let quotePost, let quotePostMain = quotePost.nrPost.event?.toMain() {
            
            let relayHint: String? = resolveRelayHint(forPubkey: quotePost.nrPost.pubkey, receivedFromRelays: quotePostMain.relays_).first
            
            if let si = try? NostrEssentials.ShareableIdentifier("nevent", id: quotePost.nrPost.id, kind: Int(quotePost.nrPost.kind), pubkey: quotePost.nrPost.pubkey, relays: [relayHint].compactMap { $0 }) {
                content = (content + "\nnostr:" + si.identifier)
            }
            else if let note1id = note1(quotePost.nrPost.id) {
                content = (content + "\nnostr:" + note1id)
            }
            
            nEvent.tags.insert(NostrTag(["q", quotePost.nrPost.id, relayHint ?? "", quotePost.nrPost.pubkey]), at: 0)
            
            if !nEvent.pTags().contains(quotePost.nrPost.pubkey) {
                nEvent.tags.append(NostrTag(["p", quotePost.nrPost.pubkey]))
            }
        }
        
        qTags.forEach { qTag in
            nEvent.tags.append(NostrTag(["q", qTag]))
        }
        
        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            content = replaceNsecWithHunter2(content)
        }
        
        let lockToThisRelay: RelayData? = Drafts.shared.lockToThisRelay
        
        if lockToThisRelay != nil && lockToSingleRelay {
            nEvent.tags.append(NostrTag(["-"]))
        }
        
        if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey)) {
            nEvent.tags.append(NostrTag(["client", "Nostur", NIP89_APP_REFERENCE]))
        }
        
        if nEvent.kind == .highlight { // for highlight the content is in the comment tag
            nEvent.tags.append(NostrTag(["comment", content]))
        }
        else {
            nEvent.content = content
        }
        
        return nEvent
    }
    
    func showPreview(quotePost: QuotePost? = nil, replyTo: ReplyTo? = nil) {
        
        guard let finalNEvent = buildFinalEvent(imetas: [], replyTo: replyTo, quotePost: quotePost, isPreviewContext: true) else { return }
        
        bg().perform { [weak self] in
            guard let self else { return }
            let previewEvent = createPreviewEvent(finalNEvent)
            if (!self.typingTextModel.pastedImages.isEmpty) {
                previewEvent.previewImages = self.typingTextModel.pastedImages
            }
            if (!self.typingTextModel.pastedVideos.isEmpty) {
                previewEvent.previewVideos = self.typingTextModel.pastedVideos
            }
            let nrPost = NRPost(event: previewEvent, withFooter: false)
            DispatchQueue.main.async { [weak self] in
                self?.previewNEvent = finalNEvent
                self?.previewNRPost = nrPost
            }
            bg().delete(previewEvent)
        }
    }
    
    func selectContactSearchResult(_ nrContact: NRContact) {
        guard let textView = textView else { return }
        let mentionName = nrContact.anyName
        let mentionText = "\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063} " // invisible characters to replace later

        if let selectedRange = textView.selectedTextRange {
            let cursorPosition = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
            var currentText = textView.text ?? ""
            
            // Insert the mention text at the cursor position
            let textBeforeCursor = currentText.prefix(cursorPosition)
            
            // #0    (null) in Swift runtime failure: Can't take a suffix of negative length from a collection () <-- Maybe fix with max(,)
            let textAfterCursor = currentText.suffix(max(0,currentText.count - cursorPosition))
            currentText = "\(textBeforeCursor.dropLast(term.count))\(mentionText)\(textAfterCursor)"
            
            // Update the text storage
//            textView.text = currentText
            
            let mentionLength = "\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063} ".count - term.count // "@fa" becomes "@fabian " and we count "bian "
            
            // Change cursor position to after replacement
            // so from "@fa" to "@fabian "
            if let selectedRange = self.textView!.selectedTextRange {
                let currentPosition = selectedRange.end
                
                // move the cursor
                if let newPosition = self.textView!.position(from: currentPosition, offset: mentionLength) {
                    textView.text = currentText
                    self.textView!.selectedTextRange = self.textView!.textRange(from: newPosition, to: newPosition)
                }
                else {
                    // or if for some reason the cursor is out of range, just move to end
                    textView.text = currentText
                    let newPosition = self.textView!.endOfDocument
                    self.textView!.selectedTextRange = self.textView!.textRange(from: newPosition, to: newPosition)
                }
            }
            
            // Update the typingTextModel text
            typingTextModel.text = currentText
            
            // Update the available contacts and selected mentions
            availableContacts.insert(nrContact)
            typingTextModel.selectedMentions.insert(nrContact)
            mentioning = false
            contactSearchResults = []
            lastHit = mentionName

            
            term = ""
        }
    }
    
    public func textChanged(_ newText:String) {
        guard textView != nil else { return }
        if let mentionTerm = mentionTerm(newText, textView: textView) {
            if mentionTerm == lastHit {
                mentioning = false
            }
            else {
                mentioning = true
                term = mentionTerm
                self.searchContacts(mentionTerm)
            }
            
        }
        else {
            if mentioning {
                mentioning = false
            }
        }
        
        let showMentioning = mentioning && !filteredContactSearchResults.isEmpty
        if showMentioning != self.showMentioning { // check first to reduce rerendering
            self.showMentioning = showMentioning
        }
    }
    
    private func searchContacts(_ mentionTerm: String) {
        Importer.shared.delayProcessing()
        bg().perform {
            let fr = Contact.fetchRequest()
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)]
            fr.predicate = NSPredicate(format: "(display_name CONTAINS[cd] %@ OR name CONTAINS[cd] %@) AND NOT pubkey IN %@", mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), AppState.shared.bgAppState.blockedPubkeys)
            
            let contactSearchResults: [NRContact] = Array(((try? bg().fetch(fr)) ?? []).prefix(60))
                .map { NRContact.instance(of: $0.pubkey, contact: $0) }
            
            Task { @MainActor [weak self] in
                self?.contactSearchResults = contactSearchResults
            }
        }
    }
    
    func loadQuotingEvent() {
        var newQuoteRepost = NEvent(content: typingTextModel.text)
        newQuoteRepost.kind = .textNote
        nEvent = newQuoteRepost
    }
    
    func loadReplyTo(_ replyTo: ReplyTo) {
        requiredP = replyTo.nrPost.pubkey
        var newReply = NEvent(content: typingTextModel.text)
        newReply.kind = .textNote
        bg().perform {
            guard let replyToEvent = replyTo.nrPost.event else { return }
            let existingPtags = replyToEvent.pTags()
            
            let availableContacts: [NRContact] = Set(Contact.fetchByPubkeys(existingPtags, context: bg()))
                .map { NRContact.instance(of: $0.pubkey, contact: $0) }
            
            let replyToNrContact: NRContact? = if let contact = replyToEvent.contact {
                NRContact.fetch(contact.pubkey, contact: contact)
            }
            else {
                nil
            }
            
            Task { @MainActor in
                self.availableContacts = Set([replyToNrContact].compactMap { $0 } + availableContacts)
                self.typingTextModel.selectedMentions = Set([replyToNrContact].compactMap { $0 } + availableContacts)
            }
            
            let root = TagsHelpers(replyToEvent.tags()).replyToRootEtag()
            
            if (root != nil) { // ADD "ROOT" + "REPLY"
                let newRootTag = NostrTag(["e", root!.tag[1], "", "root"]) // TODO RECOMMENDED RELAY HERE
                newReply.tags.append(newRootTag)
                
                let newReplyTag = NostrTag(["e", replyToEvent.id, "", "reply"])
                
                newReply.tags.append(newReplyTag)
            }
            else { // ADD ONLY "ROOT"
                let newRootTag = NostrTag(["e", replyToEvent.id, "", "root"])
                newReply.tags.append(newRootTag)
            }
            
            let rootA = replyToEvent.toNEvent().replyToRootAtag()
            
            if (rootA != nil) { // ADD EXISTING "ROOT" (aTag) FROM REPLYTO
                let newRootATag = NostrTag(["a", rootA!.tag[1], "", "root"]) // TODO RECOMMENDED RELAY HERE
                newReply.tags.append(newRootATag)
            }
            else if replyToEvent.kind == 30023 { // ADD ONLY "ROOT" (aTag) (DIRECT REPLY TO ARTICLE)
                let newRootTag = NostrTag(["a", replyToEvent.aTag, "", "root"]) // TODO RECOMMENDED RELAY HERE
                newReply.tags.append(newRootTag)
            }

            Task { @MainActor in
                self.nEvent = newReply
            }
        }
    }
    
    func directMention(_ contact: NRContact) {
        guard textView != nil else { return }
        guard let pubkey = account()?.publicKey, pubkey != contact.pubkey else { return }
        let mentionName = contact.anyName
        typingTextModel.text = "@\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063} "
        availableContacts.insert(contact)
        typingTextModel.selectedMentions.insert(contact)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // after 0.3 sec to get the new .endOfDocument
            let newPosition: UITextPosition = self.textView!.endOfDocument
            self.textView!.selectedTextRange = self.textView!.textRange(from: newPosition, to: newPosition)
        }
    }
}

func mentionTerm(_ text: String, textView: SystemTextView?) -> String? {
    guard let textView else { return nil }
    
    if let selectedRange = textView.selectedTextRange {
        let cursorPosition = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
        let textUntilCursor = String(text.prefix(cursorPosition))
        
        if let atRange = textUntilCursor.range(of: "@", options: .backwards) {
            let textAfterAt = String(textUntilCursor[atRange.upperBound...])
            return textAfterAt
        }
    }
    return nil
}

struct Imeta {
    let url: String
    var dim: String?
    var hash: String?
    var blurhash: String?
}


public func toHttpAuthHeader(_ nEvent: NEvent) -> String? {
    let jsonString = nEvent.eventJson()
    guard let jsonData = jsonString.data(using: .utf8, allowLossyConversion: true) else {
        return nil
    }
    let base64 = jsonData.base64EncodedString()
    return "Nostr \(base64)"
}

// BLOSSOM
public func getUnsignedAuthorizationHeaderEvent(pubkey: String, sha256hex: String, action: BlossomUploader.Verb = .upload) -> NEvent {
    // 5 minutes from now timestamp
    let expirationTimestamp = Int(Date().timeIntervalSince1970) + 300
    
    var unsignedEvent = NEvent(content: "Upload", kind: .blossomAuth, tags: [
        NostrTag(["t", action.rawValue]),
        NostrTag(["x", sha256hex]),  // hash of file
        NostrTag(["expiration", expirationTimestamp.description])
    ])
    unsignedEvent.publicKey = pubkey
    unsignedEvent = unsignedEvent.withId()
    return unsignedEvent
}


// NIP-96
public func getUnsignedAuthorizationHeaderEvent96(pubkey: String, sha256hex: String, method: String, apiUrl: URL) -> NEvent {
    // 5 minutes from now timestamp
    let expirationTimestamp = Int(Date().timeIntervalSince1970) + 300
    
    var unsignedEvent = NEvent(content: "", kind: .custom(27235), tags: [
        NostrTag(["u", apiUrl.absoluteString]),
        NostrTag(["method", method]),
        NostrTag(["payload", sha256hex]), // hash of entire request.httpBody
    ])
    unsignedEvent.publicKey = pubkey
    unsignedEvent = unsignedEvent.withId()
    return unsignedEvent
}
