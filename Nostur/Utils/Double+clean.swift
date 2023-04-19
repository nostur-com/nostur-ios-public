//
//  Double+clean.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/02/2023.
//

import Foundation

extension Double {
    var clean: String {
       return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
    }
    
    var satsFormatted: String {
        let thousand = 1000.0
        let million = thousand * thousand
        let billion = million * thousand
        let trillion = billion * thousand

        switch self {
        case 0..<thousand:
            return String(format: "%.0f", self)
        case thousand..<million:
            return String(format: "%.1fK", self / thousand)
        case million..<billion:
            return String(format: "%.1fM", self / million)
        case billion..<trillion:
            return String(format: "%.1fB", self / billion)
        default:
            return String(format: "%.1fT", self / trillion)
        }
    }
}


extension Int64 {
    
    var formatNumber: String {
        let thousand = 1000
        let million = thousand * thousand
        let billion = million * thousand
        let trillion = billion * thousand

        switch Int(self) {
        case 0..<thousand:
            return String(format: "%.0f", self)
        case thousand..<million:
            return String(format: "%.1fK", Int(self) / thousand)
        case million..<billion:
            return String(format: "%.1fM", Int(self) / million)
        case billion..<trillion:
            return String(format: "%.1fB", Int(self) / billion)
        default:
            return String(format: "%.1fT", Int(self) / trillion)
        }
    }
}
