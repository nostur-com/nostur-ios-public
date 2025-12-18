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

class ConversionVM: ObservableObject {
    private var participants: Set<String> // all participants (including sender)
    private var ourAccountPubkey: String {
        didSet {
            self.account = AccountsState.shared.accounts.first(where: { $0.publicKey == ourAccountPubkey })
        }
    }
    public var receivers: Set<String> {
        participants.subtracting([ourAccountPubkey])
    }
    private var conversationId: String
    
    @Published var viewState: ConversionVMViewState = .initializing
    @Published var navigationTitle = "To: ..."
    @Published var receiverContacts: [NRContact] = []
    
    @Published var isAccepted = false {
        didSet {
            let isAccepted = isAccepted
            bg().perform { [weak self] in
                self?.cloudDMState?.accepted = isAccepted
            }
        }
    }
    
    // 0 = NIP-04, 1 = NIP-17
    @Published var conversionVersion: Int = 0
    
    public var account: CloudAccount? = nil
    
    private let dayIdFormatter: DateFormatter
    
    private var subscriptions: Set<AnyCancellable> = []
    
    // bg
    private var cloudDMState: CloudDMState? = nil
    
    init(participants: Set<String>, ourAccountPubkey: String) {
        self.participants = participants
        self.ourAccountPubkey = ourAccountPubkey
        self.conversationId = CloudDMState.getConversationId(for: participants)
        
        let dayIdFormatter = DateFormatter()
        dayIdFormatter.dateFormat = "yyyy-MM-dd"          // note: lowercase yyyy
        dayIdFormatter.locale = Locale(identifier: "en_US_POSIX") // ensures consistent format
        self.dayIdFormatter = dayIdFormatter
    }
    
    private var didLoad = false
    
    @MainActor
    public func load(force: Bool = false) async {
        guard force || !didLoad else { return }
        self.subscriptions.removeAll()
        self.didLoad = true
        self.viewState = .loading
        self.receiverContacts = receivers.map { NRContact.instance(of: $0) }
        self.cloudDMState = await getGroupState()
        self.isAccepted = await withBgContext { _ in
            return self.cloudDMState?.accepted ?? false
        }
//#if DEBUG
//        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
//            guard let account = AccountsState.shared.fullAccounts.first(where: { $0.publicKey == self.ourAccountPubkey }) else {
//                viewState = .error("Missing private key for account: \(self.ourAccountPubkey)")
//                return
//            }
//        }
//        let privateKey = "mock-private-key"
//#else
        guard let account = AccountsState.shared.fullAccounts.first(where: { $0.publicKey == self.ourAccountPubkey }), let privateKey = account.privateKey else {
            viewState = .error("Missing private key for account: \(nameOrPubkey(self.ourAccountPubkey))")
            return
        }
//#endif

        if let cloudDMState { // Should always exists because getGroupState() gets existing or creates new
            let visibleMessages = await getMessages(cloudDMState, keyPair: (publicKey: ourAccountPubkey, privateKey: privateKey))
            
            await self.resolveConversationVersion(participants, messages: visibleMessages)
            
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
            }.sorted(by: { $0.dayId < $1.dayId })
            
            viewState = .ready(days)
        }
        
