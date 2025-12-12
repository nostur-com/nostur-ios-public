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
    private var ourAccountPubkey: String {
        didSet {
            self.account = AccountsState.shared.accounts.first(where: { $0.publicKey == ourAccountPubkey })
        }
    }
    private var receivers: Set<String> {
        participants.subtracting([ourAccountPubkey])
    }
    
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
    
    public var account: CloudAccount? = nil
    
    
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
            viewState = .error("Missing private key for account: \(self.ourAccountPubkey)")
            return
        }
//#endif

        if let cloudDMState {
            let visibleMessages = await getMessages(cloudDMState, keyPair: (publicKey: ourAccountPubkey, privateKey: privateKey))
            
            let calendar = Calendar.current
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"          // note: lowercase yyyy
            formatter.locale = Locale(identifier: "en_US_POSIX") // ensures consistent format
            formatter.timeZone = TimeZone(secondsFromGMT: 0)      // optional: use UTC
            
            var messagesByDay: [Date: [NRChatMessage]] {
                return Dictionary(grouping: visibleMessages) { nrChatMessage in
                    calendar.startOfDay(for: nrChatMessage.createdAt)
                }
            }
            
            let days = messagesByDay.map { (date, messages) in
                ConversationDay(
                    dayId: formatter.string(from: date),
                    date: date,
                    messages: messages // .sorted(by: { $0.createdAt < $1.createdAt })
                )
            }.sorted(by: { $0.id < $1.id })
            
            viewState = .ready(days)
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
    
    @MainActor
    public func sendMessage(_ message: String) async throws {
        guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: ourAccountPubkey), let ourkeys = try? NostrEssentials.Keys(privateKeyHex: privKey) else { throw DMError.PrivateKeyMissing }
        
        
        let recipientPubkeys = participants.subtracting([ourAccountPubkey])
        let content = message
        let message = NostrEssentials.Event(
            pubkey: ourAccountPubkey,
            content: content,
            kind: 14,
            created_at: Int(Date().timeIntervalSince1970),
            tags: recipientPubkeys.map { Tag(["p", $0]) }
        )
        let rumorEvent = createRumor(message) // makes sure sig is removed and adds id
        
        // save message to local db and giftwrap to ourselve (relay backup)  (we can't unwrap sent to receipents, can only unwrap received to our pubkey)
        let giftWrap = try createGiftWrap(rumorEvent, receiverPubkey: ourAccountPubkey, keys: ourkeys)
        await bg().perform {
            Event.saveEvent(event: rumorEvent, wrapId: giftWrap.id, context: bg())
        }
        let relays = await getDMrelays(for: ourAccountPubkey)
        // send to to relays..
        
        
        
        // send to other participants
        var sendJobs: [(receiver: String, wrappedEvent: NostrEssentials.Event, relays: Set<String>?)]
        
        // Wrap and send to receiver DM relays
        for receiverPubkey in recipientPubkeys {
            // wrap message
            do {
                let giftWrap = try createGiftWrap(rumorEvent, receiverPubkey: receiverPubkey, keys: ourkeys)
                let relays = await getDMrelays(for: receiverPubkey)
                // send to to relays..
//                sendJobs.append((receiver: receiverPubkey, wrappedEvent: giftWrap, relays: relays))
            }
            catch {
                
            }
        }
        
//        var results = []
//        for job in sendJobs {
//            results.append(async let sendToDMRelays(job.wrappedEvent, relays: job.relays))
//        }
//        async let a = taskA()
//        async let b = taskB()
//
//        await print(a + b)
    }
    
    private func sendToDMRelays(_ wrappedEvent: NostrEssentials.Event, relays: Set<String>) async throws {
        
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
    
    // DM sending queue, status, errors
    
    private var sendJobs: [String: OutgoingDM] = [:] // rumor.id: sada s
    private var sendErrors: [String: String] = [:] // rumor.id: fsdfdsd
}

public enum DMError: Error {

    case PrivateKeyMissing
}

enum ConversionVMViewState {
    case initializing
    case loading
    case ready([ConversationDay])
    case timeout
    case error(String)
}

struct ConversationDay: Identifiable, Hashable, Equatable {
    var id: String { dayId }
    let dayId: String // 2025-12-10
    let date: Date
    let messages: [NRChatMessage]
}

func fetchDMrelays(for pubkeys: Set<String>) {
    
}

class OutgoingDM: ObservableObject {
    let nrChatMessage: NRChatMessage // rumor
    init(nrChatMessage: NRChatMessage) {
        self.nrChatMessage = nrChatMessage
    }
    
}

func getDMrelays(for pubkey: String) async -> Set<String>? {
    let relays: Set<String>? = await withBgContext { bgContext in
        if let dmRelaysEvent = Event.fetchEventsBy(pubkey: pubkey, andKind: 10050, context: bgContext).first {
            let relays = dmRelaysEvent.fastTags.filter { $0.0 == "relay" }
                .compactMap { $0.1 }
                .map { normalizeRelayUrl($0) }
            if !relays.isEmpty {
                return Set(relays)
            }
            return nil
        }
        return nil
    }
    return relays
}

