//
//  OneOffEventPublisher.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/08/2025.
//

import Foundation

class OneOffEventPublisher: NSObject, URLSessionWebSocketDelegate {
    private let url: URL
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession!
    
    private var openErrorContinuation: CheckedContinuation<Void, Error>?
    
    private var expectedEventId: String?
    private var sentEventFirstResponseContinuation: CheckedContinuation<EventResponse, Never>?
    
    private var expectedAuthResponseId: String?
    private var sentAuthResponseContinuation: CheckedContinuation<EventResponse, Never>?

    private var sentEventAfterAuthResponseContinuation: CheckedContinuation<EventResponse, Never>?
    private var didSendAfterAuth = false
    
    private var authRequiredForEventId: String?
    public var eventsThatMayNeedAuth: [String: String] = [:] // [ post id : event message text string ]
    
    init(_ urlString: String, signNEventHandler: @escaping (NEvent) async throws -> NEvent) {
        self.url = URL(string: urlString)!
        self.signNEventHandler = signNEventHandler
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }
    
    private var signNEventHandler: (NEvent) async throws -> NEvent
    
    // MARK: - Connect
    func connect(timeout: TimeInterval = 10) async throws {
        let task = session.webSocketTask(with: url)
        self.webSocket = task
        task.resume()
        
        // Wait until didOpen fires with timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SendMessageError.timeout
            }
            
            // Add connection waiting task
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self.openErrorContinuation = cont
                }
            }
            
            // Return first result and cancel the other
            try await group.next()
            group.cancelAll()
        }
        
        // Start listener
        Task {
            await self.listen()
        }
    }
    
    // MARK: - Delegate
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        openErrorContinuation?.resume()
        openErrorContinuation = nil
#if DEBUG
        L.og.debug("WebSocket connected ✅")
