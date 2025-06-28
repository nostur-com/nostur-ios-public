//
//  NWCZapQueue.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//

import Foundation
import NostrEssentials

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

class NWCZapQueue {
    static let shared = NWCZapQueue()
    
    private var waitingZaps = [UUID:Zap]()
    private var cleanUpTimer: Timer?
    let encoder = JSONEncoder()
    
    init() {
        cleanUpTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { [unowned self] timer in
            let now = Date()
            
            bg().perform { [weak self] in
                guard let self = self else { return }
                var failedZaps = [Zap]()
                for zap in self.waitingZaps.filter({ now.timeIntervalSince($0.value.queuedAt) >= 55 }) {
                    if zap.value.error != nil {
                        failedZaps.append(zap.value)
                    }
                }
                self.waitingZaps = self.waitingZaps.filter { now.timeIntervalSince($0.value.queuedAt) < 55 }
                
                if !failedZaps.isEmpty, let jsonData = try? self.encoder.encode(failedZaps.map { FailedZap(contactPubkey: $0.contactPubkey, eventId: $0.eventId, error: $0.error!) }) {
                    
                    if let serializedFails = String(data: jsonData, encoding: .utf8) {
#if DEBUG
                        L.og.info("⚡️ Creating notification for \(failedZaps.count) failed zaps")
#endif
                        let notification = PersistentNotification.createFailedNWCZaps(pubkey: AccountsState.shared.activeAccountPublicKey, message: serializedFails, context: bg())
                        NotificationsViewModel.shared.checkNeedsUpdate(notification)
                    }
                }
            }
        })
        cleanUpTimer?.fire()
    }
    
    public func sendZap(_ zap:Zap, debugInfo:String? = "") {
#if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
#endif
        self.waitingZaps[zap.id] = zap
#if DEBUG
        L.og.info("⚡️ NWC: sendZap. now in queue: \(self.waitingZaps.count) -- \(debugInfo ?? "")")
#endif
    }
    
    public func getAwaitingZap(byId id:UUID) -> Zap? {
#if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
#endif
        return self.waitingZaps[id]
    }
    
    public func removeZap(byId id:UUID) {
#if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
#endif
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
    var zapMessage:String = ""
    var isNC = false
    var amount:Int64
    var eventId:String?
    var aTag:String?
    var event:Event?
    let contact:Contact
    let cancellationId:UUID
    let contactPubkey:String
    var error:String? = nil
    
    var supportsZap = false
    var callbackUrl:String? = nil
    var pr:String? = nil // payment request (invoice)
    var fromAccountPubkey:String
    var withPending = false
    
    init(isNC: Bool = false, amount: Int64, contact: Contact, eventId: String? = nil, aTag: String? = nil, event: Event? = nil, cancellationId: UUID, zapMessage: String = "", withPending: Bool = false) {
        self.isNC = isNC
        self.fromAccountPubkey = AccountsState.shared.activeAccountPublicKey
        self.queuedAt = .now
        self.amount = amount
        self.contact = contact
        self.cancellationId = cancellationId
        self.contactPubkey = contact.pubkey
        self.eventId = eventId
        self.aTag = aTag
        self.event = event
        self.lud16 = contact.lud16
        self.lud06 = contact.lud06
        self.zapMessage = zapMessage
        self.withPending = withPending
        next()
    }
    
    enum ZapSate: String {
        case INIT = "INIT"
        case CALLBACK_RECEIVED = "CALLBACK_RECEIVED"
        case INVOICE_FETCHED = "INVOICE_FETCHED"
        case NWC_PAY_REQUEST_SENT = "NWC_PAY_REQUEST_SENT"
        case NWC_INVOICE_PAID = "NWC_INVOICE_PAID"
        case ERROR = "ERROR"
    }
    
    private func next() {
#if DEBUG
        L.og.debug("⚡️ Zap.next() \(self.state.rawValue) - \(self.id.uuidString) - \(self.callbackUrl ?? "") - supportsZap: \(self.supportsZap) - lud \(self.lud16 ?? self.lud06 ?? "") - eventId: \(self.eventId ?? "") - aTag: \(self.aTag ?? "") - \(self.pr ?? "")")
#endif
        switch state {
        case .INIT: //1. fetch callback from ln pay end point
            fetchCallbackUrl()
        case .CALLBACK_RECEIVED:
            Task { @MainActor in
                self.fetchInvoice()
            }
        case .INVOICE_FETCHED:
            payInvoice()
        case .NWC_PAY_REQUEST_SENT:
#if DEBUG
            L.og.debug("NWC_PAY_REQUEST_SENT")
#endif
            break
        case .NWC_INVOICE_PAID:
#if DEBUG
            L.og.debug("NWC_INVOICE_PAID")
#endif
            break
        case .ERROR:
            bg().perform { [weak self] in
                guard let self = self else { return }
                if let eventId = self.eventId {
                    let message = String(localized: "[Zap](nostur:e:\(eventId)) failed.\n\(self.error ?? "")", comment: "Error message. don't translate the (nostur:e:...) part")
                    let notification = PersistentNotification.createFailedNWCZap(pubkey: AccountsState.shared.activeAccountPublicKey, message: message, context: bg())
                    NotificationsViewModel.shared.checkNeedsUpdate(notification)
#if DEBUG
                    L.og.info("⚡️ Created notification: Zap failed for [post](nostur:e:\(eventId)). \(self.error ?? "")")
#endif
                    
                    // Revert zap state
                    if let event = EventRelationsQueue.shared.getAwaitingBgEvent(byId: eventId) {
#if DEBUG
                        L.og.info("Revert from queue")
#endif
                        event.zapState = nil
                    }
                    else if let event = Event.fetchEvent(id: eventId, context: bg()) {
#if DEBUG
                        L.og.info("Revert from DB")
#endif
                        event.zapState = nil
                    }
                }
                else {
                    let message = String(localized:"Zap failed for [contact](nostur:p:\(self.contactPubkey)).\n\(self.error ?? "")", comment: "Error message. Only translate the 'Zap failed for' part, don't change between brackets")
                    let notification = PersistentNotification.createFailedNWCZap(pubkey: AccountsState.shared.activeAccountPublicKey, message: message, context: bg())
                    NotificationsViewModel.shared.checkNeedsUpdate(notification)
#if DEBUG
                    L.og.info("⚡️ Created notification: Zap failed for [contact](nostur:p:\(self.contactPubkey)). \(self.error ?? "")")
#endif
                }
                DataProvider.shared().bgSave()
            }
        }
    }
    
    private func fetchCallbackUrl() {
        Task { [weak self] in
            guard let self else { return }
            guard (lud16 != nil || lud06 != nil) else { return }
            do {
                let response = try await (lud16 != nil ? LUD16.getCallbackUrl(lud16: lud16!) : LUD16.getCallbackUrl(lud06: lud06!))
                if let callback = response.callback {
                    if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                        self.supportsZap = true
                        // Store zapper nostrPubkey on contact.zapperPubkey as cache
                        await bg().perform {
                            self.contact.zapperPubkeys.insert(zapperPubkey)
                        }
                    }
                    self.callbackUrl = callback
                    Task { @MainActor in
                        self.state = .CALLBACK_RECEIVED
                    }
                }
                else {
                    self.error = String(localized:"Could not fetch invoice", comment: "Error message")
                    self.state = .ERROR
                }
            }
            catch {
#if DEBUG
                L.og.error("🔴🔴🔴🔴 problem in lnurlp \(error)")
#endif
                self.error = String(localized:"Could not fetch invoice", comment: "Error message")
                self.state = .ERROR
            }
        }
    }
    
    @MainActor
    private func fetchInvoice() {
        guard let callbackUrl = self.callbackUrl else { state = .ERROR; return }
        let relays = ConnectionPool.shared.connections.values
            .filter { $0.relayData.write && !$0.isNWC }
            .map { $0.url }
        
        guard let account = account() else { return }
        let acountPubkey = account.publicKey
        
        if (self.supportsZap) {
            bg().perform { [weak self] in
                guard let self = self else { return }
                
                
                let accountNrContact = NRContact.instance(of: acountPubkey)
                
                if isNC {
                    let zapRequestNote = if let aTag = self.aTag {
                        zapRequest(forPubkey: self.contactPubkey, andATag: aTag, withMessage: zapMessage, relays: relays)
                    }
                    else {
                        zapRequest(forPubkey: self.contactPubkey, andEvent: self.eventId, withMessage: zapMessage, relays: relays)
                    }
                    
                    let content = NRContentElementBuilder.shared.buildElements(input: zapRequestNote.content, fastTags: zapRequestNote.fastTags, primaryColor: Themes.default.theme.primary).0
                    
                    Task { @MainActor in
                        NSecBunkerManager.shared.requestSignature(forEvent: zapRequestNote, usingAccount: account, whenSigned: { [weak self] signedEvent in
                            Task { [weak self] in
                                guard let self else { return }
                                
                                if self.withPending, let aTag = self.aTag {
                                    DispatchQueue.main.async {
                                        sendNotification(.receivedPendingZap, NRChatPendingZap(
                                            id: signedEvent.id,
                                            pubkey: signedEvent.publicKey,
                                            createdAt: Date(
                                                timeIntervalSince1970: Double(signedEvent.createdAt.timestamp)
                                            ),
                                            aTag: aTag,
                                            amount: 21000,
                                            nxEvent: NXEvent(pubkey: signedEvent.publicKey, kind: signedEvent.kind.id),
                                            content: content,
                                            contact: accountNrContact,
                                            via: (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(signedEvent.publicKey)) ? "Nostur" : nil
                                        ))
                                    }
                                }
                                if let response = try? await LUD16.getInvoice(url:callbackUrl, amount:UInt64(self.amount * 1000), zapRequestNote: signedEvent) {
                                    
                                    if let pr = response.pr {
                                        self.pr = pr
                                        self.state = .INVOICE_FETCHED
                                    }
                                    else {
#if DEBUG
                                        L.fetching.notice("problem fetching ln invoice / or signing zap request note. callback: \(self.callbackUrl ?? "")")
#endif
                                        self.error = String(localized:"Could not fetch invoice", comment: "Error message")
                                        self.state = .ERROR
                                    }
                                }
                                else {
#if DEBUG
                                    L.fetching.notice("problem fetching ln invoice / or signing zap request note. callback: \(self.callbackUrl ?? "")")
#endif
                                    self.error = String(localized:"Could not fetch invoice", comment: "Error message")
                                    self.state = .ERROR
                                }
                            }
                        })
                    }
                }
                else {
                    
                    let zapRequestNote = if let aTag = self.aTag {
                        zapRequest(forPubkey: self.contactPubkey, andATag: aTag, withMessage: zapMessage, relays: relays)
                    }
                    else {
                        zapRequest(forPubkey: self.contactPubkey, andEvent: self.eventId, withMessage: zapMessage, relays: relays)
                    }
                    
                    let content = NRContentElementBuilder.shared.buildElements(input: zapRequestNote.content, fastTags: zapRequestNote.fastTags, primaryColor: Themes.default.theme.primary).0
                    
                    Task { @MainActor in
                        if let signedZapRequestNote = try? account.signEvent(zapRequestNote) {
                            if self.withPending, let aTag = self.aTag {
                                    sendNotification(.receivedPendingZap, NRChatPendingZap(
                                        id: signedZapRequestNote.id,
                                        pubkey: signedZapRequestNote.publicKey,
                                        createdAt: Date(
                                            timeIntervalSince1970: Double(signedZapRequestNote.createdAt.timestamp)
                                        ),
                                        aTag: aTag,
                                        amount: self.amount,
                                        nxEvent: NXEvent(pubkey: signedZapRequestNote.publicKey, kind: signedZapRequestNote.kind.id),
                                        content: content,
                                        contact: accountNrContact,
                                        via: (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(signedZapRequestNote.publicKey)) ? "Nostur" : nil
                                    ))
                            }
                            if let response = try? await LUD16.getInvoice(url:callbackUrl, amount:UInt64(self.amount * 1000), zapRequestNote: signedZapRequestNote) {
                                if let pr = response.pr {
                                    self.pr = pr
                                    self.state = .INVOICE_FETCHED
                                }
                                else {
#if DEBUG
                                    L.fetching.notice("problem fetching ln invoice / or signing zap request note. callback: \(self.callbackUrl ?? "")")
#endif
                                    self.error = String(localized:"Could not fetch invoice", comment: "Error message")
                                    self.state = .ERROR
                                }
                            }
                            else {
#if DEBUG
                                L.fetching.notice("problem fetching ln invoice / or signing zap request note. callback: \(self.callbackUrl ?? "")")
#endif
                                self.error = String(localized:"Could not fetch invoice", comment: "Error message")
                                self.state = .ERROR
                            }
                        }
                        else {
#if DEBUG
                            L.fetching.notice("problem fetching ln invoice / or signing zap request note. callback: \(self.callbackUrl ?? "")")
#endif
                            self.error = String(localized:"Could not fetch invoice", comment: "Error message")
                            self.state = .ERROR
                        }
                    }
                }
            }
        }
        else {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let response = try await LUD16.getInvoice(url:callbackUrl, amount: UInt64(amount * 1000))
                    
                    if let pr = response.pr {
                        self.pr = pr
                        self.state = .INVOICE_FETCHED
                        next()
                    }
                }
                catch {
#if DEBUG
                    L.fetching.notice("problem fetching ln invoice. callback:\(self.callbackUrl ?? "") \(error)")
#endif
                    self.error = String(localized:"Could not fetch invoice", comment: "Error message")
                    self.state = .ERROR
                }
            }
        }
    }
    
    private func payInvoice() {
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard let pr = self.pr else { state = .ERROR; return }
            
            if nwcSendPayInvoiceRequest(pr, zap:self, cancellationId: self.cancellationId) {
                self.state = .NWC_PAY_REQUEST_SENT
            }
            else {
                self.error = String(localized:"Could not send NWC request", comment: "Error message")
                state = .ERROR
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
#if DEBUG
    L.og.debug("⚡️ nwcSendPayInvoiceRequest called \(pr)")
#endif
    var pk:String?
    var walletPubkey:String?
    
    if Thread.isMainThread {
        guard !SettingsStore.shared.activeNWCconnectionId.isEmpty else {
#if DEBUG
            L.og.error("⚡️ No activeNWCConnectionId")
#endif
            return false
        }
        guard let nwc = NWCConnection.fetchConnection(SettingsStore.shared.activeNWCconnectionId, context: DataProvider.shared().viewContext) else { L.og.error("⚡️ Problem fetching nwcConnection \(SettingsStore.shared.activeNWCconnectionId)"); return false }
        
        guard let mainPK = nwc.privateKey else {
#if DEBUG
            L.og.error("⚡️ Problem with private key or nwcConnection")
#endif
            return false
        }
        pk = mainPK
        walletPubkey = nwc.walletPubkey
    }
    else {
        guard let bgPK = NWCRequestQueue.shared.nwcConnection?.privateKey else {
#if DEBUG
            L.og.error("⚡️ Problem with private key or nwcConnection")
#endif
            return false
        }
        guard let bgWalletPubkey = NWCRequestQueue.shared.nwcConnection?.walletPubkey else {
#if DEBUG
            L.og.error("⚡️ Problem with private key or nwcConnection")
#endif
            return false
        }
        pk = bgPK
        walletPubkey = bgWalletPubkey
    }
    guard let pk = pk else { return false }
    guard let walletPubkey = walletPubkey else { return false }
    
    if let keys = try? Keys(privateKeyHex: pk) {
        
        let request = NWCRequest(method: "pay_invoice", params: NWCRequest.NWCParams(invoice: pr))
        let encoder = JSONEncoder()
        
        if let requestJsonData = try? encoder.encode(request) {
            if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                var nwcReq = NEvent(content: requestJsonString)
                nwcReq.kind = .nwcRequest
                nwcReq.tags.append(NostrTag(["p",walletPubkey]))
                
#if DEBUG
                L.og.debug("⚡️ Going to encrypt and send: \(nwcReq.eventJson())")
#endif
                
                guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex, pubkey: walletPubkey, content: nwcReq.content) else {
#if DEBUG
                    L.og.error("⚡️ Problem encrypting request")
#endif
                    return false
                }
                
                nwcReq.content = encrypted
                
                if let signedReq = try? nwcReq.sign(keys) {
//                            print(signedReq.wrappedEventJson())
                    if (Thread.isMainThread) {
                        bg().perform {
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
#if DEBUG
                    L.og.error("⚡️ Problem signing: \(nwcReq.eventJson())")
#endif
                    return false
                }
            }
        }
        
#if DEBUG
        L.og.error("⚡️ Problem encoding request")
#endif
        return false
    }
#if DEBUG
    L.og.error("⚡️ Problem with NWC private key")
#endif
    return false
}
