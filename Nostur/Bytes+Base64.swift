//
//  String+Base64.swift
//  iotex-antenna-swift
//
//  Created by ququzone on 2019/12/20.
//  Copyright © 2019 IoTeX. All rights reserved.
//

import Foundation

/*
public extension String {
    func fromBase64() -> String? {
        var origin = String(self)
        
        origin = origin.replacingOccurrences(of: "-", with: "+")
        origin = origin.replacingOccurrences(of: "_", with: "/")
        while origin.count % 4 != 0 {
            origin = origin.appending("=")
        }
        
        guard let data = Data(base64Encoded: origin) else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    func toBase64() -> String {
        var result = Data(self.utf8).base64EncodedString()
        result = result.replacingOccurrences(of: "+", with: "-")
        result = result.replacingOccurrences(of: "/", with: "_")
        result = result.replacingOccurrences(of: "=", with: "")
        return result
    }
}
*/

public extension Array where Element == UInt8 {
    func toSafeBase64() -> String {
        var data = Data(self).base64EncodedString()
        data = data.replacingOccurrences(of: "+", with: "-")
        data = data.replacingOccurrences(of: "/", with: "_")
        data = data.replacingOccurrences(of: "=", with: "")
        return data
    }
    
    init(safeBase64: String) {
        self.init()
        
        var origin = String(safeBase64)
        
        origin = origin.replacingOccurrences(of: "-", with: "+")
        origin = origin.replacingOccurrences(of: "_", with: "/")
        while origin.count % 4 != 0 {
            origin = origin.appending("=")
        }
        
        guard let decodedData = Data(base64Encoded: origin) else {
            return
        }
        
        append(contentsOf: decodedData.bytes)
    }
}
