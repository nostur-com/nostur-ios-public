//
//  NSecBunkerManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/06/2023.
//

import Foundation
import Combine
import NostrEssentials

// TODO: The happy paths works fine, but need to handle errors, timeouts, etc and notify user instead of silent fail.
class NSecBunkerManager: ObservableObject {
    
    static let shared = NSecBunkerManager()
    
    @Published var state: STATE = .disconnected
    @Published var error = ""
    @Published var ncRelay = ""
    
    var invalidRelayAddress: Bool {
        if let url = URL(string: ncRelay) {
            if url.absoluteString.lowercased().prefix(6) == "wss://" { return false }
            if url.absoluteString.lowercased().prefix(5) == "ws://" { return false }
        }
        return true
    }
    
    var backlog = Backlog(timeout: 15, auto: true)
    let decoder = JSONDecoder()
    var account: CloudAccount? = nil
    var subscriptions = Set<AnyCancellable>()
    
    // Queue of commands to execute when we receive a response
    var responseCommmandQueue: [String: (NEvent) -> Void] = [:] // TODO: need to add clean up, timeout...
    
    private init() {
        listenForNCMessages()
    }
    
    private func listenForNCMessages() {
        receiveNotification(.receivedMessage)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let message = notification.object as! RelayMessage
                guard let event = message.event else { return }
                guard event.kind == .ncMessage else { return }
                guard let account = self.account else { return }
                guard let sessionPrivateKey = account.privateKey else { return }
             
                guard let decrypted = Keys.decryptDirectMessageContent(withPrivateKey: sessionPrivateKey, pubkey: event.publicKey, content: event.content) ?? Keys.decryptDirectMessageContent44(withPrivateKey: sessionPrivateKey, pubkey: event.publicKey, content: event.content) else {
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
#if DEBUG
                        L.og.error("🏰 NSECBUNKER Unknown or missing result \(decrypted) ")
#endif
                        return
                    }
                    
                    guard let nEvent = try? decoder.decode(NEvent.self, from: result.data(using: .utf8)!) else {
#if DEBUG
                        L.og.error("🏰 NSECBUNKER error decoding signed result event \(decrypted)")
#endif
                        return
                    }
                    command(nEvent)
                    responseCommmandQueue[ncResponse.id] = nil
                    return
                }
                
                // CONNECT RESPONSE
                if ncResponse.id.prefix(8) == "connect-" {
                    guard let result = ncResponse.result else {
#if DEBUG
                        L.og.error("🏰 ncMessage does not have result, \(event.eventJson()) - \(decrypted)")
#endif
                        return
                    }
                    if result == "auth_url" { // ugh need useless OAuth like flow now
                        DispatchQueue.main.async {
                            self.state = .connected
                            L.og.debug("🏰 NSECBUNKER connection needs auth_url oauth type handling ")
#if DEBUG
                            L.og.info("🏰 result: \(result) -- \(event.eventJson()) - \(decrypted)")
#endif
                            self.getPublicKey()
                        }
                    }                   
                    else if result == "ack" {
                        DispatchQueue.main.async {
                            self.state = .connected
                            L.og.debug("🏰 NSECBUNKER ack success ")
                            self.getPublicKey()
                        }
                    }
                    else {
                        DispatchQueue.main.async {
                            self.error = "Unable to connect"
                            self.state = .error
#if DEBUG
                                L.og.error("🏰 result: \(result) -- \(event.eventJson()) - \(decrypted)")
#endif
                        }
                    }
                }
                
                // DESCRIBE RESPONSE - Using this to check connectivity
                else if ncResponse.id.prefix(9) == "describe-" {
                    guard let result = ncResponse.result else {
#if DEBUG
                        L.og.error("🏰 ncMessage does not have result, \(event.eventJson()) - \(decrypted)")
#endif
                        return
                    }
                    if result.contains("\"describe\"") { // should be something like "[\"connect\",\"sign_event\",\"nip04_encrypt\",\"nip04_decrypt\",\"get_public_key\",\"describe\",\"publish_event\"]"
                        DispatchQueue.main.async {
                            self.state = .connected
                            L.og.debug("🏰 NSECBUNKER connection success ")
#if DEBUG
                            L.og.debug("🏰 result: \(result) -- \(event.eventJson()) - \(decrypted)")
#endif
                        }
                    }
                }
                
