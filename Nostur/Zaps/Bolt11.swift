//
//  Lightning
//
//  Created by Otto Suess on 09.07.18.
//  Copyright © 2018 Zap. All rights reserved.
//

import Foundation
import BigInt

extension Bolt11.Invoice {
    init(network: Network, date: Date) {
        self.network = network
        self.date = date
    }
}

public enum Bolt11 {
    public struct Invoice: Equatable {
        public var network: Network
        public var date: Date
        public var paymentHash: Data?
        public var amount: Satoshi?
        public var description: String?
        public var expiry: TimeInterval?
//        public var fallbackAddress: BitcoinAddress?
    }

    public enum Prefix: String {
        case lnbc
        case lntb
        case lnbcrt
        case lnsb

        public static func forNetwork(_ network: Network) -> Prefix {
            switch network {
            case .regtest:
                return .lnbcrt
            case .testnet:
                return .lntb
            case .mainnet:
                return .lnbc
            case .simnet:
                return .lnsb
            }
        }
    }

    private enum Multiplier: Character {
        case milli = "m"
        case micro = "u"
        case nano = "n"
        case pico = "p"

        var value: Decimal {
            switch self {
            case .milli:
                return 100000
            case .micro:
                return 100
            case .nano:
                return 0.1
            case .pico:
                return 0.0001
            }
        }
    }

    private enum FieldTypes: UInt8 {
        case fieldTypeP = 1  // fieldTypeP is the field containing the payment hash.
        case fieldTypeD = 13 // fieldTypeD contains a short description of the payment.
        case fieldTypeN = 19 // fieldTypeN contains the pubkey of the target node.
        case fieldTypeH = 23 // fieldTypeH contains the hash of a description of the payment.
        case fieldTypeX = 6  // fieldTypeX contains the expiry in seconds of the invoice.
        case fieldTypeF = 9  // fieldTypeF contains a fallback on-chain address.
        case fieldTypeR = 3  // fieldTypeR contains extra routing information.
        case fieldTypeC = 24 // fieldTypeC contains an optional requested final CLTV delta.
    }

    private static let signatureBase32Len = 104
    private static let timestampBase32Len = 7
    private static let hashBase32Len = 52

    public static func decode(string: String) -> Invoice? {
        let bech32 = Bech32()
        guard
            let (humanReadablePart, data) = bech32.decode(string, limit: false),
            humanReadablePart.count > 3,
            let network = decodeNetwork(humanReadablePart: humanReadablePart) else { return nil }


        let invoiceData = data.dropLast(signatureBase32Len)

        guard invoiceData.count >= timestampBase32Len else { return nil }


        let date = parseTimestamp(data: invoiceData[invoiceData.startIndex..<invoiceData.startIndex + timestampBase32Len])
        var invoice = Invoice(network: network, date: date)

        invoice.amount = decodeAmount(for: humanReadablePart, network: network)


        let tagData = invoiceData[invoiceData.startIndex + timestampBase32Len..<invoiceData.endIndex]

        return parseTaggedFields(data: tagData, invoice: invoice)
    }

