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
    
    private let dayIdFormatter: DateFormatter
    
    
    // bg
    private var cloudDMState: CloudDMState? = nil
    
    init(participants: Set<String>, ourAccountPubkey: String) {
        self.participants = participants
        self.ourAccountPubkey = ourAccountPubkey
        
        let dayIdFormatter = DateFormatter()
        dayIdFormatter.dateFormat = "yyyy-MM-dd"          // note: lowercase yyyy
        dayIdFormatter.locale = Locale(identifier: "en_US_POSIX") // ensures consistent format
        dayIdFormatter.timeZone = TimeZone(secondsFromGMT: 0)      // optional: use UTC
        self.dayIdFormatter = dayIdFormatter
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
    
    
    
    private var sendJobs: [(receiver: String, wrappedEvent: NostrEssentials.Event, relays: Set<String>?)] = []
    @Published var balloonErrors: [BalloonError] = []
    @Published var balloonSuccesses: [BalloonSuccess] = []
    
    @MainActor
    public func sendMessage(_ message: String) async throws {
        guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: ourAccountPubkey), let ourkeys = try? NostrEssentials.Keys(privateKeyHex: privKey) else { throw DMError.PrivateKeyMissing }
        
        
        let recipientPubkeys = participants.subtracting([ourAccountPubkey])
        let content = message
        let messageDate = Date()
        let message = NostrEssentials.Event(
            pubkey: ourAccountPubkey,
            content: content,
            kind: 14,
            created_at: Int(messageDate.timeIntervalSince1970),
            tags: recipientPubkeys.map { Tag(["p", $0]) }
        )
        let rumorEvent = createRumor(message) // makes sure sig is removed and adds id
        
        // add to view
        if case .ready(let days) = self.viewState {
            let newChatMessage = NRChatMessage(
                nEvent: NEvent.fromNostrEssentialsEvent(rumorEvent),
                keyPair: (publicKey: ourkeys.publicKeyHex, privateKey: ourkeys.privateKeyHex)
            )
            if let day = days.first(where: { $0.dayId == dayIdFormatter.string(from: messageDate) }) {
                withAnimation {
                    day.messages.append(
                        newChatMessage
                    )
                }
            }
            else {
                withAnimation {
                    self.viewState = .ready(days + [ConversationDay(
                        dayId: dayIdFormatter.string(from: messageDate),
                        date: messageDate,
                        messages: [newChatMessage]
                    )])
                }
            }
        }
        
        // save message to local db and giftwrap to ourselve (relay backup)  (we can't unwrap sent to receipents, can only unwrap received to our pubkey)
        let giftWrap = try createGiftWrap(rumorEvent, receiverPubkey: ourAccountPubkey, keys: ourkeys)
        await bg().perform {
            Event.saveEvent(event: rumorEvent, wrapId: giftWrap.id, context: bg())
        }
        let relays = await getDMrelays(for: ourAccountPubkey)
        
        // send to to relays..
#if DEBUG
        L.og.debug("💌💌 1. Sending to own relays: \(relays)")
#endif
        
        
        
        // send to other participants
        
        // Wrap and send to receiver DM relays
        for (n, receiverPubkey) in recipientPubkeys.enumerated() {
            // wrap message
            do {
                let giftWrap = try createGiftWrap(rumorEvent, receiverPubkey: receiverPubkey, keys: ourkeys)
                let relays = await getDMrelays(for: receiverPubkey)
                // send to to relays..
#if DEBUG
                L.og.debug("💌💌 2. (\(n+1)/\(recipientPubkeys.count)) Sending to \(receiverPubkey) relays: \(relays)")
#endif
                
                if relays.isEmpty {
                    balloonErrors.append(BalloonError(messageId: rumorEvent.id, receiverPubkey: receiverPubkey, relay: "Missing: ", errorText: "relays for \(receiverPubkey)"))
                }
                
                sendJobs.append((receiver: receiverPubkey, wrappedEvent: giftWrap, relays: relays))
            }
            catch {
#if DEBUG
                L.og.debug("🔴🔴 💌💌 error while trying to wrap \(error)")
#endif
            }
        }
        
//        var results = []
        for job in sendJobs {
            try await sendToDMRelays(receiverPubkey: job.receiver, wrappedEvent: job.wrappedEvent, relays: relays, rumorId: rumorEvent.id)
        }

    }
    
    @Published var relayLogs: String = ""
    
    private func sendToDMRelays(receiverPubkey: String, wrappedEvent: NostrEssentials.Event, relays: Set<String>, rumorId: String) async throws {
//        if ConnectionPool.shared.connections
//        ConnectionPool.shared.sendEphemeralMessage(
//            RM.getEvent(id: eventId, subscriptionId: taskId),
//            relay: relay
//        )
        
        // Publish to all relays simultaneously
        await withTaskGroup(of: (String, RelayState).self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        // TODO: don't need OneOffEventPublisher for already connected write relays
                        
                        let connection = OneOffEventPublisher(relay, allowAuth: false, signNEventHandler: { ignore in
                            return ignore
                        })
                        
                        try await connection.connect(timeout: 6)
                        try await connection.publish(NEvent.fromNostrEssentialsEvent(wrappedEvent), timeout: 6)
                        
                        return (relay, RelayState.published)
                    } catch let myError as SendMessageError {
                        if case .sendFailed(let reason) = myError {
                            if let reason {
                                self.relayLogs = self.relayLogs + "\(reason)\n"
                            }
                            return (relay, RelayState.error)
                        }
                        else if case .authRequired = myError {
                            return (relay, RelayState.authRequired)
                        }
                        return (relay, RelayState.error)
                    }
                    catch {
                        return (relay, RelayState.error)
                    }
                }
            }
            
            
            // Update relay states as tasks complete
            for await (relay, state) in group {
                Task { @MainActor in
                    switch state {
                        case .published:
                            balloonSuccesses.append(BalloonSuccess(messageId: rumorId, receiverPubkey: receiverPubkey, relay: relay))
                        case .error:
                            balloonErrors.append(BalloonError(messageId: rumorId, receiverPubkey: receiverPubkey, relay: relay, errorText: "failed (1)"))
                        case .authRequired:
                            balloonErrors.append(BalloonError(messageId: rumorId, receiverPubkey: receiverPubkey, relay: relay, errorText: "needs auth"))
                        default:
                            balloonErrors.append(BalloonError(messageId: rumorId, receiverPubkey: receiverPubkey, relay: relay, errorText: "failed (2)"))
                    }
                }
            }
        }
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

