//
//  Bytes+UInt.swift
//  iotex-swift
//
//  Created by ququzone on 2019/8/1.
//  Copyright © 2019 IoTeX. All rights reserved.
//

import Foundation

extension Array where Element == Byte {
    
    public var bigEndianUInt: UInt? {
        guard self.count <= MemoryLayout<UInt>.size else {
            return nil
        }
        var number: UInt = 0
        for i in (0 ..< self.count).reversed() {
            number = number | (UInt(self[self.count - i - 1]) << (i * 8))
        }
        
        return number
    }
}
