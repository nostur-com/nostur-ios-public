//
//  NIP29Service.swift
//  Nostur
//

import Combine
import Foundation

@MainActor
final class NIP29Service: ObservableObject {
    static let shared = NIP29Service()

    let store: NIP29Store

    private final class Session {
        let key: NIP29SessionKey
        let transport: NIP29RelayTransport
        var addresses: Set<NIP29GroupAddress> = []
        var addressBySubscriptionId: [String: NIP29GroupAddress] = [:]
        var pendingAuthEventId: String?
        var pendingPublishedMessages: [String: String] = [:]
        var state: NIP29ConnectionState = .disconnected

        init(key: NIP29SessionKey, transport: NIP29RelayTransport) {
            self.key = key
            self.transport = transport
        }
    }

    private var sessions: [NIP29SessionKey: Session] = [:]
    private let transportFactory: (NIP29SessionKey) -> NIP29RelayTransport

    init(
        store: NIP29Store? = nil,
        transportFactory: @escaping (NIP29SessionKey) -> NIP29RelayTransport = {
            NIP29WebSocketTransport(relayURL: $0.relayURL)
        }
    ) {
        self.store = store ?? NIP29Store()
        self.transportFactory = transportFactory
    }

    func subscribe(to address: NIP29GroupAddress, accountPubkey: String) throws {
        guard !address.groupId.isEmpty else { throw NIP29Error.emptyGroupId }
        guard Self.isValidRelayURL(address.relayURL) else { throw NIP29Error.invalidRelayURL }

        let key = NIP29SessionKey(relayURL: address.relayURL, accountPubkey: accountPubkey)
        let session = session(for: key)
        guard !session.addresses.contains(address) else { return }

        let subscriptionId = Self.subscriptionId(for: address)
        session.addresses.insert(address)
        session.addressBySubscriptionId[subscriptionId] = address
        store.prepare(address)
        if session.state == .connected {
            session.transport.send(
                NIP29Protocol.subscriptionMessage(address: address, subscriptionId: subscriptionId)
            )
        } else {
            session.transport.connect()
        }
    }

    func unsubscribe(from address: NIP29GroupAddress, accountPubkey: String) {
        let key = NIP29SessionKey(relayURL: address.relayURL, accountPubkey: accountPubkey)
        guard let session = sessions[key] else { return }
        let subscriptionId = Self.subscriptionId(for: address)
        session.transport.send(NIP29Protocol.closeMessage(subscriptionId: subscriptionId))
        session.addresses.remove(address)
        session.addressBySubscriptionId.removeValue(forKey: subscriptionId)
        if session.addresses.isEmpty {
            session.transport.disconnect()
            sessions.removeValue(forKey: key)
        }
    }

    func sendChat(_ content: String, to address: NIP29GroupAddress, accountPubkey: String) throws {
        let previousIds = store.previousEventIds(for: address, excludingPubkey: accountPubkey)
        try publish(
            NIP29Protocol.chatEvent(content: content, address: address, previousEventIds: previousIds),
            to: address,
            accountPubkey: accountPubkey
        )
    }

    func requestJoin(
        _ address: NIP29GroupAddress,
        accountPubkey: String,
        inviteCode: String? = nil,
        reason: String = ""
    ) throws {
        try publish(
            NIP29Protocol.joinRequest(address: address, inviteCode: inviteCode, reason: reason),
            to: address,
            accountPubkey: accountPubkey
        )
    }

    func requestLeave(_ address: NIP29GroupAddress, accountPubkey: String, reason: String = "") throws {
        try publish(
            NIP29Protocol.leaveRequest(address: address, reason: reason),
            to: address,
            accountPubkey: accountPubkey
        )
    }

    private func session(for key: NIP29SessionKey) -> Session {
        if let existing = sessions[key] { return existing }
        let transport = transportFactory(key)
        let session = Session(key: key, transport: transport)
        transport.onTextFrame = { [weak self, weak session] text in
            guard let session else { return }
            do {
                let frame = try NIP29RelayFrame.parse(text)
                if case .event(_, let event) = frame, (try? event.verified()) != true { return }
                DispatchQueue.main.async {
                    self?.handle(frame, from: session)
                }
            } catch {
#if DEBUG
                L.sockets.debug("NIP-29 frame parse failed from \(session.key.relayURL): \(error.localizedDescription)")
#endif
            }
        }
        transport.onStateChange = { [weak self, weak session] state in
            DispatchQueue.main.async {
                guard let self, let session else { return }
                self.handle(state, for: session)
            }
        }
        sessions[key] = session
        return session
    }