    private static func parseTimestamp(data: Data) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(base32ToUInt(data)))
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func parseTaggedFields(data: Data, invoice: Invoice) -> Invoice? {
        var invoice = invoice
        var index: Data.Index = data.startIndex
        while data.endIndex - index >= 3 {
            let type = FieldTypes(rawValue: data[index])
            guard
                let dataLength = parseFieldDataLength(data[index + 1..<index + 3]),
                data.endIndex >= index + 3 + dataLength
            else { return nil }

            let base32Data = data[index + 3..<index + 3 + dataLength]

            index += 3 + dataLength

            if let type = type {
                switch type {
                case .fieldTypeP:
                    guard invoice.paymentHash == nil else { break }
                    invoice.paymentHash = parsePaymentHash(data: base32Data)
                case .fieldTypeD:
                    guard invoice.description == nil else { break }
                    invoice.description = parseDescription(data: base32Data)
                case .fieldTypeX:
                    guard invoice.expiry == nil else { break }
                    invoice.expiry = parseExpiry(data: base32Data)
//                case .fieldTypeF:
//                    guard invoice.fallbackAddress == nil else { break }
//                    invoice.fallbackAddress = parseFallbackAddress(data: base32Data, network: invoice.network)
                case .fieldTypeF, .fieldTypeN, .fieldTypeH, .fieldTypeC, .fieldTypeR:
                    break
                }
            }
        }

        return invoice
    }

    private static func base32ToUInt(_ data: Data) -> UInt {
        var result: UInt = 0
        for byte in data {
            result = result << 5 | UInt(byte)
        }
        return result
    }

    private static func parseFieldDataLength(_ data: Data) -> Int? {
        guard data.count == 2 else { return nil }
        return Int(data[data.startIndex]) << 5 | Int(data[data.startIndex + 1])
    }

    private static func parseDescription(data: Data) -> String? {
        guard let base256Data = data.convertBits(fromBits: 5, toBits: 8, pad: false) else { return nil }
        return String(data: base256Data, encoding: .utf8)
    }

    private static func parseExpiry(data: Data) -> TimeInterval {
        return TimeInterval(base32ToUInt(data))
    }

    private static func parsePaymentHash(data: Data) -> Data? {
        guard data.count == hashBase32Len else { return nil }
        return data.convertBits(fromBits: 5, toBits: 8, pad: false)
    }

//    private static func parseFallbackAddress(data: Data, network: Network) -> BitcoinAddress? {
//        guard data.count >= 2 else { return nil }
//        let version = data[data.startIndex]
//        guard let data = data[(data.startIndex + 1)...].convertBits(fromBits: 5, toBits: 8, pad: false) else { return nil }
//
//        switch version {
//        case 0:
//            if data.count == 20 {
//                return BitcoinAddress(witnessPubKeyHash: data, network: network)
//            } else if data.count == 32 {
//                return BitcoinAddress(witnessScriptHash: data, network: network)
//            } else {
//                return nil
//            }
//        case 17:
//            return BitcoinAddress(pubKeyHash: data, network: network)
//        case 18:
//            return BitcoinAddress(scriptHashFromHash: data, network: network)
//        default:
//            return nil
//        }
//    }

    private static func decodeAmount(for humanReadablePart: String, network: Network) -> Satoshi? {
        let netPrefixLength = Prefix.forNetwork(network).rawValue.count
        var amountString = humanReadablePart[humanReadablePart.index(humanReadablePart.startIndex, offsetBy: netPrefixLength)..<humanReadablePart.endIndex]

        guard amountString.count >= 2 else { return nil }

        let lastCharacter = amountString.removeLast()

        guard
            let multiplier = Multiplier(rawValue: lastCharacter),
            let amount = Int(amountString)
            else { return nil }

        return Decimal(amount) * multiplier.value
    }

    private static func decodeNetwork(humanReadablePart: String) -> Network? {
        if humanReadablePart.starts(with: Prefix.forNetwork(.mainnet).rawValue) {
            return .mainnet
        } else if humanReadablePart.starts(with: Prefix.forNetwork(.testnet).rawValue) {
            return .testnet
        } else if humanReadablePart.starts(with: Prefix.forNetwork(.simnet).rawValue) {
            return .simnet
        }
        return nil
    }
}


public enum Network: String, Codable, CaseIterable {
    case regtest
    case testnet
    case mainnet
    case simnet
}


private extension Network {
    var pubKeyHashAddressID: Int {
        switch self {
        case .simnet:
            return 0x3f // starts with S
        case .testnet, .regtest:
            return 0x6f // starts with m or n
        case .mainnet:
            return 0x00 // starts with 1
        }
    }

    var scriptHashAddressID: Int {
        switch self {
        case .simnet:
            return 0x7b // starts with s
        case .testnet, .regtest:
            return 0xc4 // starts with 2
        case .mainnet:
            return 0x05 // starts with 3
        }
    }
}

