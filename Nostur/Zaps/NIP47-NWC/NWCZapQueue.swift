//
//  NWCZapQueue.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
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

class NWCZapQueue {
    static let shared = NWCZapQueue()
    
    private var waitingZaps = [UUID:Zap]()
    private var cleanUpTimer: Timer?
    
    init() {
        cleanUpTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true, block: { [unowned self] timer in
            let now = Date()
            
            DataProvider.shared().bg.perform {
                self.waitingZaps = self.waitingZaps.filter { now.timeIntervalSince($0.value.queuedAt) < 30 }
            }
        })
    }
    
    public func sendZap(_ zap:Zap, debugInfo:String? = "") {
        if Thread.isMainThread {
            fatalError("Fix this")
        }
        self.waitingZaps[zap.id] = zap
        L.og.info("⚡️ NWC: sendZap. now in queue: \(self.waitingZaps.count) -- \(debugInfo ?? "")")
    }
    
    public func getAwaitingZap(byId id:UUID) -> Zap? {
        if Thread.isMainThread {
            fatalError("Fix this")
        }
        return self.waitingZaps[id]
    }
    
    public func removeZap(byId id:UUID) {
        if Thread.isMainThread {
            fatalError("Fix this")
        }
        self.waitingZaps.removeValue(forKey: id)
    }
    
    public func removeZap(byCancellationId cancellationId:UUID) {
        if let zap = self.waitingZaps.first(where: { zId, zap in
            zap.cancellationId == cancellationId
        }) {
            self.waitingZaps.removeValue(forKey: zap.value.id)
        }
    }
}

class Zap {
    var id = UUID()
    let queuedAt:Date
    var state:ZapSate = .INIT {
        didSet {
            guard state != .INIT else { return }
            next()
        }
    }
    var lud16:String?
    var lud06:String?
    var amount:Int64
    var eventId:String?
    let contact:Contact
    let cancellationId:UUID
    let contactPubkey:String
    var error:String? = nil
    
    var supportsZap = false
    var callbackUrl:String? = nil
    var pr:String? = nil // payment request (invoice)
    
    init(amount:Int64, contact:Contact, eventId:String? = nil, cancellationId:UUID) {
        self.queuedAt = .now
        self.amount = amount
        self.contact = contact
        self.cancellationId = cancellationId
        self.contactPubkey = contact.pubkey
        self.eventId = eventId
        self.lud16 = contact.lud16
        self.lud06 = contact.lud06
        next()
    }
    
    enum ZapSate:String {
        case INIT = "INIT"
        case CALLBACK_RECEIVED = "CALLBACK_RECEIVED"
        case INVOICE_FETCHED = "INVOICE_FETCHED"
        case NWC_PAY_REQUEST_SENT = "NWC_PAY_REQUEST_SENT"
        case NWC_INVOICE_PAID = "NWC_INVOICE_PAID"
        case ERROR = "ERROR"
    }
    
    private func next() {
        L.og.debug("⚡️ Zap.next() \(self.state.rawValue) - \(self.id.uuidString) - \(self.callbackUrl ?? "") - supportsZap: \(self.supportsZap) - lud \(self.lud16 ?? self.lud06 ?? "") - eventId:\(self.eventId ?? "") - \(self.pr ?? "")")
        switch state {
        case .INIT: //1. fetch callback from ln pay end point
            fetchCallbackUrl()
        case .CALLBACK_RECEIVED:
            fetchInvoice()
        case .INVOICE_FETCHED:
            payInvoice()
        case .NWC_PAY_REQUEST_SENT:
            print("")
        case .NWC_INVOICE_PAID:
            print("")
        case .ERROR:
            print("")
        }
    }
    
