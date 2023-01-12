//
//  Nostr.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/01/2023.
//

import Foundation
import Starscream
import secp256k1

//extension String: Error {}

class Nostr : WebSocketDelegate {
    
    var socket: WebSocket!
    var isConnected = false
    let server = WebSocketServer()
    
    func connect(relayURL:String) -> Void {
        var request = URLRequest(url: URL(string: relayURL)!) //https://localhost:8080
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket.delegate = self
        socket.connect()
    }
    
    // MARK: - WebSocketDelegate
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            isConnected = true
            print("websocket is connected: \(headers)")
        case .disconnected(let reason, let code):
            isConnected = false
            print("websocket is disconnected: \(reason) with code: \(code)")
        case .text(let string):
            print("Received text: \(string)")
        case .binary(let data):
            print("Received data: \(data.count)")
        case .ping(_):
            break
        case .pong(_):
            break
        case .viabilityChanged(_):
            break
        case .reconnectSuggested(_):
            break
        case .cancelled:
            isConnected = false
        case .error(let error):
            isConnected = false
            handleError(error)
        }
    }
    
    func handleError(_ error: Error?) {
        if let e = error as? WSError {
            print("websocket encountered an error: \(e.message)")
        } else if let e = error {
            print("websocket encountered an error: \(e.localizedDescription)")
        } else {
            print("websocket encountered an error")
        }
    }
    
    // MARK: Write Text Action
    
    func writeText() {
        socket.write(string: "hello there!")
    }
    
    // MARK: Disconnect Action
    
    func disconnect() {
        if isConnected {
            socket.disconnect()
        } else {
            socket.connect()
        }
    }
    
    
}

public struct NTimestamp: Codable {
    public let timestamp: Int

    public init(date: Date) {
        self = .init(timestamp: Int(date.timeIntervalSince1970))
    }

    public init(timestamp: Int) {
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try timestamp = container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(timestamp)
    }
}

public enum NEventKind: Codable, Equatable {
    case setMetadata
    case textNote
    case recommentServer
    case custom(Int)

    init(id: Int) {
        switch id {
        case 0: self = .setMetadata
        case 1: self = .textNote
        case 2: self = .recommentServer
        default: self = .custom(id)
        }
    }

    var id: Int {
        switch self {
        case .setMetadata: return 0
        case .textNote: return 1
        case .recommentServer: return 2
        case .custom(let customId): return customId
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        self.init(id: try container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        try container.encode(self.id)
    }
}

public struct NEventTag: Codable {
    private let underlyingData: [String]

    public var id: String {
        return underlyingData.first!
    }

    public var otherInformation: [String] {
        return Array(underlyingData.suffix(from: 1))
    }

    public static func event(otherEventId: String, recommendedRelay: URL? = nil) -> NEventTag {
        return NEventTag(id: "e", otherInformation: otherEventId, recommendedRelay?.absoluteString)
    }

    public static func pubKey(publicKey: String, recommendedRelay: URL? = nil) -> NEventTag {
        return NEventTag(id: "p", otherInformation: publicKey, recommendedRelay?.absoluteString)
    }

    public init(id: String, otherInformation: String?...) {
        underlyingData = [id] + otherInformation.compactMap { $0 }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        underlyingData = try container.decode([String].self)

        guard underlyingData.count > 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: .init(), debugDescription: "missing required tag id"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(contentsOf: underlyingData)
    }
}

struct NSerializableEvent: Encodable {
    let id = 0
    let publicKey: String
    let createdAt: NTimestamp
    let kind: NEventKind
    let tags: [NEventTag]
    let content: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(id)
        try container.encode(publicKey)
        try container.encode(createdAt)
        try container.encode(kind)
        try container.encode(tags)
        try container.encode(content)
    }
}

struct NEvent: Codable {

    enum EventError : Error {
        case InvalidId
        case InvalidSignature
    }

    public var id: String
    public var publicKey: String
    public var createdAt: NTimestamp
    public var kind: NEventKind
    public var tags: [NEventTag]
    public var content: String
    public var signature: String

    enum CodingKeys: String, CodingKey {
        case id
        case publicKey = "pubkey"
        case createdAt = "created_at"
        case kind
        case tags
        case content
        case signature = "sig"
    }

    init(content:NSetMetadata) {
        self.createdAt = NTimestamp.init(date: Date())
        self.kind = .setMetadata
        self.content = try! content.encodedString()
        self.id = ""
        self.tags = []
        self.publicKey = ""
        self.signature = ""
    }

    init(content:String) {
        self.kind = .textNote
        self.createdAt = NTimestamp.init(date: Date())
        self.content = content
        self.id = ""
        self.tags = []
        self.publicKey = ""
        self.signature = ""
    }

    mutating func sign(_ keys:NKeys) throws -> NEvent {

        let serializableEvent = NSerializableEvent(publicKey: keys.publicKeyHex(), createdAt: self.createdAt, kind:self.kind, tags: self.tags, content: self.content)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let serializedEvent = try! encoder.encode(serializableEvent)
        let sha256Serialized = SHA256.hash(data: serializedEvent)

        let sig = try! keys.signature(for: sha256Serialized)


        guard keys.publicKey.schnorr.isValidSignature(sig, for: sha256Serialized) else {
            throw "Signing failed"
        }

        self.id = String(bytes:sha256Serialized.bytes)
        self.publicKey = keys.publicKeyHex()
        self.signature = String(bytes:sig.rawRepresentation.bytes)

        print("🟣🟣 sign:")
        print(self.id)
        print(self.signature)

        return self
    }

