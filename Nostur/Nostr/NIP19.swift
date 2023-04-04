//
//  File.swift
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
    let key: Bytes
    let displayString: String
    var hexString:String { get { key.hexString() }}
    
    public init(prefix:String, hexString: String) throws {
        self.key = hexString.hexToBytes()
        let bech32 = Bech32()
        let grouped = try bech32.convertBits(from: 8, to: 5, pad: true, idata: Data(bytes: key, count: 32)) // Data: Thread 1: Heap buffer overflow
        self.displayString = bech32.encode(prefix, values: grouped)
    }
    
    public init(prefix:String, key: Bytes) throws {
        self.key = key
        let bech32 = Bech32()
        let grouped = try bech32.convertBits(from: 8, to: 5, pad: true, idata: Data(bytes: key, count: 32))
        self.displayString = bech32.encode(prefix, values: grouped)
    }
    
    public init(displayString: String) throws {
        self.displayString = displayString
        let bech32 = Bech32()
        let (_, checksum) = try bech32.decode(displayString)
        self.key = try bech32.convertBits(from: 5, to: 8, pad: false, idata: checksum).makeBytes()
    }
    
    // NIP-19 nprofile
    
}

func note1(_ hex:String) -> String {
    return try! NIP19(prefix: "note", hexString: hex).displayString
}

func npub(_ hex:String) -> String {
    return try! NIP19(prefix: "npub", hexString: hex).displayString
}

func nsec(_ hex:String) -> String {
    return try! NIP19(prefix: "nsec", hexString: hex).displayString
}

func pubkey(_ npub:String) throws -> String {
    return try NIP19(displayString: npub).hexString
}

func hex(_ note1:String) -> String {
    return try! NIP19(displayString: note1).hexString
}


class ShareableIdentifier {

    let bech32string:String
    let prefix:String
    
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
                            eventId = value.hexEncodedString() // or: String(data: value, encoding: .utf8) ??
                        default:
                            throw "EncodingError.invalidPrefix"
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
                            throw "EncodingError.invalidPrefix"
                    }
                case 3:
                    guard prefix == "naddr" else {
                        throw "EncodingError.invalidPrefix"
                    }
                    kind = Int64(value.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian)
                default:
                    print("EncodingError.invalidType")
            }
        }
    }
}
