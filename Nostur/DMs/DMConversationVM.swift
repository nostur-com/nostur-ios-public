//
//  DMConversationVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/12/2025.
//

import SwiftUI
import CoreData
import NostrEssentials
import Combine

struct PendingFileAttachment {
    let fileURL: URL
    let fileSize: Int64
    let mimeType: String
    let imageDimensions: String?
    let fileName: String?
    let thumbnailImage: UIImage?
    
    var isImage: Bool { mimeType.hasPrefix("image/") }
    
    var fileExtension: String {
        switch mimeType {
        case "image/jpeg": return "JPG"
        case "image/png": return "PNG"
        case "image/gif": return "GIF"
        case "image/webp": return "WEBP"
        case "application/pdf": return "PDF"
        default:
            if let sub = mimeType.split(separator: "/").last {
                return String(sub).uppercased()
            }
            return "FILE"
        }
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

class ConversionVM: ObservableObject {
    public var participants: Set<String> // all participants (including sender)
    public var ourAccountPubkey: String {
        didSet {
            self.account = AccountsState.shared.accounts.first(where: { $0.publicKey == ourAccountPubkey })
        }
    }
    public var receivers: Set<String> {
        participants.subtracting([ourAccountPubkey])
    }
    public var conversationId: String
    
    @Published var viewState: ConversionVMViewState = .initializing
    @Published var lastMessageId: String? = nil
    @Published var scrollToId: String? = nil
    @Published var navigationTitle = "To: ..."
    @Published var receiverContacts: [NRContact] = []
    
    @Published var isAccepted = false
    
    // 4 = NIP-04, 17 = NIP-17
    @Published var conversationVersion: Int = 0 {
        didSet {
            if oldValue == 17 && conversationVersion == 4 {
                Task { @MainActor in
                    self.fetchNip04DMs()
                }
            }
        }
    }
    
    // For DMChatInputField
    @Published var quotingNow: NRChatMessage? = nil {
        didSet { // can only have quote OR reply, so unset other
            if quotingNow == nil { return } // but not if already unsetting
            if replyingNow != nil {
                replyingNow = nil
            }
        }
    }
    @Published var replyingNow: NRChatMessage? = nil {
        didSet { // can only have quote OR reply, so unset other
            if replyingNow == nil { return } // but not if already unsetting
            if quotingNow != nil {
                quotingNow = nil
            }
        }
    }
    @Published var pendingFileAttachment: PendingFileAttachment? = nil {
        didSet {
            if pendingFileAttachment == nil { return }
            replyingNow = nil
            quotingNow = nil
        }
    }
    
    public var account: CloudAccount? = nil
    
    private let dayIdFormatter: DateFormatter
    private let yearIdFormatter: DateFormatter
    
    private var subscriptions: Set<AnyCancellable> = []
    
    public var dmState: CloudDMState? = nil
    
    private var parentDMsVM: DMsVM
    
    init(participants: Set<String>, ourAccountPubkey: String, parentDMsVM: DMsVM) {
        self.participants = participants
        self.ourAccountPubkey = ourAccountPubkey
        self.conversationId = CloudDMState.getConversationId(for: participants)
        
        let dayIdFormatter = DateFormatter()
        dayIdFormatter.dateFormat = "yyyy-MM-dd"          // note: lowercase yyyy
        dayIdFormatter.locale = Locale(identifier: "en_US_POSIX") // ensures consistent format
        self.dayIdFormatter = dayIdFormatter
        
        let yearIdFormatter = DateFormatter()
        yearIdFormatter.dateFormat = "yyyy"          // note: lowercase yyyy
        yearIdFormatter.locale = Locale(identifier: "en_US_POSIX") // ensures consistent format
        self.yearIdFormatter = yearIdFormatter
        
        self.parentDMsVM = parentDMsVM
    }
    
    private var didLoad = false
    
    private var onScreenIds: Set<String> = []
    
    @MainActor
    public func load(force: Bool = false) async {
        guard force || !didLoad else { return }
        self.subscriptions.removeAll()
        self.didLoad = true
        self.viewState = .loading
        self.receiverContacts = receivers.map { NRContact.instance(of: $0) }
        self.dmState = getGroupState()
        self.isAccepted = self.dmState?.accepted ?? false

        if let dmState { // Should always exists because getGroupState() gets existing or creates new
            
            let keyPair: (publicKey: String, privateKey: String)? = if let account = AccountsState.shared.fullAccounts.first(where: { $0.publicKey == self.ourAccountPubkey }), let privateKey = account.privateKey {
                (publicKey: account.publicKey, privateKey: privateKey)
            } else {
                nil
            }
            
            let visibleMessages = await getMessages(conversationId: dmState.conversationId, keyPair: keyPair)
            
            self.onScreenIds = Set(visibleMessages.map { $0.id })
            
            let calendar = Calendar.current
            
            var messagesByDay: [Date: [NRChatMessage]] {
                return Dictionary(grouping: visibleMessages) { nrChatMessage in
                    calendar.startOfDay(for: nrChatMessage.createdAt)
                }
            }
            
            let days = messagesByDay.map { (date, messages) in
                ConversationDay(
                    dayId: dayIdFormatter.string(from: date),
                    date: date,
                    messages: messages // .sorted(by: { $0.createdAt < $1.createdAt })
                )
            }.sorted(by: { $0.dayId > $1.dayId })
            
            var daysByYear: [String: [ConversationDay]] {
                return Dictionary(grouping: days) { day in
                    yearIdFormatter.string(from: day.date)
                }
            }
            
            let years = daysByYear.map { (year, days) in
                ConversationYear(
                    year: year,
                    days: days
                )
            }.sorted(by: { $0.year > $1.year })
            
            viewState = .ready(years)
            lastMessageId = visibleMessages.last?.id
            
            // add DM state to parent vm
            parentDMsVM.addDMState(dmState)
            
            Task { @MainActor in
                if dmState.version == 0 {
                    if participants.count == 2, let receiver = participants.subtracting([ourAccountPubkey]).first, !receiver.isEmpty {
                        // Check DM relays
    #if DEBUG
                        L.og.debug("💌💌 Checking for DM relays for \(nameOrPubkey(receiver)) (useOutbox: true)")
    #endif
                        _ = try? await relayReq(Filters(
                            authors: [receiver],
                            kinds: [10050],
                            limit: 167
                        ), timeout: 2.2, useOutbox: true)
                        
                        let foundRelays = await hasDMrelays(pubkey: receiver)
                        
                        // No relays found? Check search relays
                        if !foundRelays {
    #if DEBUG
                        L.og.debug("💌💌 No DM relays found for \(nameOrPubkey(receiver)), checking .SEARCH_ONLY relays")
    #endif
                            _ = try? await relayReq(Filters(
                                authors: [receiver],
                                kinds: [10050],
                                limit: 167
                            ), timeout: 2.2, relayType: .SEARCH_ONLY)
                        }
                    }
                    let conversationVersion = await self.resolveConversationVersion(participants, messages: visibleMessages)
                    Task { @MainActor in
                        self.conversationVersion = conversationVersion
                        dmState.version = conversationVersion
                    }
                }
            }
        }
        
        
        self.fetchNip04DMs() // Always fetch for older DMs also in case of earlier older messages or older clients
        // newer giftwraps will be fetched from general DMsVM.fetchGiftWraps(), can't query conversation specific with metadata hidden
        self.fetchDMrelays()
        self.listenForNewMessages()
    }
    
    private func listenForNewMessages() {
        Importer.shared.importedDMSub
            .filter { $0.conversationId == self.conversationId }
            .sink { (_, event, nEvent, newDMStateCreated) in
                guard !self.onScreenIds.contains(nEvent.id) else { return }
#if DEBUG
                    L.og.debug("💌💌 Calling self.addToView from importedDMsub: rumor.id: \(nEvent.id)")
#endif
                if nEvent.kind == .directMessage { // already decrypted by unwrap, don't need keypair here
                    _ = self.addToView(nEvent, nil, Date(timeIntervalSince1970: Double(nEvent.createdAt.timestamp)))
                } else {
                    guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: self.ourAccountPubkey), let ourKeys = try? NostrEssentials.Keys(privateKeyHex: privKey) else { return }
                    _ = self.addToView(nEvent, ourKeys, Date(timeIntervalSince1970: Double(nEvent.createdAt.timestamp)))
                }
                
                
            }
            .store(in: &subscriptions)
    }
    
    private func resolveConversationVersion(_ participants: Set<String>, messages: [NRChatMessage]) async -> Int {
        // More than 2 participants = NIP-17
        if participants.count > 2 {
            return 17 // NIP-17
        }
        
        // Last message is kind 14? = NIP17
        if messages.last?.nEvent.kind == .directMessage {
            return 17 // NIP-17
        }
        
        // Last message is kind 15? = NIP17
        if messages.last?.nEvent.kind == .fileMessage {
            return 17 // NIP-17
        }
        
        // no messages yet, but has DM relay (both us and them)? NIP-17
        if messages.isEmpty, let receiverPubkey = participants.subtracting([ourAccountPubkey]).first {
            let receiverHasDMRelays = await hasDMrelays(pubkey: receiverPubkey)
#if DEBUG
            L.og.debug("💌💌 resolveConversationVersion, receiver (\(nameOrPubkey(receiverPubkey))) \(receiverHasDMRelays ? "has" : "has NO") relays")
#endif
            let weHaveDMrelays = await hasDMrelays(pubkey: ourAccountPubkey)
            if receiverHasDMRelays && weHaveDMrelays {
                return 17 // NIP-17
            }
        }
        
        if messages.isEmpty { // We don't know, maybe still need to fetch messages
            return 0
        }
        
        // No indication of NIP-17 support so fall back to NIP-04
        return 4 // NIP-04
    }
    
//    @MainActor
//    public func reload(participants: Set<String>, ourAccountPubkey: String) async {
//        self.participants = participants
//        self.ourAccountPubkey = ourAccountPubkey
//        self.conversationId = CloudDMState.getConversationId(for: participants)
//        
//        await self.load(force: true)
//    }
    
    private func getGroupState() -> CloudDMState {
        // Get existing or create new
        let participants = self.participants
        if let groupDMState = CloudDMState.fetchByParticipants(participants: participants, andAccountPubkey: self.ourAccountPubkey, context: viewContext()) {
            self.conversationVersion = groupDMState.version
            return groupDMState
        }
        let newDMState = CloudDMState.create(accountPubkey: self.ourAccountPubkey, participants: participants, context: viewContext())
        newDMState.accepted = true
        newDMState.initiatorPubkey_ = self.ourAccountPubkey
        newDMState.version = participants.count > 2 ? 17 : 0
        DataProvider.shared().saveToDisk(.bgContext)
        self.conversationVersion = participants.count > 2 ? 17 : 0
        return newDMState
    }
    
    private func getMessages(conversationId: String, keyPair: (publicKey: String, privateKey: String)? = nil) async -> [NRChatMessage] {
        
        let dmEvents = await withBgContext { bgContext in
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.predicate = NSPredicate(format: "groupId = %@ AND kind IN {4,14,15}", conversationId)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)]
            
            
            return ((try? bgContext.fetch(request)) ?? [])
                .map {
                    NEvent(id: $0.id,
                           publicKey: $0.pubkey,
                           createdAt: NTimestamp(timestamp: $0.created_at),
                           content: $0.content ?? "",
                           kind: NEventKind(id: $0.kind),
                           tags: $0.tags(),
                           signature: ""
                    )
                }
                .map {
                    NRChatMessage(nEvent: $0, keyPair: keyPair)
                }
        }
        