    private func handle(_ state: NIP29ConnectionState, for session: Session) {
        session.state = state
        store.setConnectionState(state, for: session.addresses)
        guard state == .connected else { return }
        for (subscriptionId, address) in session.addressBySubscriptionId {
            session.transport.send(
                NIP29Protocol.subscriptionMessage(address: address, subscriptionId: subscriptionId)
            )
        }
    }

    private func handle(_ frame: NIP29RelayFrame, from session: Session) {
        switch frame {
            case .auth(let challenge):
                sendAuth(challenge: challenge, on: session)
            case .event(let subscriptionId, let event):
                guard let address = session.addressBySubscriptionId[subscriptionId] else { return }
                store.ingest(event, from: address, accountPubkey: session.key.accountPubkey)
            case .eose(let subscriptionId):
                guard let address = session.addressBySubscriptionId[subscriptionId] else { return }
                store.markEOSE(for: address)
            case .ok(let eventId, let accepted, let message):
                if session.pendingAuthEventId == eventId {
                    session.pendingAuthEventId = nil
                    if accepted {
                        restoreSubscriptions(on: session)
                        for pendingMessage in session.pendingPublishedMessages.values {
                            session.transport.send(pendingMessage)
                        }
                    }
                    return
                }
                if accepted {
                    session.pendingPublishedMessages.removeValue(forKey: eventId)
                    return
                }
                if !message.hasPrefix("auth-required:") {
                    session.pendingPublishedMessages.removeValue(forKey: eventId)
                }
                for address in session.addresses { store.setError(message, for: address) }
            case .closed(let subscriptionId, let message):
                guard let address = session.addressBySubscriptionId[subscriptionId] else { return }
                store.setError(message, for: address)
            case .notice(let message):
                guard !message.isEmpty else { return }
                for address in session.addresses { store.setError(message, for: address) }
        }
    }

    private func publish(_ event: NEvent, to address: NIP29GroupAddress, accountPubkey: String) throws {
        guard NIP29Protocol.groupId(in: event) == address.groupId else {
            throw NIP29Error.eventDoesNotBelongToGroup
        }
        let key = NIP29SessionKey(relayURL: address.relayURL, accountPubkey: accountPubkey)
        try subscribe(to: address, accountPubkey: accountPubkey)
        guard let session = sessions[key] else { return }
        sign(event, accountPubkey: key.accountPubkey) { [weak self, weak session] result in
            guard let self, let session else { return }
            switch result {
            case .success(let signedEvent):
                guard signedEvent.publicKey == session.key.accountPubkey else {
                    self.store.setError(NIP29Error.eventPubkeyDoesNotMatchSession.localizedDescription, for: address)
                    return
                }
                let message = NIP29Protocol.eventMessage(signedEvent)
                session.pendingPublishedMessages[signedEvent.id] = message
                session.transport.send(message)
            case .failure(let error):
                self.store.setError(error.localizedDescription, for: address)
            }
        }
    }

    private func sendAuth(challenge: String, on session: Session) {
        let event = NEvent(
            content: "",
            kind: .auth,
            tags: [
                NostrTag(["relay", session.key.relayURL]),
                NostrTag(["challenge", challenge])
            ]
        )
        sign(event, accountPubkey: session.key.accountPubkey) { [weak session] result in
            guard let session, case .success(let signedEvent) = result else { return }
            session.pendingAuthEventId = signedEvent.id
            session.transport.send(NIP29Protocol.authMessage(signedEvent))
        }
    }

    private func restoreSubscriptions(on session: Session) {
        for (subscriptionId, address) in session.addressBySubscriptionId {
            session.transport.send(
                NIP29Protocol.subscriptionMessage(address: address, subscriptionId: subscriptionId)
            )
        }
    }

    private func sign(
        _ event: NEvent,
        accountPubkey: String,
        completion: @escaping (Result<NEvent, Error>) -> Void
    ) {
        guard let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) else {
            completion(.failure(NIP29Error.accountUnavailable))
            return
        }
        guard account.isFullAccount else {
            completion(.failure(NIP29Error.accountCannotSign))
            return
        }
        if account.isNC {
            var eventWithId = event
            eventWithId = eventWithId.withId()
            RemoteSignerManager.shared.requestSignature(forEvent: eventWithId, usingAccount: account) {
                completion(.success($0))
            }
        } else {
            do {
                completion(.success(try account.signEvent(event)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func subscriptionId(for address: NIP29GroupAddress) -> String {
        let stableHash = address.id.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return "NIP29-\(String(stableHash, radix: 16))"
    }

    private static func isValidRelayURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "ws" || scheme == "wss") && url.host != nil
    }
}
