//
//  NSecBunkerManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/06/2023.
//

import Foundation
import Combine

// TODO: The happy paths works fine, but need to handle errors, timeouts, etc and notify user instead of silent fail.
class NSecBunkerManager: ObservableObject {
    
    static let shared = NSecBunkerManager()
    
    @Published var state:STATE = .disconnected
    @Published var error = ""
    @Published var isSelfHostedNsecBunker = false
    @Published var ncRelay = ""
    
    var invalidSelfHostedAddress:Bool {
        if let url = URL(string: ncRelay) {
            if url.absoluteString.lowercased().prefix(6) == "wss://" { return false }
            if url.absoluteString.lowercased().prefix(5) == "ws://" { return false }
        }
        return true
    }
    
    var backlog = Backlog(timeout: 15, auto: true)
    let decoder = JSONDecoder()
    var account:CloudAccount? = nil
    var subscriptions = Set<AnyCancellable>()
    
    // Queue of commands to execute when we receive a response
    var responseCommmandQueue:[String: (NEvent) -> Void] = [:] // TODO: need to add clean up, timeout...
    
    private init() {
        listenForNCMessages()
    }
    
    private func listenForNCMessages() {
        receiveNotification(.receivedMessage)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let message = notification.object as! RelayMessage
                guard let event = message.event else { return }
                guard let account = self.account else { return }
                guard let sessionPrivateKey = account.privateKey else { return }
             
                guard let decrypted = NKeys.decryptDirectMessageContent(withPrivateKey: sessionPrivateKey, pubkey: event.publicKey, content: event.content) else {
                    L.og.error("🏰 Could not decrypt ncMessage, \(event.eventJson())")
                    return
                }
                guard let ncResponse = try? decoder.decode(NCResponse.self, from: decrypted.data(using: .utf8)!) else {
                    L.og.error("🏰 Could not parse/decode ncMessage, \(event.eventJson()) - \(decrypted)")
                    return
                }
                 
                if let command = responseCommmandQueue[ncResponse.id] {
                    // SIGNED EVENT RESPONSE
                    if let error = ncResponse.error {
                        L.og.error("🏰 NSECBUNKER error signing event: \(error) ")
                        Importer.shared.listStatus.send("nsecBunker: \(error)")
                        return
                    }
                    guard let result = ncResponse.result else {
                        L.og.error("🏰 NSECBUNKER Unknown or missing result \(decrypted) ")
                        return
                    }
                    
                    guard let nEvent = try? decoder.decode(NEvent.self, from: result.data(using: .utf8)!) else {
                        L.og.error("🏰 NSECBUNKER error decoding signed result event \(decrypted)")
                        return
                    }
                    command(nEvent)
                    responseCommmandQueue[ncResponse.id] = nil
                    return
                }
                
                // CONNECT RESPONSE
                if ncResponse.id.prefix(8) == "connect-" {
                    guard let result = ncResponse.result else {
                        L.og.error("🏰 ncMessage does not have result, \(event.eventJson()) - \(decrypted)")
                        return
                    }
                    if result == "ack" {
                        DispatchQueue.main.async {
                            self.state = .connected
                            L.og.info("🏰 NSECBUNKER connection success ")
                        }
                    }
                    else {
                        DispatchQueue.main.async {
                            self.error = "Unable to connect"
                            self.state = .error
                            L.og.error("🏰 result: \(result) -- \(event.eventJson()) - \(decrypted)")
                        }
                    }
                }
                
                // DESCRIBE RESPONSE - Using this to check connectivity
                else if ncResponse.id.prefix(9) == "describe-" {
                    guard let result = ncResponse.result else {
                        L.og.error("🏰 ncMessage does not have result, \(event.eventJson()) - \(decrypted)")
                        return
                    }
                    if result.contains("\"describe\"") { // should be something like "[\"connect\",\"sign_event\",\"nip04_encrypt\",\"nip04_decrypt\",\"get_public_key\",\"describe\",\"publish_event\"]"
                        DispatchQueue.main.async {
                            self.state = .connected
                            L.og.info("🏰 NSECBUNKER connection success ")
                        }
                    }
                }
                
                // SIGNED EVENT RESPONSE
                else if ncResponse.id.prefix(11) == "sign-event-" {
                    // SIGNED EVENT RESPONSE
                    if let error = ncResponse.error {
                        L.og.error("🏰 NSECBUNKER error signing event: \(error) ")
                        return
                    }
                    guard let result = ncResponse.result else {
                        L.og.error("🏰 NSECBUNKER Unknown or missing result \(decrypted) ")
                        return
                    }
                    self.handleSignedEvent(eventString:result)
                }
            }
            .store(in: &subscriptions)
    }
    
    private func connectToSelfHostedNsecbunker(sessionPublicKey: String, relay:String) {
        _ = SocketPool.shared.addNCSocket(sessionPublicKey: sessionPublicKey, url: relay)
    }
    
    private func connectToHardcodedNsecbunker(sessionPublicKey: String) {
        _ = SocketPool.shared.addNCSocket(sessionPublicKey: sessionPublicKey, url: "wss://relay.nsecbunker.com")
    }
    
    public func setAccount(_ account: CloudAccount) {
        self.account = account
        guard let sessionPrivateKey = account.privateKey else { return }
        guard let keys = try? NKeys(privateKeyHex: sessionPrivateKey) else { return }
        // connect to NC relay, the session public key is used as id
        if account.ncRelay != "" {
            self.connectToSelfHostedNsecbunker(sessionPublicKey: keys.publicKeyHex(), relay: account.ncRelay)
        }
        else {
            self.connectToHardcodedNsecbunker(sessionPublicKey: keys.publicKeyHex())
        }
    }
    
    public func connect(_ account: CloudAccount, token: String) {
        // When the connection is made, we set ns.setAccount with connectingAccount
        state = .connecting
        self.account = account
        
        // Generate session key, the private key is stored in keychain, it is accessed by using the public key of the bunker managed account
        _ = NIP46SecretManager.shared.generateKeysForAccount(account)
        
        account.isNC = true
        let bunkerManagedPublicKey = account.publicKey
        
        // account does not have a .privateKey, but because isNC=true it will look up in NIP46SecretManager for a session private key and use that instead
        guard let sessionPrivateKey = account.privateKey else { state = .error; return }
        guard let keys = try? NKeys(privateKeyHex: sessionPrivateKey) else { state = .error; return }
        
        // connect to NC relay, the session public key is used as id
        if isSelfHostedNsecBunker {
            self.connectToSelfHostedNsecbunker(sessionPublicKey: keys.publicKeyHex(), relay: self.ncRelay)
        }
        else {
            self.connectToHardcodedNsecbunker(sessionPublicKey: keys.publicKeyHex())
        }
        
        // the connect request, params are our session public key and the bunker provided redemption token
        let request = NCRequest(id: "connect-\(UUID().uuidString)", method: "connect", params: [keys.publicKeyHex(), token])
        let encoder = JSONEncoder()
        
        guard let requestJsonData = try? encoder.encode(request) else { state = .error; return }
        
        guard let requestJsonString = String(data: requestJsonData, encoding: .utf8) else { state = .error; return }
        
        var ncReq = NEvent(content: requestJsonString)
        ncReq.kind = .ncMessage
        ncReq.tags.append(NostrTag(["p", bunkerManagedPublicKey]))
        
        L.og.debug("🏰 ncReq (unecrypted): \(ncReq.eventJson())")
        
        guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex(), pubkey: bunkerManagedPublicKey, content: ncReq.content) else {
            L.og.error("🏰 🔴🔴 Could not encrypt content for ncMessage")
            return
        }
        
        ncReq.content = encrypted
        
        guard let signedReq = try? ncReq.sign(keys) else { state = .error; return }
        
        L.og.debug("🏰 ncReqSigned (encrypted): \(signedReq.wrappedEventJson())")
        
        // Wait 2.5 seconds for NC connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // Setup the NC subscription that listens for NC messages
            // filter: authors (bunker managed key), #p (our session pubkey)
            req(RM.getNCResponses(pubkey: keys.publicKeyHex(), bunkerPubkey: bunkerManagedPublicKey, subscriptionId: "NC"), activeSubscriptionId: "NC")
            
            // Send connection request
            SocketPool.shared.sendMessageAfterPing(ClientMessage(onlyForNCRelay: true, message: signedReq.wrappedEventJson()), accountPubkey: signedReq.publicKey)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { // Must wait until connected to bunker relay
            if self.state != .connected {
                self.error = "Connection timed out"
                self.state = .error
            }
        }
    }
    
    // Ask nsecBunker for signature for given event, runs whenSigned(..) callback with signed event after
    public func requestSignature(forEvent event: NEvent, usingAccount: CloudAccount? = nil, whenSigned: ((NEvent) -> Void)? = nil) {
        guard let account = (usingAccount ?? (Thread.isMainThread ? account : account?.toBG())) else { return }
        
        // account does not have a .privateKey, but because isNC=true it will look up in NIP46SecretManager for a session private key and use that instead
        guard let sessionPrivateKey = account.privateKey else { return }
        guard let keys = try? NKeys(privateKeyHex: sessionPrivateKey) else { return }
        
        var unsignedEvent = event
        unsignedEvent.publicKey = account.publicKey
        let unsignedEventWithId = unsignedEvent.withId()
            
        let commandId = "sign-event-\(UUID().uuidString)"
        let request = NCRequest(id: commandId, method: "sign_event", params: [unsignedEventWithId.eventJson()])
        let encoder = JSONEncoder()
        
        guard let requestJsonData = try? encoder.encode(request) else { return }
        
        guard let requestJsonString = String(data: requestJsonData, encoding: .utf8) else { return }
        
        var ncReq = NEvent(content: requestJsonString)
        ncReq.kind = .ncMessage
        ncReq.tags.append(NostrTag(["p", account.publicKey]))
        
        guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex(), pubkey: account.publicKey, content: ncReq.content) else {
            L.og.error("🏰🔴🔴 Could not encrypt content")
            return
        }
        
        ncReq.content = encrypted
        
        guard let signedReq = try? ncReq.sign(keys) else { return }
        
        L.og.debug("🏰 ncReqSigned (encrypted): \(signedReq.wrappedEventJson())")
        
        if let whenSigned {
            responseCommmandQueue[commandId] = whenSigned
        }
        
        // Make sure "NC" subscription is active
        reqP(RM.getNCResponses(pubkey: keys.publicKeyHex(), bunkerPubkey: account.publicKey, subscriptionId: "NC"), activeSubscriptionId: "NC")
        
        // Send message to nsecBunker, ping first for reliability
        SocketPool.shared.sendMessageAfterPing(ClientMessage(onlyForNCRelay: true, message: signedReq.wrappedEventJson()), accountPubkey: signedReq.publicKey)
    }
    
    
    public func describe() {
        guard let account = Thread.isMainThread ? account : account?.toBG() else { return }
        
        // account does not have a .privateKey, but because isNC=true it will look up in NIP46SecretManager for a session private key and use that instead
        guard let sessionPrivateKey = account.privateKey else { return }
        guard let keys = try? NKeys(privateKeyHex: sessionPrivateKey) else { return }
            
        let commandId = "describe-\(UUID().uuidString)"
        let request = NCRequest(id: commandId, method: "describe", params: [])
        let encoder = JSONEncoder()
        
        guard let requestJsonData = try? encoder.encode(request) else { return }
        
        guard let requestJsonString = String(data: requestJsonData, encoding: .utf8) else { return }
        
        var ncReq = NEvent(content: requestJsonString)
        ncReq.kind = .ncMessage
        ncReq.tags.append(NostrTag(["p", account.publicKey]))
        
        guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex(), pubkey: account.publicKey, content: ncReq.content) else {
            L.og.error("🏰🔴🔴 Could not encrypt content")
            return
        }
        
        ncReq.content = encrypted
        
        guard let signedReq = try? ncReq.sign(keys) else { return }
        
        L.og.debug("🏰 ncReqSigned (encrypted): \(signedReq.wrappedEventJson())")
        
        // Make sure "NC" subscription is active
        reqP(RM.getNCResponses(pubkey: keys.publicKeyHex(), bunkerPubkey: account.publicKey, subscriptionId: "NC"), activeSubscriptionId: "NC")
        
        // Send message to nsecBunker, ping first for reliability
        SocketPool.shared.sendMessageAfterPing(ClientMessage(onlyForNCRelay: true, message: signedReq.wrappedEventJson()), accountPubkey: signedReq.publicKey)
    }
    
    private func handleSignedEvent(eventString:String) {
        L.og.info("🏰 NSECBUNKER signed event received, ready to publish: \(eventString)")
        let accountPubkey = parsePubkey(eventString)
        SocketPool.shared.sendMessage(ClientMessage(message: "[\"EVENT\",\(eventString)"), accountPubkey: accountPubkey)
    }
    
    enum STATE {
        case disconnected
        case connecting
        case connected
        case error
    }
}

func parsePubkey(_ eventString:String) -> String? {
    guard let dataFromString = eventString.data(using: .utf8, allowLossyConversion: false) else {
        return nil
    }
    let decoder = JSONDecoder()
    if let mMessage = try? decoder.decode(MinimalMessage.self, from: dataFromString) {
        return mMessage.pubkey
    }
    return nil
}
