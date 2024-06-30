//
//  NIP19.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2023.
//

import Foundation

//var key = try! NIP19(displayString: "npub")
//key.displayString // "npub..."
//key.hexString // "8df73d0..."
//
//var key = try! NIP19(prefix: "npub", hexString: "73ea43...")
//var key = try! NIP19(prefix: "note", hexString: "139d3d...")
//var key = try! NIP19(prefix: "nsec", hexString: "139d3d...")

struct NIP19 {
    let key: [UInt8]
    let displayString: String
    let hexString:String
    
    public init(prefix:String, hexString: String) throws {
        self.key = hexString.hexToBytes()
        self.hexString = key.hexString()
        let bech32 = Bech32()
        let grouped = try bech32.convertBits(from: 8, to: 5, pad: true, idata: Data(bytes: key, count: 32))
        self.displayString = bech32.encode(prefix, values: grouped)
    }
    
    public init(prefix:String, key: [UInt8]) throws {
        self.key = key
        self.hexString = key.hexString()
        let bech32 = Bech32()
        let grouped = try bech32.convertBits(from: 8, to: 5, pad: true, idata: Data(bytes: key, count: 32))
        self.displayString = bech32.encode(prefix, values: grouped)
    }
    
    public init(displayString: String) throws {
        self.displayString = displayString
        let bech32 = Bech32()
        let (_, checksum) = try bech32.decode(displayString)
        self.key = try bech32.convertBits(from: 5, to: 8, pad: false, idata: checksum).makeBytes()
        self.hexString = key.hexString()
    }
}

func note1(_ hex:String) -> String? {
    return try? NIP19(prefix: "note", hexString: hex).displayString
}

func npub(_ hex:String) -> String {
    return try! NIP19(prefix: "npub", hexString: hex).displayString
}

func nsec(_ hex:String) -> String {
    return try! NIP19(prefix: "nsec", hexString: hex).displayString
}

func toPubkey(_ npub:String) throws -> String {
    return try NIP19(displayString: npub).hexString
}

func hex(_ note1:String) -> String? {
    return try? NIP19(displayString: note1).hexString
}


class ShareableIdentifier: Hashable {
    
    static func == (lhs: ShareableIdentifier, rhs: ShareableIdentifier) -> Bool {
        lhs.bech32string == rhs.bech32string
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bech32string)
    }
    
    var id: String { bech32string }
    let bech32string: String
    let prefix: String
    
    var pubkey: String?
    var eventId: String?
    var relayUrl: String?
    var relays: [String] = []
    var kind: Int64?
    
    init(_ bech32string:String) throws {
        self.bech32string = bech32string
        let (prefix, tlvData) = try Bech32.decode(other: bech32string)
        self.prefix = prefix
        
        var currentIndex = 0
        while currentIndex < tlvData.count {
            guard currentIndex + 2 < tlvData.count else {
                throw "EncodingError.invalidFormat"
            }
            let type = tlvData[currentIndex]
            let length = Int(tlvData[currentIndex + 1])
            guard currentIndex + 2 + length <= tlvData.count else {
                throw "EncodingError.invalidFormat"
            }
            let value = tlvData.subdata(in: (currentIndex + 2)..<(currentIndex + 2 + length))
            currentIndex += 2 + length
            
            switch type {
                case 0:
                    switch prefix {
                        case "nprofile":
                            pubkey = value.hexEncodedString()
                        case "nevent":
                            eventId = value.hexEncodedString()
                        case "nrelay":
                            relayUrl = String(data: value, encoding: .utf8)
                        case "naddr":
                            eventId = String(data: value, encoding: .utf8) // identifier / "d" tag
                        default:
                            throw "EncodingError.invalidPrefix.0"
                    }
                case 1:
                    let relay = String(data: value, encoding: .utf8)!
                    relays.append(relay)
                case 2:
                    switch prefix {
                        case "naddr":
                            pubkey = value.hexEncodedString()
                        case "nevent":
                            pubkey = value.hexEncodedString()
                        default:
                            throw "EncodingError.invalidPrefix.2"
                    }
                case 3:
                    switch prefix {
                        case "naddr":
                            kind = Int64(value.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian)
                        case "nevent":
                            kind = Int64(value.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian)
                        default:
                            throw "EncodingError.invalidPrefix.3"
                    }
                default:
                    L.og.error("EncodingError.invalidType")
            }
        }
    }
    
    init(prefix:String, kind:Int64, pubkey:String, dTag:String? = nil, eventId:String? = nil, relays:[String] = []) throws {
        self.prefix = prefix
        self.kind = kind
        self.pubkey = pubkey
        self.eventId = dTag ?? (eventId ?? nil)
        self.relays = relays
        
        var tlvData = Data()
        
        if let dTag, prefix == "naddr" {
            // Append TLV for the special type
            let dTagValue = dTag.data(using: .utf8)!
            tlvData.append(0) // Type
            tlvData.append(UInt8(dTagValue.count)) // Length
            tlvData.append(contentsOf: dTagValue) // Value
        }
        else if let eventId, prefix == "nevent" {
            // Append TLV for the special type
            let eventId = eventId.hexToBytes()
            tlvData.append(0) // Type
            tlvData.append(UInt8(eventId.count)) // Length
            tlvData.append(contentsOf: eventId) // Value
        }
        
        let authorValue = pubkey.hexToBytes()
        tlvData.append(2)
        tlvData.append(UInt8(authorValue.count))
        tlvData.append(contentsOf: authorValue)
        
        var kindValue = UInt32(kind).bigEndian
        let kindBytes = withUnsafeBytes(of: &kindValue) { Array($0) }
        tlvData.append(3) // Type
        tlvData.append(UInt8(kindBytes.count)) // Length (assuming 4 bytes)
        tlvData.append(contentsOf: kindBytes) // Value
        
        for relay in relays {
            let value = relay.data(using: .utf8)!
            tlvData.append(1)
            tlvData.append(UInt8(value.count))
            tlvData.append(value)
        }
        
        let bech32 = Bech32()
        
        self.bech32string = bech32.encode(prefix, values: tlvData, eightToFive: true)
    }
    
    init(aTag: String) throws {
        self.prefix = "naddr"
        
        let elements = aTag.split(separator: ":")
        guard elements.count >= 3, let aTagKind = elements[safe: 0], let aTagPubkey = elements[safe: 1], let aTagDefinition = elements[safe: 2]
        else {
            throw "Invalid aTag"
        }
        self.kind = Int64(aTagKind)
        self.pubkey = String(aTagPubkey)
        self.eventId = String(aTagDefinition)
        
        var tlvData = Data()
        
        // Append TLV for the special type
        let dTagValue = aTagDefinition.data(using: .utf8)!
        tlvData.append(0) // Type
        tlvData.append(UInt8(dTagValue.count)) // Length
        tlvData.append(contentsOf: dTagValue) // Value
        
        let authorValue = String(aTagPubkey).hexToBytes()
        tlvData.append(2)
        tlvData.append(UInt8(authorValue.count))
        tlvData.append(contentsOf: authorValue)
        
        var kindValue = UInt32(Int64(aTagKind)!).bigEndian
        let kindBytes = withUnsafeBytes(of: &kindValue) { Array($0) }
        tlvData.append(3) // Type
        tlvData.append(UInt8(kindBytes.count)) // Length (assuming 4 bytes)
        tlvData.append(contentsOf: kindBytes) // Value
        
       
        
        let bech32 = Bech32()
        
        self.bech32string = bech32.encode(prefix, values: tlvData, eightToFive: true)
    }
}

