//
//  Bytes+TrimLeadingZeros.swift
//  iotex-swift
//
//  Created by ququzone on 2019/8/1.
//  Copyright © 2019 IoTeX. All rights reserved.
//

import Foundation

extension Array where Element == Byte {
    
    func trimLeadingZeros() -> Bytes {
        var oldBytes = self
        var bytes = Bytes()
        
        var leading = true
        for i in 0 ..< oldBytes.count {
            if leading && oldBytes[i] == 0x00 {
                continue
            }
            leading = false
            bytes.append(oldBytes[i])
        }
        
        return bytes
    }
}
