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
}