    func verified() throws -> Bool {

        let serializableEvent = NSerializableEvent(publicKey: self.publicKey, createdAt: self.createdAt, kind:self.kind, tags: self.tags, content: self.content)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let serializedEvent = try! encoder.encode(serializableEvent)
        let sha256Serialized = SHA256.hash(data: serializedEvent)

        print("🟢🟢 verified:")
        print(self.id)
        print(String(bytes:sha256Serialized.bytes))

        guard self.id == String(bytes:sha256Serialized.bytes) else {
            throw "Invalid ID"
        }

//        let xOnlyKey = try secp256k1.Signing.XonlyKey(rawRepresentation: Data(hexString: self.publicKey).bytes, keyParity: 1)
//        let pubKey = secp256k1.Signing.PublicKey(xonlyKey: xOnlyKey)
//
//        let schnorrSignature = try secp256k1.Signing.SchnorrSignature(rawRepresentation: event.signature.bytes)

        // public key from this event


        let xOnlyKey = try secp256k1.Signing.XonlyKey(rawRepresentation: self.publicKey.bytes, keyParity: 1)
        let pubKey = secp256k1.Signing.PublicKey(xonlyKey: xOnlyKey)

        // signature from this event
        let schnorrSignature = try secp256k1.Signing.SchnorrSignature(rawRepresentation: self.signature.bytes)

        // public and signature from this event is valid?
        guard pubKey.schnorr.isValidSignature(schnorrSignature, for: sha256Serialized) else {
            throw "Invalid signature"
        }

        return true
    }

    func eventJson() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let finalMessage = try! encoder.encode(self)

        return String(data: finalMessage, encoding: .utf8)!
    }

    func wrappedEventJson() -> String {
        return NRelayMessage.event(self)
    }
}

struct NRelayMessage {
    var message: String
    var event:NEvent

    init(event:NEvent) {
        self.event = event
        self.message = "[\"EVENT\",\(event.eventJson())]"
    }

    static func event(_ event:NEvent) -> String {
        return "[\"EVENT\",\(event.eventJson())]"
    }
}

public struct NSetMetadata: Codable {

    public var name: String?
    public var about: String?
    public var picture: String?
    public var nip05: String? = nil
    public var lud16: String? = nil

    enum CodingKeys: String, CodingKey {
        case name
        case about
        case picture
        case nip05
        case lud16
    }

    public func encodedString() throws -> String {
        let encoder = JSONEncoder()
//        encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

struct NKeys {

    public let privateKey:secp256k1.Signing.PrivateKey
    public let publicKey:secp256k1.Signing.PublicKey

    init(privateKey:secp256k1.Signing.PrivateKey) {
        self.privateKey = privateKey
        self.publicKey = privateKey.publicKey
    }

    init(privateKeyHex:String) {
        let privateKeyBytes = try! privateKeyHex.bytes
        privateKey = try! secp256k1.Signing.PrivateKey(rawRepresentation: privateKeyBytes)
        publicKey = privateKey.publicKey
    }

    func privateKeyHex() -> String {
        return String(bytes: privateKey.rawRepresentation.bytes)
    }

    func publicKeyHex() -> String {
        return String(bytes: privateKey.publicKey.xonly.bytes)
    }

    func signature<D: Digest>(for digest: D) throws -> secp256k1.Signing.SchnorrSignature {
        return try privateKey.schnorr.signature(for: digest)
    }

    public static func newKeys() -> NKeys {
        return try! self.init(privateKey: secp256k1.Signing.PrivateKey())
    }
}

//func verifySignature(event:NEvent) throws -> Bool {
//
//    let serializableEvent = NSerializableEvent(
//            publicKey: event.publicKey,
//            createdAt: event.createdAt,
//            kind: event.kind,
//            tags: event.tags,
//            content: event.content
//    )
//
//    let encoder = JSONEncoder()
//    encoder.outputFormatting = .withoutEscapingSlashes
//    let serializedEvent = try! encoder.encode(serializableEvent)
//
//    let sha256Serialized = SHA256.hash(data: serializedEvent)
//
//    guard try event.id.bytes == sha256Serialized.bytes else {
//        throw NEvent.EventError.InvalidId
//    }
//
//    let xOnlyKey = try secp256k1.Signing.XonlyKey(rawRepresentation: event.publicKey.bytes, keyParity: 1)
//    let pubKey = secp256k1.Signing.PublicKey(xonlyKey: xOnlyKey)
//
//    let schnorrSignature = try secp256k1.Signing.SchnorrSignature(rawRepresentation: event.signature.bytes)
//
//    guard pubKey.schnorr.isValidSignature(schnorrSignature, for: sha256Serialized) else {
//        throw NEvent.EventError.InvalidSignature
//    }
//
//    return true
//}

//func signEvent(event:NSerializableEvent, keys:NKeys) throws -> NEvent {
//
//    let encoder = JSONEncoder()
//    encoder.outputFormatting = .withoutEscapingSlashes
//    let serializedEvent = try! encoder.encode(event)
//    let sha256Serialized = SHA256.hash(data: serializedEvent)
//
//    let sig = try! keys.signature(for: sha256Serialized)
//
//    guard keys.publicKey.schnorr.isValidSignature(sig, for: sha256Serialized) else {
//        throw "Signing failed"
//    }
//
//    return NEvent(id: String(bytes:sha256Serialized.bytes), publicKey: keys.publicKeyHex(), createdAt: event.createdAt, kind: event.kind, tags: event.tags, content: event.content, signature: String(bytes:sig.rawRepresentation.bytes))
//}