/// Represents p2pkh, p2sh & bech32 bitcoin addresses
//public struct BitcoinAddress: Codable, Equatable, Hashable {
//    public enum AddressType {
//        case p2pkh
//        case p2sh
//        case bech32
//    }
//
//    public let string: String
//    public let network: Network
//    public let type: AddressType
//
//    public init?(witnessPubKeyHash: Data, network: Network) {
//        guard
//            witnessPubKeyHash.count == 20,
//            let address = Bech32Address(network: network, witnessVersion: 0x00, witnessProgram: witnessPubKeyHash)?.string
//            else { return nil }
//
//        self.network = network
//        self.string = address
//        self.type = .bech32
//    }
//
//    public init?(witnessScriptHash: Data, network: Network) {
//        guard
//            witnessScriptHash.count == 32,
//            let address = Bech32Address(network: network, witnessVersion: 0x00, witnessProgram: witnessScriptHash)?.string
//            else { return nil }
//
//        self.network = network
//        self.string = address
//        self.type = .bech32
//    }
//
//    public init?(pubKeyHash: Data, network: Network) {
//        guard pubKeyHash.count == 20 else { return nil }
//        self.network = network
//        self.type = .p2pkh
//        self.string = Base58.checkEncode(pubKeyHash, version: network.pubKeyHashAddressID)
//    }
//
//    public init?(scriptHashFromHash: Data, network: Network) {
//        self.network = network
//        self.type = .p2sh
//        self.string = Base58.checkEncode(scriptHashFromHash, version: network.scriptHashAddressID)
//    }
//
//    public init?(string: String) {
//        if let legacyAddress = LegacyBitcoinAddress(string: string) {
//            switch legacyAddress.type {
//            case .pubkeyHash:
//                type = .p2pkh
//            case .scriptHash:
//                type = .p2sh
//            default:
//                return nil
//            }
//
//            network = legacyAddress.network
//        } else if let bech32Address = Bech32Address(string: string) {
//            type = .bech32
//
//            network = bech32Address.network
//        } else {
//            return nil
//        }
//
//        self.string = string
//    }
//
//    // MARK: Codable
//
//    enum CodingKeys: String, CodingKey {
//        case string
//    }
//
//    public init(from decoder: Decoder) throws {
//        let values = try decoder.container(keyedBy: CodingKeys.self)
//        string = try values.decode(String.self, forKey: .string)
//
//        guard let address = BitcoinAddress(string: string) else {
//            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid Bitcoin Address")
//        }
//
//        self.network = address.network
//        self.type = address.type
//    }
//
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(string, forKey: .string)
//    }
//}


public typealias Satoshi = Decimal

public extension Satoshi {
    func rounded() -> Satoshi {
        var value = self
        var result: Decimal = 0
        NSDecimalRound(&result, &value, 0, .bankers)
        return result
    }

    var int64: Int64 {
        return Int64(truncating: self.rounded() as NSDecimalNumber)
    }
}

private extension Network {
    var bech32Prefix: String {
        switch self {
        case .regtest:
            return "bcrt"
        case .testnet:
            return "tb"
        case .mainnet:
            return "bc"
        case .simnet:
            return "sb"
        }
    }
}

//struct Bech32Address {
//    let string: String
//    let network: Network
//
//    init?(string: String) {
//        guard let (humanReadablePart, _) = try? Bech32.decode(other: string) else { return nil }
//
//        if humanReadablePart.lowercased() == Network.testnet.bech32Prefix {
//            network = .testnet
//        } else if humanReadablePart.lowercased() == Network.mainnet.bech32Prefix {
//            network = .mainnet
//        } else if humanReadablePart.lowercased() == Network.simnet.bech32Prefix {
//            network = .simnet
//        } else {
//            return nil
//        }
//
//        self.string = string
//
//        guard self.decode() != nil else { return nil }
//    }
//
//    init?(network: Network, witnessVersion: Int, witnessProgram: Data) {
//        guard let converted = witnessProgram.convertBits(fromBits: 8, toBits: 5, pad: true) else { return nil }
//        let data = Data([UInt8(witnessVersion)]) + converted
//        self.network = network
//        self.string = Bech32.encode(humanReadablePart: network.bech32Prefix, data: data)
//    }
//
//    func decode() -> (version: Int, program: Data)? {
//        guard let dec = Bech32.decode(string) else { return nil }
//
//        if dec.humanReadablePart != network.bech32Prefix || dec.data.count < 1 || dec.data[0] > 16 {
//            return nil
//        }
//        guard let res = dec.data.advanced(by: 1).convertBits(fromBits: 5, toBits: 8, pad: false) else {
//            return nil
//        }
//        if res.count < 2 || res.count > 40 {
//            return nil
//        }
//        if dec.data[0] == 0 && res.count != 20 && res.count != 32 {
//            return nil
//        }
//        return (version: Int(dec.data[0]), program: res)
//    }
//}


