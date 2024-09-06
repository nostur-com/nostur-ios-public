//
//  Double+clean.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/02/2023.
//

import Foundation

extension Double {
    var clean: String {
        String(format: "%.0f", self)
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
            return self.truncatingRemainder(dividingBy: thousand) == 0 ? String(format: "%.0fK", self / thousand) : String(format: "%.1fK", self / thousand)
        case million..<billion:
            return self.truncatingRemainder(dividingBy: million) == 0 ? String(format: "%.0fM", self / million) : String(format: "%.1fM", self / million)
        case billion..<trillion:
            return self.truncatingRemainder(dividingBy: billion) == 0 ? String(format: "%.0fB", self / billion) : String(format: "%.1fB", self / billion)
        default:
            return self.truncatingRemainder(dividingBy: trillion) == 0 ? String(format: "%.0fT", self / trillion) : String(format: "%.1fT", self / trillion)
        }
    }
}

extension Int {
    
    var satsFormatted: String {
        let thousand = 1000.0
        let million = thousand * thousand
        let billion = million * thousand
        let trillion = billion * thousand

        switch Double(self) {
        case 0..<thousand:
            return String(format: "%.0f", Double(self))
        case thousand..<million:
            return Double(self).truncatingRemainder(dividingBy: thousand) == 0 ? String(format: "%.0fK", Double(self) / thousand) : String(format: "%.1fK", Double(self) / thousand)
        case million..<billion:
            return Double(self).truncatingRemainder(dividingBy: million) == 0 ? String(format: "%.0fM", Double(self) / million) : String(format: "%.1fM", Double(self) / million)
        case billion..<trillion:
            return Double(self).truncatingRemainder(dividingBy: billion) == 0 ? String(format: "%.0fB", Double(self) / billion) : String(format: "%.1fB", Double(self) / billion)
        default:
            return Double(self).truncatingRemainder(dividingBy: trillion) == 0 ? String(format: "%.0fT", Double(self) / trillion) : String(format: "%.1fT", Double(self) / trillion)
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
            return String(format: "%.0f", Double(self))
        case thousand..<million:
            return String(format: "%.1fK", Double(self) / Double(thousand))
        case million..<billion:
            return String(format: "%.1fM", Double(self) / Double(million))
        case billion..<trillion:
            return String(format: "%.1fB", Double(self) / Double(billion))
        default:
            return String(format: "%.1fT", Double(self) / Double(trillion))
        }
    }
    
    var satsFormatted: String { formatNumber }
}
