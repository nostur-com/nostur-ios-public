//
//  AnySigner.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/06/2023.
//

import SwiftUI
import secp256k1
import NostrEssentials

/// Sign any unsigned nostr event with your key
struct AnySigner: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var error: String?
    @State private var signedNEvent: AnyNEvent? = nil
    
    @State private var tab = "Signer"
    
    private func publish() {
        if let signedNEvent = signedNEvent {
            ConnectionPool.shared
                .sendMessage(
                    NosturClientMessage(
                        clientMessage: NostrEssentials.ClientMessage(
                            type: .EVENT
                        ),
                        relayType: .WRITE,
                        message: signedNEvent.wrappedEventJson()
                    ),
                    accountPubkey: signedNEvent.publicKey!
                )
            
            // TODO: Should also save in database, but AnyNEvent is not NEvent so can't call saveEvent()
            // Need to refactor AnyNEvent to just be NEvent...
        }
    }

    var body: some View {
        VStack {
            HStack {
                TabButton(action: {
                    withAnimation {
                        tab = "Signer"
                    }
                }, title: "Signer", selected: tab == "Signer")
                
                TabButton(action: {
                    withAnimation {
                        tab = "Broadcaster"
                    }
                }, title: "Broadcaster", selected: tab == "Broadcaster")
            }
            
            Form {
                Group {
                    if #available(iOS 16.0, *) {
                        TextField(String(localized:"Enter JSON", comment:"Label for field to enter a nostr json event"), text: $input, prompt: Text(verbatim: "{ \"some\": [\"json\"] }"), axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .lineLimit(16, reservesSpace: true)
                    }
                    else {
                        TextField(String(localized:"Enter JSON", comment:"Label for field to enter a nostr json event"), text: $input, prompt: Text(verbatim: "{ \"some\": [\"json\"] }"))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .lineLimit(16)
                    }
                }
                .listRowBackground(themes.theme.background)
                
                if let account = AccountsState.shared.loggedInAccount?.account, account.privateKey != nil, tab == "Signer" {
                    HStack {
                        Text("Signing as")
                        PFP(pubkey: account.publicKey, account: account, size: 30)
                    }
                    .background(themes.theme.background)
                }
                if let error {
                    Text(error)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
            .scrollContentBackgroundHidden()
            .onChange(of: tab) { newTab in
                if newTab == "Broadcaster" {
                    recheck(input)
                }
            }
            .onChange(of: input) { newValue in
                recheck(newValue)
            }
            .navigationTitle(tab == "Signer" ? String(localized:"Sign any nostr event", comment:"Navigation title for screen to sign any nostr event") : String(localized:"Broadcast nostr event", comment:"Navigation title for screen to broadcast any nostr event"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { UIPasteboard.general.string = input } label: { Image(systemName: "doc.on.clipboard.fill") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized:"Publish", comment:"Button to publish")) { publish() }
                        .disabled(signedNEvent == nil)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if tab == "Signer" {
                        Button(String(localized:"Sign event", comment:"Button to sign a nostr JSON event")) {
                            let decoder = JSONDecoder()
                            
                            guard let inputData = input.data(using: .utf8) else {
                                error = String(localized:"Could not convert data", comment: "Error message"); return
                            }
                            
                            guard var nEvent = try? decoder.decode(AnyNEvent.self, from: inputData) else {
                                error = String(localized:"Could not parse JSON", comment: "Error message"); return
                            }
                            
                            guard let pk = AccountsState.shared.loggedInAccount?.account.privateKey else {
                                error = String(localized:"Account has no private key", comment: "Error message"); return
                            }
                            
                            guard let keys = try? Keys(privateKeyHex: pk), let signedNEvent = try? nEvent.sign(keys), let verified = try? signedNEvent.verified(), verified else {
                                error = String(localized:"Could not sign event", comment: "Error message"); return
                            }


                            input = signedNEvent.eventJson(.prettyPrinted)
                            self.signedNEvent = signedNEvent
                        }
                        .disabled(AccountsState.shared.loggedInAccount?.account.privateKey == nil)
                    }
                }
            }
        }
    }
    
    func recheck(_ newValue: String) {
        guard newValue != "" else {
            self.signedNEvent = nil
            return
        }
        if input != newValue {
            self.signedNEvent = nil
        }

        if tab == "Broadcaster" {
            let decoder = JSONDecoder()
            
            guard let inputData = newValue.data(using: .utf8) else {
                error = String(localized:"Could not convert data", comment: "Error message"); return
            }
            
            guard let nEvent = try? decoder.decode(AnyNEvent.self, from: inputData) else {
                error = String(localized:"Could not parse JSON", comment: "Error message"); return
            }
            
           
            
            guard let verified = try? nEvent.verified(), verified else {
                error = String(localized:"Unsigned or invalid event", comment: "Error message"); return
            }
            error = nil
//            input = nEvent.eventJson(.prettyPrinted)
            self.signedNEvent = nEvent
        }
    }
}

import NavigationBackport

struct AnySigner_Previews: PreviewProvider {
    static var previews: some View {
        NBNavigationStack {
            AnySigner()
                .environmentObject(Themes.default)
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
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

    mutating func sign(_ keys: Keys) throws -> AnyNEvent {

        let serializableEvent = NSerializableEvent(publicKey: keys.publicKeyHex, createdAt: self.createdAt ?? NTimestamp.init(date: Date()), kind:self.kind, tags: self.tags, content: self.content)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let serializedEvent = try! encoder.encode(serializableEvent)
        let sha256Serialized = SHA256.hash(data: serializedEvent)

        let sig = try! keys.signature(for: sha256Serialized)

        guard keys.publicKey.isValidSignature(sig, for: sha256Serialized) else {
            throw "Signing failed"
        }

        self.id = String(bytes:sha256Serialized.bytes)
        self.publicKey = keys.publicKeyHex
        self.signature = String(bytes:sig.bytes)

        return self
    }
    
    func verified() throws -> Bool {
        L.og.debug("✍️ VERIFYING SIG ✍️")
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

        let xOnlyKey = try secp256k1.Schnorr.XonlyKey(dataRepresentation: publicKey.bytes, keyParity: 1)

        // signature from this event
        let schnorrSignature = try secp256k1.Schnorr.SchnorrSignature(dataRepresentation: signature.bytes)

        // public and signature from this event is valid?
        guard xOnlyKey.isValidSignature(schnorrSignature, for: sha256Serialized) else {
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
