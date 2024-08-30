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
        return String("-DB-CHAT-" + String(bytes: sha256data.bytes).prefix(40))
    }()
    
    private var subscriptions = Set<AnyCancellable>()
    private var backlog = Backlog()
    
    @Published public var messages: [NRChatMessage] = []
    
    @MainActor
    public func start(aTag: String) throws {
        self.aTag = aTag
       
        let elements = aTag.split(separator: ":")
        guard elements.count >= 3 else {
            self.state = .error("3 or less parts")
            throw Errors.invalidATagError("3 or less parts")
        }
        guard let kindString = elements[safe: 0], let kind = Int64(kindString) else {
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
        self.listenForChats()
        self.listenForBlocks()
        self.fetchChatHistory()
        self.updateLiveSubscription()
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
                           subscriptionId: subId,
                           filters: [Filters(
                            kinds: [1311,9735],
                            tagFilter: TagFilter(tag: "a", values: [aTag]),
                            since: (Int(Date.now.timeIntervalSince1970) - 60)
                           )]
            ).json() {
            req(cm, activeSubscriptionId: subId)
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
                
                if (state == .initializing || state == .loading) && message.type == .EOSE, let subscriptionId = message.subscriptionId, subscriptionId == subId {
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
                guard event.tags.first(where: { $0.type == "a" && $0.value == aTag }) != nil else { return }

                if self.state != .ready {
                    self.objectWillChange.send()
                    self.state = .ready
                }
                
                #if DEBUG
                L.nests.debug("Chat message/zap received \(event.kind == .zapNote ? "ZAP" : "MESSAGE"): \(event.content)")
                #endif
                // TODO: Filter WoT before adding? or already filtered in MessageParser?
                bg().perform {
                    let nrChat: NRChatMessage = NRChatMessage(nEvent: event)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        let messages: [NRChatMessage] = (self.messages + [nrChat]).sorted(by: { $0.createdAt > $1.createdAt })
                        self.objectWillChange.send()
                        self.messages = messages
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    private func listenForBlocks() {
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                withAnimation {
                    self.messages = self.messages.filter { !blockedPubkeys.contains($0.pubkey) }
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
