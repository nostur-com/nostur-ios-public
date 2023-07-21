//
//  Date+agoString.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/04/2023.
//

import Foundation

extension Date {
    
    static let secondsInMinute = 60.0
    static let secondsInHour = secondsInMinute * 60.0
    static let secondsInDay = secondsInHour * 24.0
    static let secondsInYear = secondsInDay * 365.0
    
    var agoString: String {
        let timeInterval = Date().timeIntervalSince(self)
        
        if timeInterval >= Self.secondsInYear {
            return String.localizedStringWithFormat("%dy", Int(timeInterval / Self.secondsInYear))
        } else if timeInterval >= Self.secondsInDay {
            return String.localizedStringWithFormat("%dd", Int(timeInterval / Self.secondsInDay))
        } else if timeInterval >= Self.secondsInHour {
            return String.localizedStringWithFormat("%dh", Int(timeInterval / Self.secondsInHour))
        } else if timeInterval >= Self.secondsInMinute {
            return String.localizedStringWithFormat("%dm", Int(timeInterval / Self.secondsInMinute))
        } else {
            return String.localizedStringWithFormat("%ds", Int(timeInterval))
        }
    }
}
