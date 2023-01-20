//
//  String+Conversion.swift
//  iotex-antenna-swift
//
//  Created by ququzone on 2019/8/9.
//  Copyright © 2019 IoTeX. All rights reserved.
//

import Foundation

public extension String {
    func binaryToHex() -> String {
        var binaryString = self
        if binaryString.count % 8 > 0 {
            binaryString = "0" + binaryString
        }
        let bytesCount = binaryString.count / 8
        return (0..<bytesCount).compactMap({ i in
            let offset = i * 8
            if let str = binaryString.substr(offset, 8), let int = UInt8(str, radix: 2) {
                return String(format: "%02x", int)
            }
            return nil
        }).joined()
    }

    func hexToBinary() -> String {
        return self.hexToBytes().map({ byte in
            return String(byte, radix: 2).paddingLeft(toLength: 8, withPad: "0")
        }).joined()
    }

    func hexToBytes() -> [UInt8] {
        var value = self
        if self.count % 2 > 0 {
            value = "0" + value
        }
        let bytesCount = value.count / 2
        return (0..<bytesCount).compactMap({ i in
            let offset = i * 2
            if let str = value.substr(offset, 2) {
                return UInt8(str, radix: 16)
            }
            return nil
        })
    }

    func substr(_ offset: Int,  _ length: Int) -> String? {
        guard offset + length <= self.count else { return nil }
        let start = index(startIndex, offsetBy: offset)
        let end = index(start, offsetBy: length)
        return String(self[start..<end])
    }
    
    subscript (bounds: CountableClosedRange<Int>) -> String {
        let start = index(self.startIndex, offsetBy: bounds.lowerBound)
        let end = index(self.startIndex, offsetBy: bounds.upperBound)
        return String(self[start...end])
    }
    
    subscript (bounds: CountableRange<Int>) -> String {
        let start = index(self.startIndex, offsetBy: bounds.lowerBound)
        let end = index(self.startIndex, offsetBy: bounds.upperBound)
        return String(self[start..<end])
    }
    
    subscript (bounds: CountablePartialRangeFrom<Int>) -> String {
        let start = index(self.startIndex, offsetBy: bounds.lowerBound)
        let end = self.endIndex
        return String(self[start..<end])
    }

    func paddingLeft(toLength length: Int, withPad character: Character) -> String {
        if self.count < length {
            return String(repeatElement(character, count: length - self.count)) + self
        } else {
            return String(self.prefix(length))
        }
    }

    func paddingLeft(toMultipleOf base: Int, withPad character: Character) -> String {
        let newLength = Int(ceil(Double(count) / Double(base))) * base
        return self.paddingLeft(toLength: newLength, withPad: character)
    }

    func padding(toMultipleOf base: Int, withPad character: Character) -> String {
        let newLength = Int(ceil(Double(count) / Double(base))) * base
        return self.padding(toLength: newLength, withPad: String(character), startingAt: 0)
    }
    
    func interpretAsBinaryData() -> Data? {
        return Data(self.binaryToHex().hexToBytes())
    }
    
    func removeDecimal() -> String {
        if self.contains(".") {
            return self.components(separatedBy: ".").first!
        }
        return self
    }
    
    func stripHexPrefix() -> String {
        if self.hasPrefix("0x") {
            let indexStart = self.index(self.startIndex, offsetBy: 2)
            return String(self[indexStart...])
        }
        return self
    }
}