#endif
    }
    
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        // Clean up any pending continuations on connection close
        openErrorContinuation?.resume(throwing: SendMessageError.timeout)
        openErrorContinuation = nil
        
        resumeContinuation(&sentEventFirstResponseContinuation, with: EventResponse.failReason("Connection closed"))
        resumeContinuation(&sentAuthResponseContinuation, with: EventResponse.failReason("Connection closed"))
        resumeContinuation(&sentEventAfterAuthResponseContinuation, with: EventResponse.failReason("Connection closed"))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Connection failed - throw the actual error
            openErrorContinuation?.resume(throwing: error)
            openErrorContinuation = nil
            
            resumeContinuation(&sentEventFirstResponseContinuation, with: EventResponse.failReason("Connection error: \(error)"))
            resumeContinuation(&sentAuthResponseContinuation, with: EventResponse.failReason("Connection error: \(error)"))
            resumeContinuation(&sentEventAfterAuthResponseContinuation, with: EventResponse.failReason("Connection error: \(error)"))
        }
    }
    
    // MARK: - Listen
    private func listen() async {
        guard let ws = webSocket else { return }
        while true {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    await handleIncomingMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleIncomingMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
#if DEBUG
                L.og.debug("🔴 WebSocket listen error: \(error)")
#endif
                
                // Clean up any pending continuations on listen error
                resumeContinuation(&sentEventFirstResponseContinuation, with: EventResponse.failReason("Listen error: \(error)"))
                resumeContinuation(&sentAuthResponseContinuation, with: EventResponse.failReason("Listen error: \(error)"))
                resumeContinuation(&sentEventAfterAuthResponseContinuation, with: EventResponse.failReason("Listen error: \(error)"))
                break
            }
        }
    }
    
    private func handleIncomingMessage(_ text: String) async {
#if DEBUG
        L.og.debug("🟠 Received: \(text)")
#endif
        do {
            let message = try RelayMessage.parseRelayMessage(text: text, relay: self.url.absoluteString)
            
            switch message.type {
            case .AUTH:
                saveAuthChallenge(message.message)
                do {
                    try await sendAuthResponse()
                } catch {
                    // Auth response send failed - this is logged but doesn't affect continuations
                    // since sentAuthResponseContinuation isn't set until we wait for the auth response
#if DEBUG
                    L.og.debug("🔴 sendAuthResponse failed: \(error)")
#endif
                }
            case .OK:
                // EVENT RESPONSE
                if let eventId = message.id, let expectedEventId, expectedEventId == eventId { // Should be first response after sending the EVENT
                    if !didSendAfterAuth { // Response after we sent event without sending auth
                        if message.success ?? false { // Success? We are finished
                            resumeContinuation(&sentEventFirstResponseContinuation, with: EventResponse.ok(eventId))
                        }
                        else if message.message.prefix(14) == "auth-required:" { // Auth required, send auth response using the token we should already have
                            resumeContinuation(&sentEventFirstResponseContinuation, with: EventResponse.authRequired(eventId))
                        }
                        else {
                            resumeContinuation(&sentEventFirstResponseContinuation, with: EventResponse.failReason(message.message))
                        }
                    }
                    else { // Response after we sent event after auth was already sent
                        if message.success ?? false { // Success? We are finished
                            resumeContinuation(&sentEventAfterAuthResponseContinuation, with: EventResponse.ok(eventId))
                        }
                        else {
                            resumeContinuation(&sentEventAfterAuthResponseContinuation, with: EventResponse.failReason(message.message))
                        }
                    }
                }
                
                // AUTH RESPONSE EVENT
                else if let eventId = message.id, let expectedAuthResponseId, expectedAuthResponseId == eventId { // Should be the AUTH response
                    if message.success ?? false { // Success? We are finished
                        resumeContinuation(&sentAuthResponseContinuation, with: EventResponse.ok(eventId))
                    }
                    else {
                        resumeContinuation(&sentAuthResponseContinuation, with: EventResponse.failReason(message.message))
                    }
                }
                // Unexpected OK message - might indicate we're in an invalid state
                else {
#if DEBUG
                    L.og.debug("🟠 Unexpected OK message for event ID: \(message.id ?? "nil"), expected: \(self.expectedEventId ?? "nil") or \(self.expectedAuthResponseId ?? "nil")")
#endif
                }

            case .CLOSED:
                break
            default:
                break
            }
        }
        catch {
#if DEBUG
            L.sockets.info("🔴🔴 Message parsing error: \(error)")
#endif
            // Clean up continuations on parsing errors - we might be in an invalid state
            resumeContinuation(&sentEventFirstResponseContinuation, with: EventResponse.failReason("Message parsing error: \(error)"))
            resumeContinuation(&sentAuthResponseContinuation, with: EventResponse.failReason("Message parsing error: \(error)"))
            resumeContinuation(&sentEventAfterAuthResponseContinuation, with: EventResponse.failReason("Message parsing error: \(error)"))
        }
    }
    
    func sendAuthResponse() async throws {
        // Need to already have auth challenge, and never send twice
        guard let authChallenge, !didSendAuth else { return }
#if DEBUG
        L.og.debug("🔑 Creating auth response for challenge: \(authChallenge)")
#endif
        let unsignedAuthResponse = NEvent(
            content: "",
            kind: .auth, tags: [
                NostrTag(["relay", self.url.absoluteString]),
                NostrTag(["challenge", authChallenge])
            ])
        let signedAuthResponse = try await signNEventHandler(unsignedAuthResponse)
        expectedAuthResponseId = signedAuthResponse.id
        didSendAuth = true
        try await sendMessage(ClientMessage.auth(event: signedAuthResponse))
#if DEBUG
        L.og.debug("🔑 Sent AUTH response for challenge: \(authChallenge) with id: \(signedAuthResponse.id) 🔑")
#endif
    }
    
    private func waitForEventResponse(timeout: TimeInterval, setContinuation: @escaping (CheckedContinuation<EventResponse, Never>) -> Void) async throws -> EventResponse {
        return try await withThrowingTaskGroup(of: EventResponse.self) { group in
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .timeout
            }
            
            // Add response waiting task
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<EventResponse, Never>) in
                    setContinuation(cont)
                }
            }
            
            // Return first result and cancel the other
            guard let result = try await group.next() else {
                throw SendMessageError.timeout
            }
            group.cancelAll()
            
            if case .timeout = result {
                throw SendMessageError.timeout
            }
            
            return result
        }
    }
    
    // Helper to safely resume continuation only once
    private func resumeContinuation<T>(_ continuation: inout CheckedContinuation<T, Never>?, with value: T) {
        continuation?.resume(returning: value)
        continuation = nil
    }
    
    public func publish(_ nEvent: NEvent, timeout: TimeInterval = 10) async throws {
        try await sendEvent(nEvent)
        
        // Wait for first OK response (true or auth-required:)
        let response: EventResponse = try await waitForEventResponse(timeout: timeout) { continuation in
            self.sentEventFirstResponseContinuation = continuation
        }
        
        switch response {
        case .ok:
#if DEBUG
            L.og.debug("✅✅ One Shotted! ✅✅")
#endif
            break
        case .authRequired(let eventId):
            authRequiredForEventId = eventId
#if DEBUG
            L.og.debug("🔑 Auth required for event id: \(eventId) 🔑")
#endif
            if !didSendAuth { // did not send auth yet
                do {
                    try await sendAuthResponse()
                    
                    let authResponse: EventResponse = try await waitForEventResponse(timeout: timeout) { continuation in
                        self.sentAuthResponseContinuation = continuation
                    }
                    
                    switch authResponse {
                    case .ok:
                        // Auth successful, now retry the event
                        didSendAfterAuth = true
                        do {
                            try await sendEvent(nEvent)
                            
                            let retryResponse: EventResponse = try await waitForEventResponse(timeout: timeout) { continuation in
                                self.sentEventAfterAuthResponseContinuation = continuation
                            }
                    
                            switch retryResponse {
                            case .ok:
#if DEBUG
                                L.og.debug("✅ Success on retry after auth ✅")
#endif
                                break
                            case .authRequired(let eventId):
#if DEBUG
                                L.og.debug("❌ Still failing on retry (auth-required for: \(eventId)) ❌")
#endif
                                throw SendMessageError.sendFailed
                            case .failReason(let reason):
#if DEBUG
                                L.og.debug("❌ Still failing on retry - \(reason) ❌")
#endif
                                throw SendMessageError.sendFailed
                            case .timeout:
#if DEBUG
                                L.og.debug("❌ Timeout on retry ❌")
#endif
                                throw SendMessageError.timeout
                            }
                        } catch {
#if DEBUG
                            L.og.debug("❌ Failed to send retry event: \(error) ❌")
#endif
                            throw SendMessageError.sendFailed
                        }
                    case .failReason(let reason):
#if DEBUG
                    L.og.debug("❌ Auth failed - \(reason) ❌")
#endif
                        throw SendMessageError.sendFailed
                    case .timeout:
#if DEBUG
                    L.og.debug("❌ Auth timeout ❌")
#endif
                        throw SendMessageError.timeout
                    case .authRequired:
#if DEBUG
                    L.og.debug("❌ Auth still required ❌")
#endif
                        throw SendMessageError.sendFailed
                    }
                } catch {
#if DEBUG
                    L.og.debug("❌ Failed to send auth response: \(error) ❌")
#endif
                    throw SendMessageError.sendFailed
                }
            }
            else { // already sent auth, try again
                didSendAfterAuth = true
                do {
                    try await sendEvent(nEvent)
                    
                    // Wait for OK response (After auth should have been sent)
                    let response: EventResponse = try await waitForEventResponse(timeout: timeout) { continuation in
                        self.sentEventAfterAuthResponseContinuation = continuation
                    }
                    switch response {
                    case .ok:
#if DEBUG
                        L.og.debug("✅ Success on second attempt (after auth-required) ✅")
#endif
                        break
                    case .authRequired(let eventId):
#if DEBUG
                        L.og.debug("❌ Still failing on second attempt (auth-required for: \(eventId)) ❌")
#endif
                        throw SendMessageError.sendFailed
                    case .failReason(let reason):
#if DEBUG
                        L.og.debug("❌ Still failing on second attempt - \(reason) ❌")
#endif
                        throw SendMessageError.sendFailed
                    case .timeout:
#if DEBUG
                        L.og.debug("❌ Timeout on second attempt ❌")
#endif
                        throw SendMessageError.timeout
                    }
                } catch {
#if DEBUG
                    L.og.debug("❌ Failed to send second attempt event: \(error) ❌")
#endif
                    throw SendMessageError.sendFailed
                }
            }
            
        case .failReason(let reason):
#if DEBUG
            L.og.debug("❌ Failed \(reason)")
#endif
            throw SendMessageError.sendFailed
        case .timeout:
#if DEBUG
            L.og.debug("❌ Timeout waiting for initial response ❌")
#endif
            throw SendMessageError.timeout
        }
    }
    
    private func sendEvent(_ nEvent: NEvent) async throws {
        eventsThatMayNeedAuth[nEvent.id] = "[\"EVENT\",\(nEvent.eventJson())]"
        expectedEventId = nEvent.id
        try await sendMessage("[\"EVENT\",\(nEvent.eventJson())]")
    }
    
    // MARK: - Send
    private func sendMessage(_ text: String) async throws {
        guard let ws = webSocket else { throw SendMessageError.notConnected }
        
        do {
            try await ws.send(.string(text))
#if DEBUG
            L.og.debug("🔵 Sent: \(text)")
#endif
        } catch {
            throw SendMessageError.sendFailed
        }
    }
    
    private var authChallenge: String?
    private var didSendAuth = false
    
    // Handle ["AUTH","b56299da6987e6ec"]
    // Never needed more than once
    func saveAuthChallenge(_ message: String) {
        guard let messageData = message.data(using: .utf8) else { return }
        
        let decoder = JSONDecoder()
        guard let authMessage: [String] = try? decoder.decode([String].self, from: messageData),
              authMessage.count >= 2,
              authMessage[0] == "AUTH"
        else { return }
        
        self.authChallenge = authMessage[1]
    }
}

enum EventResponse {
    case ok(String) // id
    case authRequired(String) // reason/message
    case failReason(String) // reason/message
    case timeout
}

enum SendMessageError: Error {
    case notConnected
    case sendFailed
    case timeout
}
