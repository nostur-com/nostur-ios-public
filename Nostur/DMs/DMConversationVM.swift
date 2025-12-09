//
//  DMConversationVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/12/2025.
//

import SwiftUI
import CoreData
import NostrEssentials

class ConversionVM: ObservableObject {
    private var participants: Set<String> // all participants (including sender)
    private var ourAccountPubkey: String
    private var receivers: Set<String> {
        participants.subtracting([ourAccountPubkey])
    }
    
    @Published var viewState: ConversionVMViewState = .initializing
    
    // bg
    private var cloudDMState: CloudDMState? = nil
    
    init(participants: Set<String>, ourAccountPubkey: String) {
        self.participants = participants
        self.ourAccountPubkey = ourAccountPubkey
    }
    
    private var didLoad = false
    
    @MainActor
    public func load(force: Bool = false) async {
        guard force || !didLoad else { return }
        self.didLoad = true
        self.viewState = .loading
        self.cloudDMState = await getGroupState()
        guard let account = AccountsState.shared.fullAccounts.first(where: { $0.publicKey == self.ourAccountPubkey }), let privateKey = account.privateKey else {
            viewState = .error("Missing private key for account: \(self.ourAccountPubkey)")
            return
        }
        
        if let cloudDMState {
            let visibleMessages = await getMessages(cloudDMState, keyPair: (publicKey: ourAccountPubkey, privateKey: privateKey))
            viewState = .ready(visibleMessages)
        }
        
        self.fetchDMrelays()
    }
    
    @MainActor
    public func reload(participants: Set<String>, ourAccountPubkey: String) async {
        self.participants = participants
        self.ourAccountPubkey = ourAccountPubkey
        await self.load(force: true)
    }
    
    private func getGroupState() async -> CloudDMState {
        // Get existing or create new
        let participants = self.participants
        return await withBgContext { bgContext in
            if let groupDMState = CloudDMState.fetchByParticipants(participants: participants, andAccountPubkey: self.ourAccountPubkey, context: bgContext) {
                return groupDMState
            }
            return CloudDMState.create(accountPubkey: self.ourAccountPubkey, participants: participants, context: bgContext)
        }
    }
    
    private func getMessages(_ cloudDMState: CloudDMState, keyPair: (publicKey: String, privateKey: String)) async -> [NRChatMessage] {
        
        let dmEvents = await withBgContext { bgContext in
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.predicate = NSPredicate(format: "groupId = %@ AND kind IN {4,14}", cloudDMState.conversationId)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            
            
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
    
    private func sendMessage(_ message: String, ourkeys: Keys) {
        let recipientPubkeys = participants.subtracting([ourAccountPubkey])
        let content = message
        var messageEvent =  NostrEssentials.Event(
            pubkey: ourAccountPubkey,
            content: content,
            kind: 14,
            created_at: Int(Date().timeIntervalSince1970),
            tags: []
        )
        
        // Wrap and send to receiver DM relays, also our own. (we can't unwrap sent, only received to our pubkey)
        for receiverPubkey in participants {
            // wrap message
            messageEvent.tags = recipientPubkeys.map { Tag(["p", $0]) }
            do {
                let giftWrap = try createGiftWrap(messageEvent, receiverPubkey: receiverPubkey, keys: ourkeys)
                sendToDMRelay(giftWrap)
            }
            catch {
                
            }
        }
    }
    
    private func sendToDMRelay(_ wrappedEvent: NostrEssentials.Event) {
        
    }
    
    private func fetchDMs() {
        if participants.count == 2, let receiver = participants.subtracting([ourAccountPubkey]).first {
            nxReq(
                Filters(
                    authors: [ourAccountPubkey],
                    kinds: [4],
                    tagFilter: TagFilter(tag: "p", values: [receiver]),
                    limit: 1000
                ),
                subscriptionId: "DM-S"
            )
            
            nxReq(
                Filters(
                    authors: [receiver],
                    kinds: [4],
                    tagFilter: TagFilter(tag: "p", values: [ourAccountPubkey]),
                    limit: 1000
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
            limit: 200
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
}

enum ConversionVMViewState {
    case initializing
    case loading
    case ready([NRChatMessage])
    case timeout
    case error(String)
}

func fetchDMrelays(for pubkeys: Set<String>) {
    
}

func getDMrelay(for pubkey: String) {
    
}