struct BalloonError: Identifiable {
    var id: String { messageId }
    let messageId: String
    let receiverPubkey: String
    let relay: String
    let errorText: String
}

struct BalloonSuccess: Identifiable {
    var id: String { messageId }
    let messageId: String
    let receiverPubkey: String
    let relay: String
}

public enum DMError: Error {

    case PrivateKeyMissing
}

enum DMSendResult {
    case success
    case error
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
        lhs.dayId == rhs.dayId && lhs.messages.count == rhs.messages.count
    }
    
    var id: String { dayId }
    let dayId: String // 2025-12-10
    let date: Date
    @Published var messages: [NRChatMessage]
    
    init(dayId: String, date: Date, messages: [NRChatMessage]) {
        self.dayId = dayId
        self.date = date
        self.messages = messages
    }
    
    
}

func fetchDMrelays(for pubkeys: Set<String>) {
    
}

class OutgoingDM: ObservableObject {
    let nrChatMessage: NRChatMessage // rumor
    init(nrChatMessage: NRChatMessage) {
        self.nrChatMessage = nrChatMessage
    }
    
}

func getDMrelays(for pubkey: String) async -> Set<String> {
    let relays: Set<String> = await withBgContext { bgContext in
        if let dmRelaysEvent = Event.fetchEventsBy(pubkey: pubkey, andKind: 10050, context: bgContext).first {
            let relays = dmRelaysEvent.fastTags.filter { $0.0 == "relay" }
                .compactMap { $0.1 }
                .map { normalizeRelayUrl($0) }
            if !relays.isEmpty {
                return Set(relays)
            }
            return []
        }
        return []
    }
    return relays
}

