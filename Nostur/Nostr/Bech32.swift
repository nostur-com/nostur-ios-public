//
//  Bech32.swift
//
//  Created by Evolution Group Ltd on 12.02.2018.
//  Copyright © 2018 Evolution Group Ltd. All rights reserved.
//
//  Base32 address format for native v0-16 witness outputs implementation
//  https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki
//  Inspired by Pieter Wuille C++ implementation
//  Optimized with ChatGPT
//  Modified for lnurl / nostr

import Foundation

// Need to clean up this mix of Bech32 implementations.
public class Bech32 {
    private static let alphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    
    private let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    /// Bech32 checksum delimiter
    private let checksumMarker: String = "1"
    /// Bech32 character set for encoding
    private let encCharset: Data = "qpzry9x8gf2tvdw0s3jn54khce6mua7l".data(using: .utf8)!
    /// Bech32 character set for decoding
    private let decCharset: [Int8] = [
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
         -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
         -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
         15, -1, 10, 17, 21, 20, 26, 30,  7,  5, -1, -1, -1, -1, -1, -1,
         -1, 29, -1, 24, 13, 25,  9,  8, 23, -1, 18, 22, 31, 27, 19, -1,
         1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, -1, -1, -1, -1, -1,
         -1, 29, -1, 24, 13, 25,  9,  8, 23, -1, 18, 22, 31, 27, 19, -1,
         1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, -1, -1, -1, -1, -1
    ]

    private func polymod(_ values: Data) -> UInt32 {
        //        let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        let chk: UInt32 = 1
        
        var precomputedTop: [UInt32] = Array(repeating: 0, count: 32)
        for i in 0..<32 {
            let mask0 = UInt32(i & 1)
            let mask1 = UInt32((i >> 1) & 1)
            let mask2 = UInt32((i >> 2) & 1)
            let mask3 = UInt32((i >> 3) & 1)
            let mask4 = UInt32((i >> 4) & 1)
            
            precomputedTop[i] = gen[0] &* mask0 ^ gen[1] &* mask1 ^ gen[2] &* mask2 ^ gen[3] &* mask3 ^ gen[4] &* mask4
        }
        
        return values.reduce(into: chk) { chk, v in
            let top = (chk >> 25)
            let newChk = (chk & 0x1ffffff) << 5 ^ UInt32(v)
            chk = newChk ^ precomputedTop[Int(top)]
        }
    }
    
    /// Expand a HRP for use in checksum computation.
    private func expandHrp(_ hrp: String) -> Data {
        guard let hrpBytes = hrp.data(using: .utf8) else { return Data() }
        var result = Data(repeating: 0x00, count: hrpBytes.count*2+1)
        for (i, c) in hrpBytes.enumerated() {
            result[i] = c >> 5
            result[i + hrpBytes.count + 1] = c & 0x1f
        }
        result[hrp.count] = 0
        return result
    }
    
    /// Verify checksum
    private func verifyChecksum(hrp: String, checksum: Data) -> Bool {
        var data = expandHrp(hrp)
        data.append(checksum)
        return polymod(data) == 1
    }
    
    /// Create checksum
    private func createChecksum(hrp: String, values: Data) -> Data {
        var enc = expandHrp(hrp)
        enc.append(values)
        enc.append(Data(repeating: 0x00, count: 6))
        let mod: UInt32 = polymod(enc) ^ 1
        var ret: Data = Data(repeating: 0x00, count: 6)
        for i in 0..<6 {
            ret[i] = UInt8((mod >> (5 * (5 - i))) & 31)
        }
        return ret
    }
    
    /// Encode Bech32 string
    public func encode(_ hrp: String, values: Data) -> String {
        let checksum = createChecksum(hrp: hrp, values: values)
        var combined = values
        combined.append(checksum)
        guard let hrpBytes = hrp.data(using: .utf8) else { return "" }
        var ret = hrpBytes
        ret.append("1".data(using: .utf8)!)
        for i in combined {
            ret.append(encCharset[Int(i)])
        }
        return String(data: ret, encoding: .utf8) ?? ""
    }
    
    func hasValidCharacters(_ bechString: String) -> Bool {
        guard let stringBytes = bechString.data(using: .utf8) else { return false }
        
        var hasLower = false
        var hasUpper = false
        
        for character in stringBytes {
            let code = UInt32(character)
            if code < 33 || code > 126 {
                return false
            } else if code >= 97 && code <= 122 {
                hasLower = true
            } else if code >= 65 && code <= 90 {
                hasUpper = true
            }
        }
        
        return !(hasLower && hasUpper)
    }
    
    public func decode(_ bechString: String, limit: Bool = true) -> (hrp: String, checksum: Data)? {
        guard hasValidCharacters(bechString) else { return nil }
        
        let bechString = bechString.lowercased()
        guard let pos = bechString.lastIndex(of: "1") else { return nil }
        
        if pos < 1 || pos + 7 > bechString.count || (limit && bechString.count > 90) {
            return nil
        }
        
        let humanReadablePart = String(bechString.prefix(pos))
        let dataPart = bechString.suffix(bechString.count - humanReadablePart.count - 1)
        
        var data = Data()
        for character in dataPart {
            guard let distance = Bech32.alphabet.indexDistance(of: character) else { return nil }
            data.append(UInt8(distance))
        }
        
        guard verifyChecksum(hrp: humanReadablePart, checksum: data) else {
            return nil
        }
        
        return (humanReadablePart, Data(data[..<(data.count - 6)]))
    }
    
