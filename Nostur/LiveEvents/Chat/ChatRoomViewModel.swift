//
//  ChatRoomViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/07/2024.
//

import SwiftUI
import NostrEssentials
import CryptoKit
import Combine

class ChatRoomViewModel: ObservableObject {
    
    enum Errors: Error {
        case invalidATagError(String)
    }
    
    @Published var state: State = .initializing
    
    private var aTag: String?
    private var pubkey: String?
    private var dTag: String?
    
    private lazy var subId: String = {
        guard let pubkey, let dTag else { return "-DB-CHAT-??" }
        let sha256data = SHA256.hash(data: "1311-\(pubkey)-\(dTag)".data(using: .utf8)!)
        return String("-DB-CHAT-" + String(bytes: sha256data.bytes).prefix(32))
    }()
    
    private lazy var realTimeSubId: String = {
        guard let pubkey, let dTag else { return "-DB-1311-9735-??" }
        let sha256data = SHA256.hash(data: "1311-\(pubkey)-\(dTag)".data(using: .utf8)!)
        return String("-DB-1311-9735-" + String(bytes: sha256data.bytes).prefix(32))
    }()
    
    private var subscriptions = Set<AnyCancellable>()
//    private var backlog = Backlog()
    
    @Published public var messages: [ChatRowContent] = []
    @Published public var topZaps: [NRChatConfirmedZap] = []
    private var bgMessages: [ChatRowContent] = []
    
    private var renderMessages = PassthroughSubject<Void, Never>()
    private var fetchMissingPs = PassthroughSubject<Void, Never>()
    private var alreadyFetchedMissingPs: Set<String> = []
    
    private var didStart = false
    
    @MainActor
    public func start(aTag: String) throws {
        guard !didStart else { return }
        self.didStart = true
#if DEBUG
        L.og.debug("vm.start()")
#endif
        self.aTag = aTag
       
        let elements = aTag.split(separator: ":")
        guard elements.count >= 3 else {
            self.state = .error("Error loading room")
            throw Errors.invalidATagError("3 or less parts")
        }
        guard let kindString = elements[safe: 0], let _ = Int64(kindString) else {
            self.state = .error("no kind")
            throw Errors.invalidATagError("no kind")
        }
        guard let pubkey = elements[safe: 1] else {
            self.state = .error("no pubkey")
            throw Errors.invalidATagError("no pubkey")
        }
        guard let definition = elements[safe: 2] else { 
            self.state = .error("no dTag")
            throw Errors.invalidATagError("no dTag")
        }
        
        self.pubkey = String(pubkey)
        self.dTag = String(definition)
        
        renderMessages
            .debounce(for: .seconds(0.25), scheduler: RunLoop.main)
            .sink { [weak self] in
                if let messages = self?.bgMessages {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        withAnimation {
                            if self.state != .ready {
                                self.state = .ready
                            }
                            self.messages = messages
                        }
                    }
                }
            }
            .store(in: &subscriptions)
        
        fetchMissingPs
            .debounce(for: .seconds(3.5), scheduler: RunLoop.main)
            .sink { [weak self] in
                if let messages = self?.bgMessages {
                    let allMissingPs: Set<String> = messages.map { $0.missingPs }.count > 0 ? Set(messages.flatMap(\.missingPs)) : []
                    let missingPsToFetch: Set<String> = allMissingPs.subtracting(self?.alreadyFetchedMissingPs ?? [])
#if DEBUG
                    L.og.debug("Fetching missingPs: \(missingPsToFetch)")
#endif
                    QueuedFetcher.shared.enqueue(pTags: missingPsToFetch)
                    self?.alreadyFetchedMissingPs.formUnion(missingPsToFetch)
                }
            }
            .store(in: &subscriptions)
        