    private func fetchCallbackUrl() {
        Task {
            do {
                let response = try await (lud16 != nil ? LUD16.getCallbackUrl(lud16: lud16!) : LUD16.getCallbackUrl(lud06: lud06!))
                if let callback = response.callback {
                    if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                        self.supportsZap = true
                        // Store zapper nostrPubkey on contact.zapperPubkey as cache
                        await DataProvider.shared().bg.perform {
                            self.contact.zapperPubkey = response.nostrPubkey!
                        }
                    }
                    self.callbackUrl = callback
                    self.state = .CALLBACK_RECEIVED
                }
                else {
                    self.state = .ERROR
                }
            }
            catch {
                L.og.error("🔴🔴🔴🔴 problem in lnurlp \(error)")
                self.error = "Payment failed"
                self.state = .ERROR
            }
        }
    }
    
    private func fetchInvoice() {
        guard let callbackUrl = self.callbackUrl else { state = .ERROR; return }
        let relays = SocketPool.shared.sockets.values
            .filter { $0.write && !$0.isNWC }
            .map { $0.url }
        
        if (self.supportsZap) {
            DataProvider.shared().bg.perform { [weak self] in
                guard let self = self else { return }
                let zapRequestNote = zapRequest(forPubkey: self.contactPubkey, andEvent: self.eventId, relays: relays)
                if let signedZapRequestNote = try? NosturState.shared.signEventBg(zapRequestNote) {
                    
                    Task {
                        if let response = try? await LUD16.getInvoice(url:callbackUrl, amount:UInt64(self.amount * 1000), zapRequestNote: signedZapRequestNote) {
                            
                            if let pr = response.pr {
                                self.pr = pr
                                self.state = .INVOICE_FETCHED
                            }
                            else {
                                L.fetching.notice("problem fetching ln invoice / or signing zap request note. callback: \(self.callbackUrl ?? "")")
                                self.state = .ERROR
                                self.error = "Problem fetching invoice"
                            }
                        }
                    }
                }
                else {
                    L.fetching.notice("problem fetching ln invoice / or signing zap request note. callback: \(self.callbackUrl ?? "")")
                    self.state = .ERROR
                    self.error = "Problem fetching invoice"
                }
            }
        }
        else {
            Task {
                do {
                    let response = try await LUD16.getInvoice(url:callbackUrl, amount:UInt64(amount * 1000))
                    
                    if let pr = response.pr {
                        self.pr = pr
                        self.state = .INVOICE_FETCHED
                        next()
                    }
                }
                catch {
                    L.fetching.notice("problem fetching ln invoice. callback:\(self.callbackUrl ?? "") \(error)")
                    self.state = .ERROR
                    self.error = "Problem fetching invoice"
                }
            }
        }
    }
    
    private func payInvoice() {
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            guard let pr = self.pr else { state = .ERROR; return }
            
            if nwcSendPayInvoiceRequest(pr, zap:self, cancellationId: self.cancellationId) {
                self.state = .NWC_PAY_REQUEST_SENT
            }
            else {
                state = .ERROR
                self.error = "Problem sending NWC payment command"
            }
        }
    }
}

//0. fetch kind 0 - skip this. if we dont have kind 0 we dont have zap button
//1. fetch callback from ln pay end point
//2. fetch invoice from callback [we include zap request here]
//3. pay invoice with NWC
//4. handle NWC response or time out

func nwcSendPayInvoiceRequest(_ pr:String, zap:Zap? = nil, cancellationId:UUID? = nil) -> Bool {
    L.og.debug("⚡️ nwcSendPayInvoiceRequest called \(pr)")
    var pk:String?
    var walletPubkey:String?
    
    if Thread.isMainThread {
        guard !SettingsStore.shared.activeNWCconnectionId.isEmpty else { L.og.error("⚡️ No activeNWCConnectionId"); return false }
        guard let nwc = NWCConnection.fetchConnection(SettingsStore.shared.activeNWCconnectionId, context: DataProvider.shared().viewContext) else { L.og.error("⚡️ Problem fetching nwcConnection \(SettingsStore.shared.activeNWCconnectionId)"); return false }
        
        guard let mainPK = nwc.privateKey else { L.og.error("⚡️ Problem with private key or nwcConnection"); return false }
        pk = mainPK
        walletPubkey = nwc.walletPubkey
    }
    else {
        guard let bgPK = NWCRequestQueue.shared.nwcConnection?.privateKey else { L.og.error("⚡️ Problem with private key or nwcConnection"); return false }
        guard let bgWalletPubkey = NWCRequestQueue.shared.nwcConnection?.walletPubkey else { L.og.error("⚡️ Problem with walletPubkey or nwcConnection"); return false }
        pk = bgPK
        walletPubkey = bgWalletPubkey
    }
    guard let pk = pk else { return false }
    guard let walletPubkey = walletPubkey else { return false }
    
    if let keys = try? NKeys(privateKeyHex: pk) {
        
        let request = NWCRequest(method: "pay_invoice", params: NWCRequest.NWCParams(invoice: pr))
        let encoder = JSONEncoder()
        
        if let requestJsonData = try? encoder.encode(request) {
            if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                var nwcReq = NEvent(content: requestJsonString)
                nwcReq.kind = .nwcRequest
                nwcReq.tags.append(NostrTag(["p",walletPubkey]))
                
                L.og.debug("⚡️ Going to encrypt and send: \(nwcReq.eventJson())")
                
                guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex(), pubkey: walletPubkey, content: nwcReq.content) else {
                    L.og.error("⚡️ Problem encrypting request")
                    return false
                }
                
                nwcReq.content = encrypted
                
                if let signedReq = try? nwcReq.sign(keys) {
//                            print(signedReq.wrappedEventJson())
                    if (Thread.isMainThread) {
                        DataProvider.shared().bg.perform {
                            NWCRequestQueue.shared.sendRequest(signedReq, zap: zap, cancellationId: cancellationId)
                        }
                    }
                    else {
                        NWCRequestQueue.shared.sendRequest(signedReq, zap: zap, cancellationId: cancellationId)
                    }
                    return true
                    // after send, should get
//                            [
//                              "OK",
//                              "bdd9129877cf7982e01d923bd52bc15ecfdf720c3d0e77012a04c7077d1af55d",
//                              true,
//                              ""
//                            ]
                }
                else {
                    L.og.error("⚡️ Problem signing: \(nwcReq.eventJson())")
                    return false
                }
            }
        }
        
        L.og.error("⚡️ Problem encoding request")
        return false
    }
    L.og.error("⚡️ Problem with NWC private key")
    return false
}