        self.fetchDMrelays()
        self.listenForNewMessages()
    }
    
    private func listenForNewMessages() {
        Importer.shared.importedDMSub
            .filter { $0.conversationId == self.conversationId }
            .sink { (_, event, nEvent, newDMStateCreated) in
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
    
    private func resolveConversationVersion(_ participants: Set<String>, messages: [NRChatMessage]) async {
        // More than 2 participants = NIP-17
        if participants.count > 2 {
            Task { @MainActor in
                self.conversionVersion = 1 // NIP-17
            }
            return
        }
        
        // Last message is kind 14? = NIP17
        if messages.last?.nEvent.kind == .directMessage {
            Task { @MainActor in
                self.conversionVersion = 1 // NIP-17
            }
            return
        }
        
        // no messages yet, but has DM relay? NIP-17
        if messages.isEmpty, let receiverPubkey = participants.subtracting([ourAccountPubkey]).first {
            let relays = await getDMrelays(for: receiverPubkey)
            if !relays.isEmpty {
                Task { @MainActor in
                    self.conversionVersion = 1 // NIP-17
                }
                return
            }
        }
        
        
        // No indication of NIP-17 support so fall back to NIP-04
        Task { @MainActor in
            self.conversionVersion = 0 // NIP-04
        }
        return
    }
    
    @MainActor
    public func reload(participants: Set<String>, ourAccountPubkey: String) async {
        self.participants = participants
        self.ourAccountPubkey = ourAccountPubkey
        self.conversationId = CloudDMState.getConversationId(for: participants)
        
        await self.load(force: true)
    }
    
    private func getGroupState() async -> CloudDMState {
        // Get existing or create new
        let participants = self.participants
        return await withBgContext { bgContext in
            if let groupDMState = CloudDMState.fetchByParticipants(participants: participants, andAccountPubkey: self.ourAccountPubkey, context: bgContext) {
                return groupDMState
            }
            let newDMState = CloudDMState.create(accountPubkey: self.ourAccountPubkey, participants: participants, context: bgContext)
            newDMState.accepted = true
            newDMState.initiatorPubkey_ = self.ourAccountPubkey
            return newDMState
        }
    }
    
    private func getMessages(_ cloudDMState: CloudDMState, keyPair: (publicKey: String, privateKey: String)) async -> [NRChatMessage] {
        
        let dmEvents = await withBgContext { bgContext in
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.predicate = NSPredicate(format: "groupId = %@ AND kind IN {4,14}", cloudDMState.conversationId)
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
        if lastAddedIds.contains(rumorNEvent.id) {
            // rumorId (if added from local submit, don't add again when receiving from relay)
#if DEBUG
            L.og.debug("💌💌 Don't add to view again rumor.id: \(rumorNEvent.id) ")
#endif
            return nil
        }
        lastAddedIds.insert(rumorNEvent.id)
        
        let keyPair: (publicKey: String, privateKey: String)? = if let ourkeys {
            (publicKey: ourkeys.publicKeyHex, privateKey: ourkeys.privateKeyHex)
        } else {
            nil
        }
        
        let newChatMessage = NRChatMessage(
            nEvent: rumorNEvent,
            keyPair: keyPair
        )
        
        if case .ready(let days) = self.viewState {
            if let day = days.first(where: { $0.dayId == dayIdFormatter.string(from: messageDate) }) {
                Task { @MainActor in
                    withAnimation {
                        day.messages.append(
                            newChatMessage
                        )
                    }
                }
            }
            else {
                Task { @MainActor in
                    withAnimation {
                        self.viewState = .ready(days + [ConversationDay(
                            dayId: dayIdFormatter.string(from: messageDate),
                            date: messageDate,
                            messages: [newChatMessage]
                        )])
                    }
                }
            }
        }
        else {
            Task { @MainActor in
                withAnimation {
                    self.viewState = .ready([ConversationDay(
                        dayId: dayIdFormatter.string(from: messageDate),
                        date: messageDate,
                        messages: [newChatMessage]
                    )])
                }
            }
        }
        
        return newChatMessage
    }
    
    @MainActor public func sendMessage(_ message: String) async throws {
        if self.conversionVersion == 1 {
            try await self.sendMessage17(message)
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
    private func sendMessage17(_ message: String) async throws {
        guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: ourAccountPubkey), let ourkeys = try? NostrEssentials.Keys(privateKeyHex: privKey) else { throw DMError.PrivateKeyMissing }
        
        
        let recipientPubkeys = participants.subtracting([ourAccountPubkey])
        let content = if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            replaceNsecWithHunter2(message)
        }
        else { message }
        
        let messageDate = Date()
        let message = NostrEssentials.Event(
            pubkey: ourAccountPubkey,
            content: content,
            kind: 14,
            created_at: Int(messageDate.timeIntervalSince1970),
            tags: recipientPubkeys.map { Tag(["p", $0]) } // not ourselves
        )
        let rumorEvent = createRumor(message) // makes sure sig is removed and adds id
        
        let rumorNEvent = NEvent.fromNostrEssentialsEvent(rumorEvent)
        let addedChatMessage = addToView(rumorNEvent, ourkeys, messageDate)
        
        // Wrap and create send jobs for all receivers (including self)
        for (n, receiverPubkey) in participants.enumerated() {
            // wrap message
            do {
                let giftWrap = try createGiftWrap(rumorEvent, receiverPubkey: receiverPubkey, keys: ourkeys)
                if receiverPubkey == ourAccountPubkey {
                    // save message to local db and giftwrap to ourselve (relay backup)  (we can't unwrap sent to receipents, can only unwrap received to our pubkey)
                    await bg().perform {
                        _ = Event.saveEvent(event: rumorEvent, wrapId: giftWrap.id, context: bg())
                        MessageParser.shared.pendingOkWrapIds.insert(giftWrap.id) // When "OK" comes back, "relays" on rumor need to be updated, not on wrap.
                    }
                }

                let relays = await getDMrelays(for: receiverPubkey)
#if DEBUG
                L.og.debug("💌💌 1. (\(n+1)/\(recipientPubkeys.count)) Preparing sendJobs. To: \(nameOrPubkey(receiverPubkey)) relays: \(relays)")
#endif
                
                if relays.isEmpty {
                    addedChatMessage?.dmSendResult[receiverPubkey] = RecipientResult(recipientPubkey: receiverPubkey, relayResults: [:])
                }
                
                sendJobs.append((receiver: receiverPubkey, wrappedEvent: giftWrap, relays: relays))
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
        
        for job in sendJobs {
            sendToDMRelays(receiverPubkey: job.receiver, wrappedEvent: job.wrappedEvent, relays: job.relays, rumorId: rumorEvent.id, addedChatMessage: addedChatMessage)
        }
    }
    
    @Published var relayLogs: String = ""
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
                Task {
                    self.nxJobs.removeAll(where: { $0 == job })
                }
            })
        
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
    
    private func fetchDMs() {
        if participants.count == 2, let receiver = participants.subtracting([ourAccountPubkey]).first, !receiver.isEmpty {
            nxReq(
                Filters(
                    authors: [ourAccountPubkey],
                    kinds: [4],
                    tagFilter: TagFilter(tag: "p", values: [receiver]),
                    limit: 999
                ),
                subscriptionId: "DM-S"
            )
            
            nxReq(
                Filters(
                    authors: [receiver],
                    kinds: [4],
                    tagFilter: TagFilter(tag: "p", values: [ourAccountPubkey]),
                    limit: 999
                ),
                subscriptionId: "DM-R"
            )
        }
        
        
        
        // Make sure main giftwraps receive subscription is active
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
            relayType: .SEARCH
        )
    }
    
    // DM sending queue, status, errors
    
//    private var sendJobs: [String: OutgoingDM] = [:] // rumor.id: sada s
    private var sendErrors: [String: String] = [:] // rumor.id: fsdfdsd
    
    
    @MainActor
    public func markAsRead() {
        bg().perform { [weak self] in
            self?.cloudDMState?.markedReadAt_ = Date.now
            DataProvider.shared().saveToDisk(.bgContext)
        }
    }
}

enum ConversionVMViewState {
    case initializing
    case loading
    case ready([ConversationDay])
    case timeout
    case error(String)
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