        self.listenForChats()
        self.listenForBlocks()
        self.fetchFromDB { [weak self] in
            self?.fetchChatHistory()
        }
        self.updateLiveSubscription()
    }
    
    private func fetchFromDB(_ onComplete: (() -> ())? = nil) {
        guard let aTag else { return }
        let blockedPubkeys = blocks()
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind IN {1311,9735} AND otherAtag == %@ AND NOT pubkey IN %@", aTag, blockedPubkeys)
        
        let bgContext = bg()
        bgContext.perform { [weak self]  in
            guard let self else { return }
            
            guard let events = try? bgContext.fetch(fr) else { return }
                        
            let rows: [ChatRowContent] = events
                .filter { $0.inWoT }
                .compactMap { event in
                let row: ChatRowContent? = if event.kind == 9735, let nZapRequest = Event.extractZapRequest(tags: event.tags()) {
                    ChatRowContent.chatConfirmedZap(
                        NRChatConfirmedZap(
                            id: event.id,
                            zapRequestId: nZapRequest.id,
                            zapRequestPubkey: nZapRequest.publicKey,
                            zapRequestCreatedAt: Date(
                                timeIntervalSince1970: Double(nZapRequest.createdAt.timestamp)
                            ),
                            amount: Int64(event.naiveSats),
                            nxEvent: NXEvent(pubkey: event.pubkey, kind: Int(event.kind)),
                            content: NRContentElementBuilder.shared.buildElements(input: nZapRequest.content, fastTags: nZapRequest.fastTags, primaryColor: Themes.default.theme.primary).0,
                            via: via(nZapRequest)
                        )
                    )
                }
                else if event.kind != 9735 {
                    ChatRowContent.chatMessage(NRChatMessage(nEvent: event.toNEvent()))
                }
                else {
                    nil
                }
                return row
            }

            self.bgMessages = rows
            self.fetchMissingPs.send()
            self.renderMessages.send()
            self.updateTopZaps()
            onComplete?()
        }
    }
    
    // Fetch past messages
    private func fetchChatHistory(limit: Int = 300) {
        guard let aTag else { return }
        
        if let cm = NostrEssentials
            .ClientMessage(type: .REQ,
                           subscriptionId: "-DB-CHATHIST",
                           filters: [Filters(
                            kinds: [1311,9735],
                            tagFilter: TagFilter(tag: "a", values: [aTag]),
                            limit: limit
                           )]
            ).json() {
            req(cm)
        }
    }
    
    // Realtime for future messages
    public func updateLiveSubscription() {
        guard let aTag else { return }

        if let cm = NostrEssentials
            .ClientMessage(type: .REQ,
                           subscriptionId: realTimeSubId,
                           filters: [Filters(
                            kinds: [1311,9735],
                            tagFilter: TagFilter(tag: "a", values: [aTag]),
                            since: (Int(Date.now.timeIntervalSince1970) - 60)
                           )]
            ).json() {
            req(cm, activeSubscriptionId: realTimeSubId)
        }
    }
    
    @MainActor
    public func closeLiveSubscription() {
        guard pubkey != nil, dTag != nil else { return }
        req(NostrEssentials.ClientMessage(type: .CLOSE, subscriptionId: subId).json()!)
    }    
    
    private func listenForChats() {
        guard let aTag else { return }
        receiveNotification(.receivedMessage)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let message = notification.object as! RelayMessage
                
                if (state == .initializing || state == .loading) && message.type == .EOSE, let subscriptionId = message.subscriptionId, (subscriptionId == subId || subscriptionId == realTimeSubId) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.objectWillChange.send()
                        self.state = .ready
                    }
                    return
                }
                guard let event = message.event else { return }
                guard !blocks().contains(event.publicKey) else { return }
                guard event.kind == .chatMessage || event.kind == .zapNote else { return }
                guard event.inWoT else { return }
                guard event.tags.first(where: { $0.type == "a" && $0.value == aTag }) != nil else { return }

                if self.state != .ready {
                    self.objectWillChange.send()
                    self.state = .ready
                }
                
                // TODO: check zapRequest.pubkey for blocks(), or maybe "P" (not "p")
                
#if DEBUG
                L.og.debug("Chat message/zap received \(event.kind == .zapNote ? "ZAP" : "MESSAGE"): \(event.content)")
