//
//  SwiftBTC
//
//  Created by Otto Suess on 28.02.18.
//  Copyright © 2018 Zap. All rights reserved.
//
import Foundation
import CommonCrypto
import Foundation

// BIP: https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki
public enum Bech32__ {
    private static let alphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private static let generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

    private static func expandHumanReadablePart(_ humanReadablePart: String) -> Data {
        guard let stringBytes = humanReadablePart.data(using: .utf8) else { return Data() }
        var data = Data()

        for character in stringBytes {
            data.append(UInt8(UInt32(character) >> 5))
        }
        data.append(0)
        for character in stringBytes {
            data.append(UInt8(UInt32(character) & 31))
        }
        return data
    }

    private static func polymod(values: Data) -> Int {
        var chk = 1
        // swiftlint:disable:next identifier_name
        for p in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ Int(p)
            // swiftlint:disable:next identifier_name
            for (i, g) in Bech32__.generator.enumerated() where ((top >> i) & 1) != 0 {
                chk ^= g
            }
        }
        return chk
    }

    private static func verifyChecksum(humanReadablePart: String, data: Data) -> Bool {
        return polymod(values: expandHumanReadablePart(humanReadablePart) + data) == 1
    }

    private static func createChecksum(humanReadablePart: String, data: Data) -> Data {
        let values = expandHumanReadablePart(humanReadablePart) + data + Data(Array(repeating: UInt8(0), count: 6))
        let mod: Int = polymod(values: values) ^ 1

        var result = Data()
        for index in 0..<6 {
            result.append(UInt8((mod >> UInt(5 * (5 - index))) & 31))
        }
        return result
    }

    private static func hasValidCharacters(_ bechString: String) -> Bool {
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

    public static func decode(_ bechString: String, limit: Bool = true) -> (humanReadablePart: String, data: Data)? {
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
            guard let distance = Bech32__.alphabet.indexDistance(of: character) else { return nil }
            data.append(UInt8(distance))
        }

        if !verifyChecksum(humanReadablePart: humanReadablePart, data: data) {
            return nil
        }

        return (humanReadablePart, Data(data[..<(data.count - 6)]))
    }
    
    static func decode(lnurl: String) throws -> URL {
        guard let (hrp, decodedData) = decode(lnurl, limit: false) else {
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

    private static func toChars(data: Data) -> String {
        return data.reduce("") {
            let index = Bech32__.alphabet.index(Bech32__.alphabet.startIndex, offsetBy: Int($1))
            return $0 + String(Bech32__.alphabet[index])
        }
    }

    public static func encode(humanReadablePart: String, data: Data) -> String {
        let checksum = Bech32__.createChecksum(humanReadablePart: humanReadablePart, data: data)
        let combined = data + checksum

        return humanReadablePart + "1" + Bech32__.toChars(data: combined)
    }
}

public extension String {
    func sha256() -> String {
        return data(using: .utf8)?.sha256.hexadecimalString ?? ""
    }

    func indexDistance(of character: Character) -> Int? {
        guard let index = firstIndex(of: character) else { return nil }
        return distance(from: startIndex, to: index)
    }

    func lastIndex(of string: String) -> Int? {
        guard let index = range(of: string, options: .backwards) else { return nil }
        return self.distance(from: self.startIndex, to: index.lowerBound)
    }
}



public extension Data {
    var sha256: Data {
        let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: digestLength)

        let bytes = withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
            Array(UnsafeBufferPointer(start: bytes, count: count / MemoryLayout<UInt8>.stride))
        }

        CC_SHA256(bytes, UInt32(count), &hash)
        return Data(hash)
    }

    var hexadecimalString: String {
        return reduce("") { $0 + String(format: "%02x", UInt8($1)) }
    }
}

private extension String {
    func onlyHasValidBech32Characters() -> Bool {
        guard let stringBytes = self.data(using: .utf8) else { return false }

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
}
