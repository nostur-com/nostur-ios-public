//
//  Lightning
//
//  Created by Otto Suess on 09.07.18.
//  Copyright © 2018 Zap. All rights reserved.
//  22/04/2023 Modified by Fabian Lachman to just get the amount/expiry

import Foundation

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
