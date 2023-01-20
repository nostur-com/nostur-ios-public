//
//  Bytes+HexString.swift
//  iotex-swift
//
//  Created by ququzone on 2019/8/1.
//  Copyright © 2019 IoTeX. All rights reserved.
//

import Foundation

extension Array where Element == Byte {
    
    func hexString() -> String {
        var str = ""
        
        for b in self {
            str += String(format: "%02x", b)
        }
        
        return str
    }
    
    func quantityHexString() -> String {
        var str = ""
        
        // Remove leading zero bytes
        var bytes = self.trimLeadingZeros()
        
        if bytes.count > 0 {
            // If there is one leading zero (4 bit) left, this one removes it
            str += String(bytes[0], radix: 16)
            
            for i in 1..<bytes.count {
                str += String(format: "%02x", bytes[i])
            }
        } else {
            str += "0"
        }
        
        return str
    }
}