        return dmEvents
    }
    
    private var sendJobs: [(receiver: String, wrappedEvent: NostrEssentials.Event, relays: Set<String>)] = []
        
    private var lastAddedIds: RecentSet<String> = .init(capacity: 10)
    
    private func addToView(_ rumorNEvent: NEvent, _ ourkeys: Keys? = nil, _ messageDate: Date) -> NRChatMessage? {
        guard !self.onScreenIds.contains(rumorNEvent.id) else { return nil }
        if lastAddedIds.contains(rumorNEvent.id) {
            // rumorId (if added from local submit, don't add again when receiving from relay)
#if DEBUG
            L.og.debug("💌💌 Don't add to view again rumor.id: \(rumorNEvent.id) ")
#endif
            return nil
        }
        lastAddedIds.insert(rumorNEvent.id)
        self.onScreenIds.insert(rumorNEvent.id)
        
        let keyPair: (publicKey: String, privateKey: String)? = if let ourkeys {
            (publicKey: ourkeys.publicKeyHex, privateKey: ourkeys.privateKeyHex)
        } else {
            nil
        }
        
        let newChatMessage = NRChatMessage(
            nEvent: rumorNEvent,
            keyPair: keyPair
        )
        
        let yearId = yearIdFormatter.string(from: messageDate)
        
        if case .ready(let years) = self.viewState {
            // Does the year exist?
            if let year = years.first(where: { $0.year == yearId }) {
                // Does the day exist?
                if let day = year.days.first(where: { $0.dayId == dayIdFormatter.string(from: messageDate) }) {
                    // Add message to existing day
                    Task { @MainActor in
                        withAnimation {
                            lastMessageId = rumorNEvent.id
                            self.objectWillChange.send() // without this view doesn't update properly
                            day.messages = (day.messages + [newChatMessage]).sorted(by: { $0.createdAt < $1.createdAt })
                        }
                    }
                }
                else { // Add the day to existing year
                    Task { @MainActor in
                        withAnimation {
                            lastMessageId = rumorNEvent.id
                            self.objectWillChange.send() // without this view doesn't update properly
                            year.days = [ConversationDay(
                                dayId: dayIdFormatter.string(from: messageDate),
                                date: messageDate,
                                messages: [newChatMessage]
                            )] + year.days
                        }
                    }
                }
            }
            else { // add new year, and new day
                Task { @MainActor in
                    withAnimation {
                        lastMessageId = rumorNEvent.id
                        self.objectWillChange.send() // without this view doesn't update properly
                        
                        self.viewState = .ready(
                            (years + [
                            ConversationYear(
                                year: yearId,
                                days: [ConversationDay(
                                    dayId: dayIdFormatter.string(from: messageDate),
                                    date: messageDate,
                                    messages: [newChatMessage]
                            )])]).sorted(by: { $0.year > $1.year })
                        )
                    }
                }
            }
        }
        else { // Add the year and new day
            Task { @MainActor in
                withAnimation {
                    self.objectWillChange.send() // without this view doesn't update properly
                    self.viewState = .ready([
                        ConversationYear(
                            year: yearId,
                            days: [ConversationDay(
                                dayId: dayIdFormatter.string(from: messageDate),
                                date: messageDate,
                                messages: [newChatMessage]
                            )]
                        )
                    ])
                }
            }
        }
        
        return newChatMessage
    }
    
    @MainActor public func sendMessage(_ message: String, quotingNow: NRChatMessage? = nil, replyingNow: NRChatMessage? = nil) async throws {
        if self.conversationVersion == 17 {
            try await self.sendMessage17(message, quotingNow: quotingNow, replyingNow: replyingNow)
        }
        else {
            try await self.sendMessage04(message)
        }
    }
    
    @MainActor private func sendMessage04(_ message: String) async throws {
        guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: ourAccountPubkey) else { throw DMError.PrivateKeyMissing }
        guard let theirPubkey = participants.subtracting([ourAccountPubkey]).first else { throw DMError.Unknown }
        let keys = try Keys(privateKeyHex: privKey)
        let messageDate = Date()
        var nEvent = NEvent(content: message)
        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }
        nEvent.kind = .legacyDirectMessage
        guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: privKey, pubkey: theirPubkey, content: nEvent.content) else {
            L.og.error("🔴🔴 Could encrypt content")
            throw DMError.Unknown
        }
        
        nEvent.content = encrypted
        nEvent.tags.append(NostrTag(["p", theirPubkey]))
        
        if let signedEvent = try? nEvent.sign(keys) {
            Unpublisher.shared.publishNow(signedEvent)
            _ = addToView(signedEvent, keys, messageDate)
            return
        }
        throw DMError.Unknown
    }
    
    @MainActor
    private func sendMessage17(_ message: String, quotingNow quoted: NRChatMessage? = nil, replyingNow replyingTo: NRChatMessage? = nil) async throws {
        guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: ourAccountPubkey), let ourkeys = try? NostrEssentials.Keys(privateKeyHex: privKey) else { throw DMError.PrivateKeyMissing }
        
        
        let recipientPubkeys = participants.subtracting([ourAccountPubkey])
        let content = if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            replaceNsecWithHunter2(message)
        }
        else { message }
        
        var tags: [Tag] = participants.map { Tag(["p", $0]) } // include ourselves for compatibility with 0xChat (seems to ignore .pubkey)
        
        if let quoted {
            tags.append(Tag(["q", quoted.id]))
        }
        
        if let replyingTo {
            tags.append(Tag(["e", replyingTo.id]))
        }
        
        let messageDate = Date()
        let message = NostrEssentials.Event(
            pubkey: ourAccountPubkey,
            content: content,
            kind: 14,
            created_at: Int(messageDate.timeIntervalSince1970),
            tags: tags
        )
        let rumorEvent = createRumor(message) // makes sure sig is removed and adds id
        
        let rumorNEvent = NEvent.fromNostrEssentialsEvent(rumorEvent)
        let addedChatMessage = addToView(rumorNEvent, ourkeys, messageDate)
        
        // Wrap and create send jobs for all receivers (including self)
        for (n, receiverPubkey) in participants.enumerated() {
            // wrap message
            do {
                let giftWrap = try createGiftWrap(rumorEvent, receiverPubkey: receiverPubkey, keys: ourkeys)
                let giftWrapId = giftWrap.fallbackId()
                if receiverPubkey == ourAccountPubkey {
                    // save message to local db and giftwrap to ourselve (relay backup)  (we can't unwrap sent to receipents, can only unwrap received to our pubkey)
                    await bg().perform {
                        _ = Event.saveEvent(event: rumorEvent, wrapId: giftWrapId, context: bg())
                        MessageParser.shared.pendingOkWrapIds.insert(giftWrapId) // When "OK" comes back, "relays" on rumor need to be updated, not on wrap.
                    }
                }

                let relays = await getDMrelays(for: receiverPubkey)
#if DEBUG
                L.og.debug("💌💌 1. (\(n+1)/\(recipientPubkeys.count)) Preparing sendJobs. To: \(nameOrPubkey(receiverPubkey)) relays: \(relays)")
#endif
                

                // If receiver has no relays, use our own relays as fallback for sending
                let relaysWithFallback = if relays.isEmpty {
                    await getDMrelays(for: ourAccountPubkey)
                } else {
                    relays
                }
                
                if relaysWithFallback.isEmpty {
                    addedChatMessage?.dmSendResult[receiverPubkey] = RecipientResult(recipientPubkey: receiverPubkey, relayResults: [:])
                }
                
                sendJobs.append((receiver: receiverPubkey, wrappedEvent: giftWrap, relays: relaysWithFallback))
            }
            catch {
#if DEBUG
                L.og.debug("🔴🔴 💌💌 error while trying to wrap \(error)")
#endif
            }
        }
        
        addedChatMessage?.dmSendResult = sendJobs.reduce(into: [:]) { dmSendJobs, sendJob in
            dmSendJobs[sendJob.receiver] = RecipientResult(
                recipientPubkey: sendJob.receiver,
                relayResults: sendJob.relays.reduce(into: [:]) { relays, relay in
                    relays[relay] = .sending
                }
            )
        }
        
        guard let addedChatMessage else { return }
        let rumorEventId = rumorEvent.fallbackId()
        
        for job in sendJobs {
            sendToDMRelays(receiverPubkey: job.receiver, wrappedEvent: job.wrappedEvent, relays: job.relays, rumorId: rumorEventId, addedChatMessage: addedChatMessage)
        }
    }
    
    // MARK: - File Message Sending (Kind 15)
    
    @Published var isUploadingFile = false
    
    @MainActor
    public func sendFileMessage17(fileURL: URL, mimeType: String, imageDimensions: String? = nil) async throws {
        guard SettingsStore.shared.defaultMediaUploadService.name == BLOSSOM_LABEL else {
            throw DMFileError.blossomNotConfigured
        }
        guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: ourAccountPubkey), let ourkeys = try? NostrEssentials.Keys(privateKeyHex: privKey) else { throw DMError.PrivateKeyMissing }
        guard let blossomServerUrl = SettingsStore.shared.blossomServerList.first, let blossomServer = URL(string: blossomServerUrl) else {
            throw DMFileError.blossomNotConfigured
        }
        
        isUploadingFile = true
        defer { isUploadingFile = false }
        
        // Read and encrypt off the main actor so large attachments don't block the UI.
        let encrypted = try await Task.detached(priority: .userInitiated) {
            let fileData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            return try encryptFileForDM(data: fileData)
        }.value
        
        // 2. Upload encrypted data to Blossom
        let blossomFile = BlossomUploadFile(data: encrypted.encryptedData, contentType: "application/octet-stream")
        let authHeader = try await getBlossomAuthHeader(keys: Keys(privateKeyHex: privKey), blossomFile: blossomFile)
        let downloadUrl = try await blossomUpload(authHeader: authHeader, blossomFile: blossomFile, contentType: "application/octet-stream", blossomServer: blossomServer, timeout: 60.0)
        
        // 3. Build kind 15 rumor tags
        var tags: [Tag] = participants.map { Tag(["p", $0]) }
        tags.append(Tag(["file-type", mimeType]))
        tags.append(Tag(["encryption-algorithm", "aes-gcm"]))
        tags.append(Tag(["decryption-key", encrypted.key.map { String(format: "%02x", $0) }.joined()]))
        tags.append(Tag(["decryption-nonce", encrypted.nonce.map { String(format: "%02x", $0) }.joined()]))
        tags.append(Tag(["x", encrypted.encryptedHash]))
        tags.append(Tag(["ox", encrypted.originalHash]))
        tags.append(Tag(["size", String(encrypted.fileSize)]))
        
        if let imageDimensions {
            tags.append(Tag(["dim", imageDimensions]))
        }
        
        // 4. Create kind 15 rumor event
        let messageDate = Date()
        let message = NostrEssentials.Event(
            pubkey: ourAccountPubkey,
            content: downloadUrl,
            kind: 15,
            created_at: Int(messageDate.timeIntervalSince1970),
            tags: tags
        )
        let rumorEvent = createRumor(message)
        
        let rumorNEvent = NEvent.fromNostrEssentialsEvent(rumorEvent)
        let addedChatMessage = addToView(rumorNEvent, ourkeys, messageDate)
        
        // 5. Gift wrap and send to all participants (same as sendMessage17)
        sendJobs = []
        for (n, receiverPubkey) in participants.enumerated() {
            do {
                let giftWrap = try createGiftWrap(rumorEvent, receiverPubkey: receiverPubkey, keys: ourkeys)
                let giftWrapId = giftWrap.fallbackId()
                if receiverPubkey == ourAccountPubkey {
                    await bg().perform {
                        _ = Event.saveEvent(event: rumorEvent, wrapId: giftWrapId, context: bg())
                        MessageParser.shared.pendingOkWrapIds.insert(giftWrapId)
                    }
                }
                
                let relays = await getDMrelays(for: receiverPubkey)
#if DEBUG
                L.og.debug("📎💌 1. (\(n+1)/\(self.participants.count)) Preparing file sendJobs. To: \(nameOrPubkey(receiverPubkey)) relays: \(relays)")
#endif
                
                let relaysWithFallback = if relays.isEmpty {
                    await getDMrelays(for: ourAccountPubkey)
                } else {
                    relays
                }
                
                if relaysWithFallback.isEmpty {
                    addedChatMessage?.dmSendResult[receiverPubkey] = RecipientResult(recipientPubkey: receiverPubkey, relayResults: [:])
                }
                
                sendJobs.append((receiver: receiverPubkey, wrappedEvent: giftWrap, relays: relaysWithFallback))
            }
            catch {
#if DEBUG
                L.og.debug("🔴🔴 📎💌 error while trying to wrap file message \(error)")
#endif
            }
        }
        
        addedChatMessage?.dmSendResult = sendJobs.reduce(into: [:]) { dmSendJobs, sendJob in
            dmSendJobs[sendJob.receiver] = RecipientResult(
                recipientPubkey: sendJob.receiver,
                relayResults: sendJob.relays.reduce(into: [:]) { relays, relay in
                    relays[relay] = .sending
                }
            )
        }
        
        guard let addedChatMessage else { return }
        let rumorEventId = rumorEvent.fallbackId()
        
        for job in sendJobs {
            sendToDMRelays(receiverPubkey: job.receiver, wrappedEvent: job.wrappedEvent, relays: job.relays, rumorId: rumorEventId, addedChatMessage: addedChatMessage)
        }
    }
    
    @Published var relayLogs: String = ""
    
    @MainActor
    private var nxJobs: [DMSendJob] = []
    
    private func sendToDMRelays(receiverPubkey: String, wrappedEvent: NostrEssentials.Event, relays: Set<String>, rumorId: String, addedChatMessage: NRChatMessage) {
        let nxJob = DMSendJob(
            timeout: 4.0,
            setup: { job in
                MessageParser.shared.okSub
                    .filter { !job.didSucceed && $0.id == wrappedEvent.id }
                    .sink { message in
#if DEBUG
                        L.og.debug("✅✅ 💌💌 3.A message.id: \(message.id) message.relayId: \(message.relay) - receiverPubkey: \(nameOrPubkey(receiverPubkey))")
#endif
                        if let recipientResult = addedChatMessage.dmSendResult[receiverPubkey] {
                            recipientResult.relayResults[message.relay] = DMSendResult.success
                            Task { @MainActor in
                                addedChatMessage.objectWillChange.send()
                            }
                        }
                    }
                    .store(in: &job.subscriptions)
            },
            onTimeout: { job in
                var didActuallyTimeout = false
                if let recipientResult: RecipientResult = addedChatMessage.dmSendResult[receiverPubkey] {
                    for (relay, result) in recipientResult.relayResults {
                        if result != .success {
                            recipientResult.relayResults[relay] = .timeout
                            didActuallyTimeout = true
#if DEBUG
                            L.og.debug("🔴🔴 💌💌 3.B TIMEOUT wrapped.id: \(wrappedEvent.id) receiverPubkey: \(nameOrPubkey(receiverPubkey)) - \(relay)")
#endif
                        }
                    }
                }
                
                guard didActuallyTimeout else { return }
                Task { @MainActor in
                    addedChatMessage.objectWillChange.send()
                }
            },
            onFinally: { job in
                Task { @MainActor in
                    self.nxJobs.removeAll(where: { $0 == job })
                }
            })
        
        Task { @MainActor in
            self.nxJobs.append(nxJob)
            
            for relay in relays {
                if ConnectionPool.shared.connections[relay] != nil {
    #if DEBUG
                    L.og.debug("💌💌 2.A Sending to \(relay) for pubkey: \(nameOrPubkey(receiverPubkey)) - wrapped.id: \(wrappedEvent.id)")
    #endif
                    ConnectionPool.shared.sendMessage(
                        NosturClientMessage(
                            clientMessage: NostrEssentials.ClientMessage(type: .EVENT, event: wrappedEvent),
                            relayType: .WRITE,
                            nEvent: NEvent.fromNostrEssentialsEvent(wrappedEvent)
                        ),
                        relays: [RelayData(read: false, write: true, search: false, auth: false, url: relay, excludedPubkeys: [])]
                    )
                }
                else {
                    if let msg = NostrEssentials.ClientMessage(type: .EVENT, event: wrappedEvent).json() {
    #if DEBUG
                    L.og.debug("💌💌 2.B Sending to ephemeral \(relay) for pubkey: \(nameOrPubkey(receiverPubkey)) - wrapped.id: \(wrappedEvent.id)")
    #endif
                        Task { @MainActor in
                            ConnectionPool.shared.sendEphemeralMessage(
                                msg,
                                relay: relay,
                                write: true
                            )
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    public func fetchNip04DMs() {
        if participants.count == 2, let receiver = participants.subtracting([ourAccountPubkey]).first, !receiver.isEmpty {
            nxReq(
                Filters(
                    authors: [ourAccountPubkey],
                    kinds: [4],
                    tagFilter: TagFilter(tag: "p", values: [receiver]),
                    limit: 999
                ),
                subscriptionId: "DM-S-\(conversationId.prefix(16))-\(conversationId.suffix(16))"
            )
            
            nxReq(
                Filters(
                    authors: [receiver],
                    kinds: [4],
                    tagFilter: TagFilter(tag: "p", values: [ourAccountPubkey]),
                    limit: 999
                ),
                subscriptionId: "DM-R-\(conversationId.prefix(16))-\(conversationId.suffix(16))"
            )
        }
    }
    
    private func fetchDMrelays() {
        let reqFilters = Filters(
            authors: receivers,
            kinds: [10050],
            limit: 199
        )
        nxReq(
            reqFilters,
            subscriptionId: "DM-" + UUID().uuidString.prefix(48),
            relayType: .READ
        )
        nxReq(
            reqFilters,
            subscriptionId: "DM-" + UUID().uuidString.prefix(48),
            relayType: .SEARCH_ONLY
        )
    }
    
    // DM sending queue, status, errors
    
//    private var sendJobs: [String: OutgoingDM] = [:] // rumor.id: sada s
    private var sendErrors: [String: String] = [:] // rumor.id: fsdfdsd
    
    
    @MainActor
    public func markAsRead() {
        self.dmState?.markedReadAt_ = Date.now
//        DataProvider.shared().saveToDisk(.all)
    }
}

enum ConversionVMViewState {
    case initializing
    case loading
    case ready([ConversationYear])
    case timeout
    case error(String)
}

class ConversationYear: Identifiable, Equatable, ObservableObject {
    
    static func == (lhs: ConversationYear, rhs: ConversationYear) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: String { year }
    let year: String
    
    @Published var days: [ConversationDay]
    
    init(year: String, days: [ConversationDay]) {
        self.year = year
        self.days = days
    }
}

class ConversationDay: Identifiable, Equatable, ObservableObject {
    
    static func == (lhs: ConversationDay, rhs: ConversationDay) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: UUID
    let dayId: String // 2025-12-10
    let date: Date
    @Published var messages: [NRChatMessage]
    
    init(dayId: String, date: Date, messages: [NRChatMessage]) {
        self.id = UUID()
        self.dayId = dayId
        self.date = date
        self.messages = messages
    }
}

struct BalloonError: Identifiable, Equatable, Hashable {
    var id: String { messageId + receiverPubkey + relay }
    let messageId: String
    let receiverPubkey: String
    let relay: String
    let errorText: String
}

struct BalloonSuccess: Identifiable, Equatable, Hashable {
    var id: String { messageId + receiverPubkey + relay }
    let messageId: String
    let receiverPubkey: String
    let relay: String
}

public enum DMError: Error {
    case Unknown
    case PrivateKeyMissing
}
