//
//  HexEncoding.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/07/2023.
//

import Foundation

extension Data {

    // Should test which one is faster, this or below
    public func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
    
    // https://stackoverflow.com/a/62465044
    var hexEncodedString2: String {
        return self.reduce(into:"") { result, byte in
            result.append(String(byte >> 4, radix: 16))
            result.append(String(byte & 0x0f, radix: 16))
        }
    }
    
    // CHATGPT3.5
    public func makeBytes() -> [UInt8] {
        var array = Array<UInt8>(repeating: 0, count: count)
        array.withUnsafeMutableBytes { buffer in
            _ = copyBytes(to: buffer)
        }
        return array
    }
    
}

extension Array where Element == UInt8 {
    
    func hexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

// https://stackoverflow.com/a/43360864
/**
 let hexaString = "e0696349774606f1b5602ffa6c2d953f"
 do {
     let bytes: [UInt8] = try hexaString.hexa()
     print(bytes)
     let data: Data = try hexaString.hexa()
     print(data)
 } catch {
     print(error)
 }
 */
extension String {
    enum DecodingError: Error {
        case invalidHexaCharacter(Character), oddNumberOfCharacters
    }
}

extension Collection {
    func unfoldSubSequences(limitedTo maxLength: Int) -> UnfoldSequence<SubSequence,Index> {
        sequence(state: startIndex) { lowerBound in
            guard lowerBound < endIndex else { return nil }
            let upperBound = index(lowerBound,
                offsetBy: maxLength,
                limitedBy: endIndex
            ) ?? endIndex
            defer { lowerBound = upperBound }
            return self[lowerBound..<upperBound]
        }
    }
}

extension StringProtocol {
    func hexa<D>() throws -> D where D: DataProtocol & RangeReplaceableCollection {
        try .init(self)
    }
}

extension DataProtocol where Self: RangeReplaceableCollection {
    init<S: StringProtocol>(_ hexa: S) throws {
        guard hexa.count.isMultiple(of: 2) else {
            throw String.DecodingError.oddNumberOfCharacters
        }
        self = .init()
        reserveCapacity(hexa.utf8.count/2)
        for pair in hexa.unfoldSubSequences(limitedTo: 2) {
            guard let byte = UInt8(pair, radix: 16) else {
                for character in pair where !character.isHexDigit {
                    throw String.DecodingError.invalidHexaCharacter(character)
                }
                continue
            }
            append(byte)
        }
    }
}

extension String {
    // CHATGPT3.5 version
    func hexToBytes() -> [UInt8] {
        var startIndex = self.startIndex
        return stride(from: 0, to: self.count, by: 2).compactMap { _ in
            let endIndex = self.index(startIndex, offsetBy: 2, limitedBy: self.endIndex) ?? self.endIndex
            defer { startIndex = endIndex }
            return UInt8(self[startIndex..<endIndex], radix: 16)
        }
    }
}