#endif

                bg().perform {
                    let confirmedZap: ChatRowContent = if event.kind == .zapNote, let nZapRequest = Event.extractZapRequest(tags: event.tags) {
                        ChatRowContent.chatConfirmedZap(
                            NRChatConfirmedZap(
                                id: event.id,
                                zapRequestId: nZapRequest.id,
                                zapRequestPubkey: nZapRequest.publicKey,
                                zapRequestCreatedAt: Date(
                                    timeIntervalSince1970: Double(nZapRequest.createdAt.timestamp)
                                ),
                                amount: Int64(event.naiveSats),
                                nxEvent: NXEvent(pubkey: event.publicKey, kind: event.kind.id),
                                content: NRContentElementBuilder.shared.buildElements(input: nZapRequest.content, fastTags: nZapRequest.fastTags, primaryColor: Themes.default.theme.primary).0,
                                via: via(nZapRequest)
                            )
                        )
                    }
                    else {
                        ChatRowContent.chatMessage(NRChatMessage(nEvent: event))
                    }
                    if let index = self.bgMessages.firstIndex(where: { row in
                        if case .chatPendingZap(let pendingZap) = row, pendingZap.id == confirmedZap.id {
                            return true
                        }
                        if case .chatConfirmedZap(let existingZap) = row, existingZap.id == confirmedZap.id {
                            return true
                        }
                        return false
                    }) {
                        self.bgMessages[index] = confirmedZap
                    }
                    else {
                        let messages: [ChatRowContent] = (self.bgMessages + [confirmedZap]).sorted(by: { $0.createdAt > $1.createdAt })
                        self.bgMessages = messages
                    }
                    self.fetchMissingPs.send()
                    self.renderMessages.send()
                    self.updateTopZaps()
                }
            }
            .store(in: &subscriptions)
        
        receiveNotification(.receivedPendingZap)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let pendingZap = notification.object as! NRChatPendingZap
                guard aTag == pendingZap.aTag else { return }
                
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    self.bgMessages = (self.bgMessages + [ChatRowContent.chatPendingZap(pendingZap)]).sorted(by: { $0.createdAt > $1.createdAt })
                    self.renderMessages.send()
                }
            }
            .store(in: &subscriptions)
    }
    
    private func listenForBlocks() {
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                let blockedPubkeys = notification.object as! Set<String>
                bg().perform { [weak self] in
                    guard let self else { return }
                    self.bgMessages = self.bgMessages.filter { !blockedPubkeys.contains($0.pubkey) }
                    self.renderMessages.send()
                }
            }
            .store(in: &subscriptions)
    }
    
    enum State: Equatable {
        case initializing
        case loading
        case ready
        case timeout
        case error(String)
    }
    
    // We are not storing chats in DB. So when we close and reopen chat and try
    // to fetch chats again they wont be parsed because they will be considered already parsed
    // by Importer.shared.existingIds. So we remove them so we can parse them again.
    @MainActor
    public func removeChatsFromExistingIdsCache() {
        let ids = self.messages.map { $0.id }
        bg().perform {
            for id in ids {
                Importer.shared.existingIds[id] = nil
            }
        }
    }
    
    private func updateTopZaps() {
        let bgContext = bg()
        bgContext.perform { [weak self] in
            guard let self else { return }
            
            let combinedZaps = self.bgMessages
                .compactMap { content in
                    if case .chatConfirmedZap(let zap) = content {
                        return zap
                    }
                    return nil
                }
                .reduce(into: [String: NRChatConfirmedZap]()) { result, zap in
                    if let existing = result[zap.zapRequestPubkey] {
                        // Combine amounts for same pubkey
                        result[zap.zapRequestPubkey] = NRChatConfirmedZap(
                            id: existing.id,
                            zapRequestId: existing.zapRequestId,
                            zapRequestPubkey: existing.zapRequestPubkey,
                            zapRequestCreatedAt: existing.zapRequestCreatedAt,
                            amount: existing.amount + zap.amount,
                            nxEvent: existing.nxEvent,
                            content: existing.content
                        )
                    } else {
                        result[zap.zapRequestPubkey] = zap
                    }
                }
                .values
                .sorted { $0.amount > $1.amount }
                .prefix(4)
                .map { $0 }
            
            DispatchQueue.main.async { [weak self] in
                self?.topZaps = combinedZaps
            }
        }
    }
    
    deinit {
        
        // cant use removeChatsFromExistingIdsCache() and closeLiveSubscription() so copy paste and fix later
        guard pubkey != nil, dTag != nil else { return }
        req(NostrEssentials.ClientMessage(type: .CLOSE, subscriptionId: subId).json()!)

        let ids = self.messages.map { $0.id }
        bg().perform {
            for id in ids {
                Importer.shared.existingIds[id] = nil
            }
        }
    }
}

enum NRChatRow: Identifiable {
    case message(NRChatMessage)
    case zap(NRZap)
    
    var id: String {
        switch self {
        case .message(let nrChatMessage):
            return nrChatMessage.id
        case .zap(let nrZap):
            return nrZap.id
        }
    }
    
    var createdAt: Date {
        switch self {
        case .message(let nrChatMessage):
            return nrChatMessage.createdAt
        case .zap(let nrZap):
            return nrZap.createdAt
        }
    }
}

class NRZap: ObservableObject {
    init(nEvent: NEvent) {
        
    }
    
    var id = "1"
    var createdAt: Date { .now }
}

func via(_ nEvent: NEvent) -> String? {
    if let via = nEvent.fastTags.first(where: { $0.0 == "client" && $0.1.prefix(6) != "31990:" })?.1 {
        return via
    }
    else if let proxy = nEvent.fastTags.first(where: { $0.0 == "proxy" && $0.2 != nil })?.2 {
        return String(format: "%@ (proxy)", proxy)
    }
    return nil
}
