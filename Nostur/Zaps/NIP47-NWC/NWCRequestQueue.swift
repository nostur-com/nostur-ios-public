//
//  NWCRequestQueue.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/06/2023.
//

import Foundation

// Instant zaps
// 1. Update UI as if Zap already happened
// 2. Add Zap Request Tracker to Queue
// 3. Zap Request Tracker fetches invoice callback
// 4. Zap Request Tracker sends zap request
// 5. Make sure NWC subscription is active
// 6. Send payment request (23194)
// 7. Wait for payment response (23195)
// 8a. If ok, remove from queue
// 8b. If error, show notification on Zaps screen
// 8c. If time out, show notification on Zaps screen

class NWCRequestQueue {
    
    typealias RequestId = String
    typealias ContactPubkey = String
    
    struct QueuedNWCRequest {
        let request: NEvent // kind 23194
        var zap: Zap?
        var cancellationId: UUID?
        let queuedAt: Date
    }
    
    struct FailedZap: Codable {
        let contactPubkey:String
        var eventId:String?
        let error:String
    }
    
    static let shared = NWCRequestQueue()
    
    private var ctx = DataProvider.shared().bg
    private var waitingRequests = [RequestId:QueuedNWCRequest]()
    private var cleanUpTimer: Timer?
    public var nwcConnection:NWCConnection? = nil
    let encoder = JSONEncoder()
    
    init() {
        cleanUpTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true, block: { [unowned self] timer in
            let now = Date()
            
            DataProvider.shared().bg.perform { [weak self] in
                guard let self = self else { return }
                var failedZaps = [Zap]()
                for req in self.waitingRequests.filter({ now.timeIntervalSince($0.value.queuedAt) >= 30 }) {
                    if req.value.zap?.error != nil {
                        failedZaps.append(req.value.zap!)
                    }
                }
                self.waitingRequests = self.waitingRequests.filter { now.timeIntervalSince($0.value.queuedAt) < 30 }
                
                if failedZaps.count > 0, let jsonData = try? self.encoder.encode(failedZaps.map { FailedZap(contactPubkey: $0.contactPubkey, eventId: $0.eventId, error: $0.error!) }) {
                    
                    if let serializedFails = String(data: jsonData, encoding: .utf8) {
                        L.og.info("⚡️ Creating notification for \(failedZaps.count) failed zaps")
                        _ = PersistentNotification.createFailedNWCZaps(pubkey: NosturState.shared.activeAccountPublicKey, message: serializedFails, context: DataProvider.shared().bg)
                    }
                }
            }
        })
    }
    
    public func sendRequest(_ request:NEvent, zap:Zap? = nil, cancellationId:UUID? = nil, debugInfo:String? = "") {
        guard let pubkey = nwcConnection?.pubkey, let walletPubkey = nwcConnection?.walletPubkey else {
            L.og.error("NWC connection missing")
            return
        }
        if Thread.isMainThread {
            fatalError("Fix this")
        }
        reqP(RM.getNWCResponses(pubkey: pubkey, walletPubkey: walletPubkey, subscriptionId: "NWC"), activeSubscriptionId: "NWC")
        DispatchQueue.main.async {
            _ = Unpublisher.shared.publish(request, cancellationId:cancellationId)
        }
        self.waitingRequests[request.id] = QueuedNWCRequest(request: request, zap:zap, cancellationId: cancellationId, queuedAt: Date.now)
        L.og.info("⚡️ NWC: sendRequest. now in queue: \(self.waitingRequests.count) -- \(debugInfo ?? "")")
    }
    
    public func getAwaitingRequests() -> [QueuedNWCRequest] {
        if Thread.isMainThread {
            fatalError("Fix this")
        }
        return self.waitingRequests.map { $0.value }
    }
    
    public func getAwaitingRequest(byId id:RequestId) -> QueuedNWCRequest? {
        if Thread.isMainThread {
            fatalError("Fix this")
        }
        return self.waitingRequests[id]
    }
    
    public func removeRequest(byId: RequestId) {
        if Thread.isMainThread {
            fatalError("Fix this")
        }
        self.waitingRequests.removeValue(forKey: byId)
    }
    
    public func removeRequest(byCancellationId cancellationId:UUID) {
        if let r = self.waitingRequests.first (where: { rId, qR in
            qR.cancellationId == cancellationId
        }) {
            self.waitingRequests.removeValue(forKey: r.value.request.id)
        }
    }
    
    public func removeAll() {
        if Thread.isMainThread {
            fatalError("Fix this")
        }
        self.waitingRequests = [RequestId:QueuedNWCRequest]()
    }
}
