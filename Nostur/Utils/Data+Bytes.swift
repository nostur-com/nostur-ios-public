//
//  Data+Bytes.swift
//  iotex-antenna-swift
//
//  Created by ququzone on 2019/8/7.
//  Copyright © 2019 IoTeX. All rights reserved.
//

import Foundation

extension Data {
    
    // This gives warning:
    // Initialization of 'UnsafeMutableBufferPointer<Byte>' (aka 'UnsafeMutableBufferPointer<UInt8>') results in a dangling buffer pointer
//    public func makeBytes() -> Bytes {
//        var array = Bytes(repeating: 0, count: count)
//        let buffer = UnsafeMutableBufferPointer(start: &array, count: count)
//        _ = copyBytes(to: buffer)
//        return array
//    }
    
    // I asked ChatGPT to fix the warning:
    public func makeBytes() -> Bytes {
        var array = Bytes(repeating: 0, count: count)
        array.withUnsafeMutableBytes { buffer in
            _ = copyBytes(to: buffer)
        }
        return array
    }
    
    func bitsInRange(_ startingBit:Int, _ length:Int) -> UInt64? {
        if startingBit + length / 8 > self.count, length > 64, startingBit > 0, length >= 1 {return nil}
        let bytes = self[(startingBit/8) ..< (startingBit+length+7)/8]
        let padding = Data(repeating: 0, count: 8 - bytes.count)
        let padded = bytes + padding
        guard padded.count == 8 else {return nil}
        let pointee = padded.withUnsafeBytes { (body: UnsafeRawBufferPointer) in
            body.baseAddress?.assumingMemoryBound(to: UInt64.self).pointee
        }
        guard let ptee = pointee else {return nil}
        var uintRepresentation = UInt64(bigEndian: ptee)
        uintRepresentation = uintRepresentation << (startingBit % 8)
        uintRepresentation = uintRepresentation >> UInt64(64 - length)
        return uintRepresentation
    }
    
    static func randomBytes(length: Int) -> Data? {
        for _ in 0...1024 {
            var data = Data(repeating: 0, count: length)
            let result = data.withUnsafeMutableBytes { (body: UnsafeMutableRawBufferPointer) -> Int32? in
                if let bodyAddress = body.baseAddress, body.count > 0 {
                    let pointer = bodyAddress.assumingMemoryBound(to: UInt8.self)
                    return SecRandomCopyBytes(kSecRandomDefault, 32, pointer)
                } else {
                    return nil
                }
            }
            if let notNilResult = result, notNilResult == errSecSuccess {
                return data
            }
        }
        return nil
    }
    
//    static func fromHex(_ hex: String) -> Data? {
//        var hex = hex
//        var data = Data()
//        while(hex.count > 0) {
//            let subIndex = hex.index(hex.startIndex, offsetBy: 2)
//            let c = String(hex[..<subIndex])
//            hex = String(hex[subIndex...])
//            var ch: UInt32 = 0
//            Scanner(string: c).scanHexInt32(&ch)
//            var char = UInt8(ch)
//            data.append(&char, count: 1)
//        }
//        return data
//    }
    
    func setLengthLeft(_ toBytes: UInt64, isNegative:Bool = false ) -> Data? {
        let existingLength = UInt64(self.count)
        if (existingLength == toBytes) {
            return Data(self)
        } else if (existingLength > toBytes) {
            return nil
        }
        var data:Data
        if (isNegative) {
            data = Data(repeating: UInt8(255), count: Int(toBytes - existingLength))
        } else {
            data = Data(repeating: UInt8(0), count: Int(toBytes - existingLength))
        }
        data.append(self)
        return data
    }
    
    func setLengthRight(_ toBytes: UInt64, isNegative:Bool = false ) -> Data? {
        let existingLength = UInt64(self.count)
        if (existingLength == toBytes) {
            return Data(self)
        } else if (existingLength > toBytes) {
            return nil
        }
        var data:Data = Data()
        data.append(self)
        if (isNegative) {
            data.append(Data(repeating: UInt8(255), count: Int(toBytes - existingLength)))
        } else {
            data.append(Data(repeating: UInt8(0), count:Int(toBytes - existingLength)))
        }
        return data
    }
}