                // GET_PUBLIC_KEY RESPONSE - Using this to check connectivity as alternative for when "describe" is not available (nak bunker)
                else if ncResponse.id.prefix(15) == "get_public_key-" {
                    guard let result = ncResponse.result else {
#if DEBUG
                        L.og.error("🏰 ncMessage does not have result, \(event.eventJson()) - \(decrypted)")
#endif
                        return
                    }
                    if isValidPubkey(result) { // should be a valid pubkey
                        // override
                        DispatchQueue.main.async {
                            guard let account = self.account else { return }
                            
                            // response from remote bunker pubkey should be this accounts .ncRemoteSignerPubkey
                            guard account.ncRemoteSignerPubkey == event.publicKey else { return }
                            
                            guard account.publicKey != result else {
                                self.state = .connected
                                L.og.info("🏰 NSECBUNKER get_public_key success, but pubkey is already set to set to: \(account.publicKey)")
                                return
                            }

                            // use the new pubkey received from bunker
                            let oldAccountPubkey = account.publicKey
                            account.publicKey = result
                            viewContextSave()
                            
                            if NRState.shared.activeAccountPublicKey == oldAccountPubkey {
                                NRState.shared.activeAccountPublicKey = result
                                NRState.shared.loggedInAccount?.pubkey = result
                                
                                NRState.shared.loadAccountsState() // Need load account because pubkey changed
                            }
                            
                            self.state = .connected
                            L.og.info("🏰 NSECBUNKER get_public_key success, pubkey set to: \(account.publicKey)")
                        }
                    }
#if DEBUG
                    L.og.debug("🏰 result: \(result) -- \(event.eventJson()) - \(decrypted)")
#endif
                }
                
