//
//  AnySigner.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/06/2023.
//

import SwiftUI
import secp256k1

/// Sign any unsigned nostr event with your key
struct AnySigner: View {
    @Environment(\.dismiss) var dismiss
    @State var input = ""
    @State var error:String?
    @State var signedNEvent:AnyNEvent? = nil
    
    func publish() {
        if let eventJson = signedNEvent?.wrappedEventJson() {
            SocketPool.shared.sendMessage(ClientMessage(message: eventJson))
        }
    }

    var body: some View {
        Form {
            TextField("Enter JSON", text: $input, prompt: Text("{ \"some\": [\"json\"] }"), axis: .vertical)
                .lineLimit(20, reservesSpace: true)
            if let error {
                Text(error)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
        }
        .onChange(of: input) { newValue in
            if input != newValue {
                self.signedNEvent = nil
            }

        }
        .navigationTitle("Sign any nostr event")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { UIPasteboard.general.string = input } label: { Image(systemName: "doc.on.clipboard.fill") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Publish") { publish() }
                    .disabled(signedNEvent == nil)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Sign event") {
                    let decoder = JSONDecoder()
                    
                    guard let inputData = input.data(using: .utf8) else {
                        error = "Could not convert data"; return
                    }
                    
                    guard var nEvent = try? decoder.decode(AnyNEvent.self, from: inputData) else {
                        error = "Could not parse JSON"; return
                    }
                    
                    guard let pk = NosturState.shared.account?.privateKey else {
                        error = "Account has no private key"; return
                    }
                    
                    guard let keys = try? NKeys(privateKeyHex: pk), let signedNEvent = try? nEvent.sign(keys), let verified = try? signedNEvent.verified(), verified else {
                        error = "Could not sign event"; return
                    }


                    input = signedNEvent.eventJson(.prettyPrinted)
                    self.signedNEvent = signedNEvent
//                    self.signedNEvent = signedNEvent
                }
            }
        }
    }
}

struct AnySigner_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AnySigner()
        }
        .previewDevice("iPhone 14")
    }
}


struct AnyNEvent: Codable {

    enum EventError : Error {
        case InvalidId
        case InvalidSignature
        case EOSE
    }

    public var id: String?
    public var publicKey: String?
    public var createdAt: NTimestamp?
    public var kind: NEventKind
    public var tags: [NostrTag]
    public var content: String
    public var signature: String?

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

    mutating func sign(_ keys:NKeys) throws -> AnyNEvent {

        let serializableEvent = NSerializableEvent(publicKey: keys.publicKeyHex(), createdAt: self.createdAt ?? NTimestamp.init(date: Date()), kind:self.kind, tags: self.tags, content: self.content)

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

        return self
    }
    
    func verified() throws -> Bool {
        print("✍️ VERIFYING SIG ✍️")
        guard let publicKey = publicKey else { throw "missing pubkey" }
        guard let createdAt = createdAt else { throw "missing createdAt" }
        guard let signature = signature else { throw "missing signature" }
        
        let serializableEvent = NSerializableEvent(publicKey: publicKey, createdAt: createdAt, kind:self.kind, tags: self.tags, content: self.content)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let serializedEvent = try! encoder.encode(serializableEvent)
        let sha256Serialized = SHA256.hash(data: serializedEvent)

        guard self.id == String(bytes:sha256Serialized.bytes) else {
            throw "🔴🔴 Invalid ID 🔴🔴"
        }

        let xOnlyKey = try secp256k1.Signing.XonlyKey(rawRepresentation: publicKey.bytes, keyParity: 1)
        let pubKey = secp256k1.Signing.PublicKey(xonlyKey: xOnlyKey)

        // signature from this event
        let schnorrSignature = try secp256k1.Signing.SchnorrSignature(rawRepresentation: signature.bytes)

        // public and signature from this event is valid?
        guard pubKey.schnorr.isValidSignature(schnorrSignature, for: sha256Serialized) else {
            throw "Invalid signature"
        }

        return true
    }

    func eventJson(_ outputFormatting:JSONEncoder.OutputFormatting? = nil) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting ?? .withoutEscapingSlashes
        let finalMessage = try! encoder.encode(self)

        return String(data: finalMessage, encoding: .utf8)!
    }
    
    func wrappedEventJson() -> String {
        return "[\"EVENT\",\(self.eventJson())]"
    }
}