    public func decode(_ str: String, skipLimit:Bool = false) throws -> (hrp: String, checksum: Data) {
        guard let strBytes = str.data(using: .utf8) else {
            throw DecodingError.nonUTF8String
        }
        guard skipLimit || !["npub1","nsec1"].contains(str.prefix(5)) || strBytes.count <= 90 else {
            throw DecodingError.stringLengthExceeded
        }
        var lower: Bool = false
        var upper: Bool = false
        for c in strBytes {
            // printable range
            if c < 33 || c > 126 {
                throw DecodingError.nonPrintableCharacter
            }
            // 'a' to 'z'
            if c >= 97 && c <= 122 {
                lower = true
            }
            // 'A' to 'Z'
            if c >= 65 && c <= 90 {
                upper = true
            }
        }
        if lower && upper {
            throw DecodingError.invalidCase
        }
        guard let pos = str.range(of: checksumMarker, options: .backwards)?.lowerBound else {
            throw DecodingError.noChecksumMarker
        }
        let intPos: Int = str.distance(from: str.startIndex, to: pos)
        guard intPos >= 1 else {
            throw DecodingError.incorrectHrpSize
        }
        guard intPos + 7 <= str.count else {
            throw DecodingError.incorrectChecksumSize
        }
        let vSize: Int = str.count - 1 - intPos
        var values: Data = Data(repeating: 0x00, count: vSize)
        for i in 0..<vSize {
            let c = strBytes[i + intPos + 1]
            let decInt = decCharset[Int(c)]
            if decInt == -1 {
                throw DecodingError.invalidCharacter
            }
            values[i] = UInt8(decInt)
        }
        let hrp = String(str[..<pos]).lowercased()
        guard verifyChecksum(hrp: hrp, checksum: values) else {
            throw DecodingError.checksumMismatch
        }
        return (hrp, Data(values[..<(vSize-6)]))
    }

    static func decode(lnurl: String) throws -> URL {
        let bech32 = Bech32()
        guard let (hrp, decodedData) = bech32.decode(lnurl, limit: false) else {
            throw "LNURLAuthError.invalidLNURL"
        }
        
        guard hrp.lowercased() == "lnurl" else {
            throw "LNURLAuthError.invalidLNURL"
        }
        
        guard let data = decodedData.convertBits(fromBits: 5, toBits: 8, pad: false) else {
            throw "LNURLAuthError.invalidLNURL"
        }
        
        guard let string = String(data: data, encoding: .utf8) else {
            throw "LNURLAuthError.invalidLNURL"
        }
        
        guard let url = URL(string: string) else {
            throw "LNURLAuthError.invalidLNURL"
        }
        
        return url
    }
    
    static func decode(other: String) throws -> (String, Data) {
        let bech32 = Bech32()
        guard let (hrp, decodedData) = try? bech32.decode(other, skipLimit: true) else {
            throw "LNURLAuthError.invalidLNURL"
        }

        guard let data = decodedData.convertBits(fromBits: 5, toBits: 8, pad: false) else {
            throw "LNURLAuthError.invalidLNURL"
        }
        
        return (hrp, data)
    }
    
    public func convertBits(from: Int, to: Int, pad: Bool, idata: Data) throws -> Data {
        var acc: Int = 0
        var bits: Int = 0
        let maxv: Int = (1 << to) - 1
        let maxAcc: Int = (1 << (from + to - 1)) - 1
        var odata = Data()
        for ibyte in idata {
            acc = ((acc << from) | Int(ibyte)) & maxAcc
            bits += from
            while bits >= to {
                bits -= to
                odata.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits != 0 {
                odata.append(UInt8((acc << (to - bits)) & maxv))
            }
        } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
            throw DecodingError.bitsConversionFailed
        }
        return odata
    }
}

extension Bech32 {
    public enum DecodingError: LocalizedError {
        case nonUTF8String
        case nonPrintableCharacter
        case invalidCase
        case noChecksumMarker
        case incorrectHrpSize
        case incorrectChecksumSize
        case stringLengthExceeded
        
        case invalidCharacter
        case checksumMismatch
        case bitsConversionFailed
        
        public var errorDescription: String? {
            switch self {
                case .checksumMismatch:
                    return "Checksum doesn't match"
                case .incorrectChecksumSize:
                    return "Checksum size too low"
                case .incorrectHrpSize:
                    return "Human-readable-part is too small or empty"
                case .invalidCase:
                    return "String contains mixed case characters"
                case .invalidCharacter:
                    return "Invalid character met on decoding"
                case .noChecksumMarker:
                    return "Checksum delimiter not found"
                case .nonPrintableCharacter:
                    return "Non printable character in input string"
                case .nonUTF8String:
                    return "String cannot be decoded by utf8 decoder"
                case .stringLengthExceeded:
                    return "Input string is too long"
                case .bitsConversionFailed:
                    return "Failed to perform bits conversion"
            }
        }
    }
}


extension Data {
    // ConvertBits converts a byte slice where each byte is encoding fromBits bits,
    // to a byte slice where each byte is encoding toBits bits.
    func convertBits(fromBits: Int, toBits: Int, pad: Bool) -> Data? {
        var acc: Int = 0
        var bits: Int = 0
        var result = Data()
        let maxv: Int = (1 << toBits) - 1
        
        for value in self {
            if value < 0 || (value >> fromBits) != 0 {
                return nil
            }
            
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        
        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        
        return result
    }
}


public extension String {
    
    func indexDistance(of character: Character) -> Int? {
        guard let index = firstIndex(of: character) else { return nil }
        return distance(from: startIndex, to: index)
    }
    
    func lastIndex(of string: String) -> Int? {
        guard let index = range(of: string, options: .backwards) else { return nil }
        return self.distance(from: self.startIndex, to: index.lowerBound)
    }
}