                // SIGNED EVENT RESPONSE
                else if ncResponse.id.prefix(11) == "sign-event-" {
                    // SIGNED EVENT RESPONSE
                    if let error = ncResponse.error {
                        L.og.error("🏰 NSECBUNKER error signing event: \(error) ")
                        return
                    }
                    guard let result = ncResponse.result else {
#if DEBUG
                        L.og.error("🏰 NSECBUNKER Unknown or missing result \(decrypted) ")
#endif
                        return
                    }
                    self.handleSignedEvent(eventString:result)
                }
            }
            .store(in: &subscriptions)
    }
    
    @MainActor
    private func connectToBunker(sessionPublicKey: String, relay: String) {
        ConnectionPool.shared.addNCConnection(connectionId: sessionPublicKey, url: relay) { conn in
            if !conn.isConnected {
                conn.connect()
            }
        }
    }
    
    public func setAccount(_ account: CloudAccount) {
        self.account = account
        guard let sessionPrivateKey = account.privateKey else { return }
        guard let keys = try? Keys(privateKeyHex: sessionPrivateKey) else { return }
        // connect to NC relay, the session public key is used as id
        if account.ncRelay != "" {
            Task { @MainActor in
                self.connectToBunker(sessionPublicKey: keys.publicKeyHex, relay: account.ncRelay)
            }
        }
    }
    
    public func connect(_ account: CloudAccount, token: String? = nil) {
        // When the connection is made, we set ns.setAccount with connectingAccount
        state = .connecting
        self.account = account
        
        // Generate session key, the private key is stored in keychain, it will be accessed by looking up (account.ncClientPubkey_ ?? account.publicKey) in the NC keychain
        guard let ncClientPubkey = try? NIP46SecretManager.shared.generateKeysForAccount(account) else {
            state = .error; return 
        }
        
        account.isNC = true
        account.ncClientPubkey_ = ncClientPubkey // need to listen for NC messages on this (can be different from user pubkey)
        let ncRemoteSignerPubkey = account.ncRemoteSignerPubkey
        
        // account does not have a .privateKey, but because isNC=true it will look up in NIP46SecretManager for a session private key and use that instead
        guard let sessionPrivateKey = account.privateKey else { state = .error; return }
        guard let keys = try? Keys(privateKeyHex: sessionPrivateKey) else { state = .error; return }
        
        // connect to NC relay, the ncRemoteSignerPubkey is used as id
        Task { @MainActor in
            self.connectToBunker(sessionPublicKey: ncRemoteSignerPubkey, relay: self.ncRelay)
        }
        
        // the connect request, params are remote signer public key (used to be user pubkey) and the bunker provided redemption token
        let request = if let token {
            NCRequest(id: "connect-\(UUID().uuidString)", method: "connect", params: [ncRemoteSignerPubkey, token])
        }
        else {
            NCRequest(id: "connect-\(UUID().uuidString)", method: "connect", params: [ncRemoteSignerPubkey])
        }
        let encoder = JSONEncoder()
        
        guard let requestJsonData = try? encoder.encode(request) else { state = .error; return }
        
        guard let requestJsonString = String(data: requestJsonData, encoding: .utf8) else { state = .error; return }
        
        var ncReq = NEvent(content: requestJsonString)
        ncReq.kind = .ncMessage
        ncReq.tags.append(NostrTag(["p", ncRemoteSignerPubkey]))
        
#if DEBUG
        L.og.debug("🏰 ncReq (unencrypted): \(ncReq.eventJson())")
#endif
        
        guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex, pubkey: ncRemoteSignerPubkey, content: ncReq.content) else {
            L.og.error("🏰 🔴🔴 Could not encrypt content for ncMessage")
            return
        }
        
        ncReq.content = encrypted
        
        guard let signedReq = try? ncReq.sign(keys) else { state = .error; return }
        
        L.og.debug("🏰 ncReqSigned (encrypted): \(signedReq.wrappedEventJson())")
        
        // Wait 2.5 seconds for NC connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // Setup the NC subscription that listens for NC messages
            // filter: authors (remote signer pubkey), #p (our session pubkey)
            req(RM.getNCResponses(pubkey: keys.publicKeyHex, bunkerPubkey: ncRemoteSignerPubkey, subscriptionId: "NC"), activeSubscriptionId: "NC")
            
            // Send connection request
            ConnectionPool.shared.sendMessage(
                NosturClientMessage(
                    clientMessage: NostrEssentials.ClientMessage(type: .EVENT),
                    onlyForNCRelay: true,
                    relayType: .READ,
                    nEvent: signedReq
                ),
                accountPubkey: account.publicKey
            )
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
        guard let account = (usingAccount ?? account) else { return }
        
        // account does not have a .privateKey, but because isNC=true it will look up in NIP46SecretManager for a session private key and use that instead
        guard let sessionPrivateKey = account.privateKey else { return }
        guard let keys = try? Keys(privateKeyHex: sessionPrivateKey) else { return }
        
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
        ncReq.tags.append(NostrTag(["p", account.ncRemoteSignerPubkey]))
#if DEBUG
        L.og.debug("🏰 ncReq (unencrypted): \(ncReq.eventJson())")
