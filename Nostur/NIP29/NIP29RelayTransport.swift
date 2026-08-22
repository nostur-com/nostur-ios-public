//
//  NIP29RelayTransport.swift
//  Nostur
//

import Foundation

protocol NIP29RelayTransport: AnyObject {
    var onTextFrame: ((String) -> Void)? { get set }
    var onStateChange: ((NIP29ConnectionState) -> Void)? { get set }

    func connect()
    func send(_ text: String)
    func disconnect()
}

final class NIP29WebSocketTransport: NSObject, NIP29RelayTransport, URLSessionWebSocketDelegate {
    var onTextFrame: ((String) -> Void)?
    var onStateChange: ((NIP29ConnectionState) -> Void)?

    private let relayURL: String
    private let queue: DispatchQueue
    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var pendingMessages: [String] = []
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var intentionallyDisconnected = false
    private var isConnected = false

    init(relayURL: String) {
        let normalizedRelayURL = normalizeRelayUrl(relayURL)
        self.relayURL = normalizedRelayURL
        self.queue = DispatchQueue(label: "nip29-relay-\(normalizedRelayURL)", qos: .userInitiated)
        super.init()
    }

    func connect() {
        queue.async { [weak self] in
            guard let self, self.webSocketTask == nil else { return }
            self.intentionallyDisconnected = false
            self.openSocket()
        }
    }

    func send(_ text: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isConnected, let webSocketTask = self.webSocketTask else {
                self.pendingMessages.append(text)
                if self.pendingMessages.count > 200 {
                    self.pendingMessages.removeFirst(self.pendingMessages.count - 200)
                }
                if self.webSocketTask == nil { self.openSocket() }
                return
            }
            self.send(text, using: webSocketTask)
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.intentionallyDisconnected = true
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.pendingMessages.removeAll()
            self.closeSocket()
            self.emitState(.disconnected)
        }
    }

    private func openSocket() {
        guard !intentionallyDisconnected,
              let url = URL(string: relayURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "ws" || scheme == "wss"),
              url.host != nil
        else {
            emitState(.failed(NIP29Error.invalidRelayURL.localizedDescription))
            return
        }

        emitState(.connecting)
        let delegateQueue = OperationQueue()
        delegateQueue.name = "nip29-urlsession-\(relayURL)"
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let task = session.webSocketTask(with: request)
        urlSession = session
        webSocketTask = task
        task.resume()
    }

    private func receiveNext() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .success(.string(let text)):
                    self.onTextFrame?(text)
                    self.receiveNext()
                case .success(.data(let data)):
                    if let text = String(data: data, encoding: .utf8) {
                        self.onTextFrame?(text)
                    }
                    self.receiveNext()
                case .failure(let error):
                    self.handleDisconnect(error: error)
                @unknown default:
                    self.handleDisconnect(error: nil)
                }
            }
        }
    }

    private func send(_ text: String, using webSocketTask: URLSessionWebSocketTask) {
        webSocketTask.send(.string(text)) { [weak self] error in
            guard let error else { return }
            self?.queue.async { self?.handleDisconnect(error: error) }
        }
    }

    private func flushPendingMessages() {
        guard let webSocketTask else { return }
        let messages = pendingMessages
        pendingMessages.removeAll(keepingCapacity: true)
        for message in messages { send(message, using: webSocketTask) }
    }

    private func handleDisconnect(error: Error?) {
        guard webSocketTask != nil || isConnected else { return }
        closeSocket()
        guard !intentionallyDisconnected else { return }
        if let error { emitState(.failed(error.localizedDescription)) }
        scheduleReconnect()
    }

    private func closeSocket() {
        isConnected = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    private func scheduleReconnect() {
        guard reconnectWorkItem == nil else { return }
        let delay = min(pow(2, Double(reconnectAttempt)), 60)
        reconnectAttempt += 1
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.openSocket()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func emitState(_ state: NIP29ConnectionState) {
        onStateChange?(state)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        queue.async { [weak self] in
            guard let self, self.webSocketTask === webSocketTask else { return }
            self.isConnected = true
            self.reconnectAttempt = 0
            self.emitState(.connected)
            self.flushPendingMessages()
            self.receiveNext()
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        queue.async { [weak self] in self?.handleDisconnect(error: nil) }
    }
}
