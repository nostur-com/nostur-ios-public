//
//  NWCRequestQueue.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//

import Foundation

// Instant zaps
// 1. Update UI as if Zap already happened
// 2. Make sure NWC subscription is active (can be slow, waiting for pong, so do this in the beginning)
// 3. Add Zap to ZapQueue
// 4. Zap fetches callback from ln pay end point
// 5. Zap fetches invoice from callback [we include zap request here]
// 6. Zap triggers sending NWC request in NWCRequestQueue
// 7. Send payment request (23194)
// 8. Wait for payment response (23195) (In Importer)
// 9a. If ok, remove from queue
// 9b. If error, show notification on Zaps screen
// 9c. If time out, show notification on Zaps screen

struct FailedZap: Codable {
    let contactPubkey:String
    var eventId:String?
    let error:String
}

struct FailedZaps: Codable {
    let failedZaps:[FailedZap]
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        failedZaps = try container.decode([FailedZap].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(contentsOf: failedZaps)
    }
}
class NWCRequestQueue: ObservableObject {
    
    typealias RequestId = String
    typealias ContactPubkey = String
    
    struct QueuedNWCRequest {
        let request: NEvent // kind 23194
        var zap: Zap?
        var cancellationId: UUID?
        let queuedAt: Date
    }
    
    static let shared = NWCRequestQueue()
    
    @Published public var balance:Int? {
        didSet {
            if let balanceString {
                balanceState = .ready(balanceString, balance)
            }
            else {
                balanceState = .timeout
            }
        }
    }
    
    public var balanceString: String? {
        guard let balance = balance else { return nil }
        return String(balance.satsFormatted)
    }
    @Published public var balanceState:BalanceState = .initial
    
    public enum BalanceState:Equatable {
        case initial
        case loading
        case ready(String, Int?)
        case timeout
    }
    
    private var ctx = bg()
    private var waitingRequests = [RequestId:QueuedNWCRequest]()
    private var cleanUpTimer: Timer?
    public var nwcConnection:NWCConnection? = nil
    let encoder = JSONEncoder()
    
    init() {
        cleanUpTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { [unowned self] timer in
//            L.og.debug("NWCRequestQueue.cleanUpTimer fired")
            let now = Date()
            
            bg().perform { [weak self] in
                guard let self = self else { return }
                var failedZaps = [Zap]()
                var timeoutZaps = [Zap]()
                for req in self.waitingRequests.filter({ now.timeIntervalSince($0.value.queuedAt) >= 55 }) {
                    if req.value.zap?.error != nil { // Received error from NWC
                        failedZaps.append(req.value.zap!)
                    }
                    else if let zap = req.value.zap { // Timeout
                        timeoutZaps.append(zap)
                    }
                    else {
                        L.og.info("⚡️ timeout for req: \(req.value.request.id) .. but has no .zap")
                    }
                }
                self.waitingRequests = self.waitingRequests.filter { now.timeIntervalSince($0.value.queuedAt) < 55 }
                
                if !failedZaps.isEmpty, let jsonData = try? self.encoder.encode(failedZaps.map { FailedZap(contactPubkey: $0.contactPubkey, eventId: $0.eventId, error: $0.error!) }) {
                    
                    if let serializedFails = String(data: jsonData, encoding: .utf8) {
                        L.og.info("⚡️ Creating notification for \(failedZaps.count) failed zaps")
                        let notification = PersistentNotification.createFailedNWCZaps(pubkey: AccountsState.shared.activeAccountPublicKey, message: serializedFails, context: bg())
                        NotificationsViewModel.shared.checkNeedsUpdate(notification)
                        if (SettingsStore.shared.nwcShowBalance) {
                            nwcSendBalanceRequest()
                        }
                    }
                    
                    for f in failedZaps  {
                        if let event = f.event {
                            event.zapState = nil
                        }
                    }
                }
                if !timeoutZaps.isEmpty, let jsonData = try? self.encoder.encode(timeoutZaps.map { FailedZap(contactPubkey: $0.contactPubkey, eventId: $0.eventId, error: "Timeout") }) {
                    
                    if let serializedFails = String(data: jsonData, encoding: .utf8) {
                        L.og.info("⚡️ Creating notification for \(timeoutZaps.count) failed zaps by timeout")
                        let notification = PersistentNotification.createTimeoutNWCZaps(pubkey: AccountsState.shared.activeAccountPublicKey, message: serializedFails, context: bg())
                        NotificationsViewModel.shared.checkNeedsUpdate(notification)
                        if (SettingsStore.shared.nwcShowBalance) {
                            nwcSendBalanceRequest()
                        }
                    }
                    
                    for t in timeoutZaps  {
                        if let event = t.event {
                            event.zapState = nil
                        }
                    }
                }
            }
        })
        cleanUpTimer?.fire()
    }
    
    public func sendRequest(_ request:NEvent, zap:Zap? = nil, cancellationId:UUID? = nil, debugInfo:String? = "") {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        
        self.ensureNWCconnection()
        
        DispatchQueue.main.async {
            _ = Unpublisher.shared.publish(request, cancellationId:cancellationId)
        }
        self.waitingRequests[request.id] = QueuedNWCRequest(request: request, zap:zap, cancellationId: cancellationId, queuedAt: .now)
        if let zap { // Handed over to NWCRequestQueue, so remove from NWCZapQueue.
            NWCZapQueue.shared.removeZap(byId: zap.id)
        }
        L.og.info("⚡️ NWC: sendRequest. now in queue: \(self.waitingRequests.count) -- \(debugInfo ?? "")")
    }
    
    public func ensureNWCconnection() {
        guard let pubkey = nwcConnection?.pubkey, let walletPubkey = nwcConnection?.walletPubkey else {
            L.og.error("NWC connection missing")
            return
        }
        req(RM.getNWCResponses(pubkey: pubkey, walletPubkey: walletPubkey, subscriptionId: "NWC"), activeSubscriptionId: "NWC")
    }
    
    public func getAwaitingRequests() -> [QueuedNWCRequest] {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        return self.waitingRequests.map { $0.value }
    }
    
    public func getAwaitingRequest(byId id:RequestId) -> QueuedNWCRequest? {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        return self.waitingRequests[id]
    }
    
    public func removeRequest(byId: RequestId) {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        self.waitingRequests.removeValue(forKey: byId)
    }
    
    public func removeRequest(byCancellationId cancellationId: UUID) {
        if let r = self.waitingRequests.first (where: { rId, qR in
            qR.cancellationId == cancellationId
        }) {
            self.waitingRequests.removeValue(forKey: r.value.request.id)
        }
    }
    
    public func removeAll() {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        self.waitingRequests = [RequestId:QueuedNWCRequest]()
    }
}