#endif
        
        guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex, pubkey: account.ncRemoteSignerPubkey, content: ncReq.content) else {
            L.og.error("🏰🔴🔴 Could not encrypt content")
            return
        }
        
        ncReq.content = encrypted
        
        guard let signedReq = try? ncReq.sign(keys) else { return }
        
        L.og.debug("🏰 ncReqSigned (encrypted): \(signedReq.wrappedEventJson())")
        
        // set account so the response is decrypted using the correct account
        self.setAccount(account)
        
        if let whenSigned {
            responseCommmandQueue[commandId] = whenSigned
        }
        
        // Make sure "NC" subscription is active
        req(RM.getNCResponses(pubkey: keys.publicKeyHex, bunkerPubkey: account.ncRemoteSignerPubkey, subscriptionId: "NC"), activeSubscriptionId: "NC")
        
        // Send message to nsecBunker
        ConnectionPool.shared.sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(type: .EVENT),
                onlyForNCRelay: true,
                relayType: .READ,
                nEvent: signedReq
            ),
            accountPubkey: account.publicKey
        )
    }
    
    
    public func describe() {
        guard let account = Thread.isMainThread ? account : account?.toBG() else { return }
        
        // account does not have a .privateKey, but because isNC=true it will look up in NIP46SecretManager for a session private key and use that instead
        guard let sessionPrivateKey = account.privateKey else { return }
        guard let keys = try? Keys(privateKeyHex: sessionPrivateKey) else { return }
            
        let commandId = "describe-\(UUID().uuidString)"
        let request = NCRequest(id: commandId, method: "describe", params: [])
        let encoder = JSONEncoder()
        
        guard let requestJsonData = try? encoder.encode(request) else { return }
        
        guard let requestJsonString = String(data: requestJsonData, encoding: .utf8) else { return }
        
        var ncReq = NEvent(content: requestJsonString)
        ncReq.kind = .ncMessage
        ncReq.tags.append(NostrTag(["p", account.ncRemoteSignerPubkey]))
        
#if DEBUG
        L.og.debug("🏰 ncReq (unencrypted): \(ncReq.eventJson())")
#endif
        
        guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex, pubkey: account.ncRemoteSignerPubkey, content: ncReq.content) else {
            L.og.error("🏰🔴🔴 Could not encrypt content")
            return
        }
        
        ncReq.content = encrypted
        
        guard let signedReq = try? ncReq.sign(keys) else { return }
        
        L.og.debug("🏰 ncReqSigned (encrypted): \(signedReq.wrappedEventJson())")
        
        // Make sure "NC" subscription is active
        req(RM.getNCResponses(pubkey: keys.publicKeyHex, bunkerPubkey: account.ncRemoteSignerPubkey, subscriptionId: "NC"), activeSubscriptionId: "NC")
        
        // Send message to nsecBunker
        ConnectionPool.shared.sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(type: .EVENT),
                onlyForNCRelay: true,
                relayType: .READ,
                nEvent: signedReq
            ),
            accountPubkey: account.publicKey
        )
    }
    
    public func getPublicKey() {
        guard let account = Thread.isMainThread ? account : account?.toBG() else { return }
        
        // account does not have a .privateKey, but because isNC=true it will look up in NIP46SecretManager for a session private key and use that instead
        guard let sessionPrivateKey = account.privateKey else { return }
        guard let keys = try? Keys(privateKeyHex: sessionPrivateKey) else { return }
            
        let commandId = "get_public_key-\(UUID().uuidString)"
        let request = NCRequest(id: commandId, method: "get_public_key", params: [])
        let encoder = JSONEncoder()
        
        guard let requestJsonData = try? encoder.encode(request) else { return }
        
        guard let requestJsonString = String(data: requestJsonData, encoding: .utf8) else { return }
        
        var ncReq = NEvent(content: requestJsonString)
        ncReq.kind = .ncMessage
        ncReq.tags.append(NostrTag(["p", account.ncRemoteSignerPubkey]))

#if DEBUG
        L.og.debug("🏰 ncReq (unencrypted): \(ncReq.eventJson())")
#endif
        
        guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex, pubkey: account.ncRemoteSignerPubkey, content: ncReq.content) else {
            L.og.error("🏰🔴🔴 Could not encrypt content")
            return
        }
        
        ncReq.content = encrypted
        
        guard let signedReq = try? ncReq.sign(keys) else { return }
        
        L.og.debug("🏰 ncReqSigned (encrypted): \(signedReq.wrappedEventJson())")
        
        // Make sure "NC" subscription is active
        req(RM.getNCResponses(pubkey: keys.publicKeyHex, bunkerPubkey: account.ncRemoteSignerPubkey, subscriptionId: "NC"), activeSubscriptionId: "NC")
        
        // Send message to nsecBunker
        ConnectionPool.shared.sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(type: .EVENT),
                onlyForNCRelay: true,
                relayType: .READ,
                nEvent: signedReq
            ),
            accountPubkey: account.publicKey
        )
    }
    
    private func handleSignedEvent(eventString: String) {
        L.og.info("🏰 NSECBUNKER signed event received, ready to publish: \(eventString)")
        let accountPubkey = parsePubkey(eventString)
        
        ConnectionPool.shared.sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(type: .EVENT),
                relayType: .WRITE,
                message: "[\"EVENT\",\(eventString)"
            ),
            accountPubkey: accountPubkey
        ) // TODO: Outbox needs to know p's for inbox relays?
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