//struct LegacyBitcoinAddress {
//    private enum AddressTypeVersion: Int {
//        case pubkeyHash = 0
//        case scriptHash = 5
//        case privateKey = 128
//
//        case testnetPubkeyHash = 111
//        case testnetScriptHash = 196
//        case testnetPrivateKey = 239
//
//        case simnetPubkeyHash = 63
//        case simnetScriptHash = 123
//        case simnetPrivateKey = 100
//    }
//
//    enum AddressType {
//        case pubkeyHash
//        case scriptHash
//        case privateKey
//    }
//
//    let string: String
//    let network: Network
//    let type: AddressType
//
//    init?(string: String) {
//        guard
//            let (version, _) = Base58.checkDecode(string),
//            let typeVersion = AddressTypeVersion(rawValue: version)
//            else { return nil }
//
//        self.string = string
//
//        switch typeVersion {
//        case .pubkeyHash:
//            type = .pubkeyHash
//            network = .mainnet
//        case .scriptHash:
//            type = .scriptHash
//            network = .mainnet
//        case .privateKey:
//            type = .privateKey
//            network = .mainnet
//        case .testnetPubkeyHash:
//            type = .pubkeyHash
//            network = .testnet
//        case .testnetScriptHash:
//            type = .scriptHash
//            network = .testnet
//        case .testnetPrivateKey:
//            type = .privateKey
//            network = .testnet
//        case .simnetPubkeyHash:
//            type = .pubkeyHash
//            network = .simnet
//        case .simnetScriptHash:
//            type = .scriptHash
//            network = .simnet
//        case .simnetPrivateKey:
//            type = .privateKey
//            network = .simnet
//        }
//    }
//}



//extension Data {
//    public init?(base58Encoded base64String: String) {
//        var answer = BigUInt(0)
//        // swiftlint:disable:next identifier_name
//        var j = BigUInt(1)
//
//        for character in base64String.reversed() {
//            guard let tmp = Base58.alphabet.indexDistance(of: character) else { return nil }
//            answer += (BigUInt(tmp) * j)
//            j *= 58
//        }
//
//        let leadingZeros = base64String.prefix(while: { $0 == "1" }).count
//        let prefix = Data([UInt8](repeating: 0, count: leadingZeros))
//
//        self = prefix + answer.serialize()
//    }
//
//    func base58EncodedString() -> String {
//        var data = BigUInt(self)
//        var result = ""
//
//        while data > 0 {
//            let mod = data % 58
//            data /= 58
//
//            let index = Base58.alphabet.index(Base58.alphabet.startIndex, offsetBy: Int(mod))
//            result += String(Base58.alphabet[index])
//        }
//
//        for byte in self {
//            if byte != 0 {
//                break
//            }
//            result += "1"
//        }
//
//        return String(result.reversed())
//    }
//}

//enum Base58 {
//    fileprivate static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
//
//    // checksum
//
//    private static func checksum(_ input: Data) -> Data {
//        let hashed = input.sha256.sha256
//        return hashed[hashed.startIndex..<hashed.startIndex + 4]
//    }
//
//    static func checkDecode(_ input: String) -> (version: Int, payload: Data)? {
//        guard
//            let decoded = Data(base58Encoded: input),
//            decoded.count >= 5
//            else { return nil }
//
//        let checksum = decoded[decoded.endIndex - 4..<decoded.endIndex]
//        let testData = decoded[decoded.startIndex..<decoded.endIndex - 4]
//
//        if !checksum.elementsEqual(Base58.checksum(Data(testData))) {
//            return nil
//        }
//
//        return (version: Int(decoded[0]), payload: Data(testData.suffix(from: 1)))
//    }
//
//    static func checkEncode(_ input: Data, version: Int) -> String {
//        var input = input
//        input.insert(UInt8(version), at: 0)
//        input.append(self.checksum(input))
//        return input.base58EncodedString()
//    }
//}
