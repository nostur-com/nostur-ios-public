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
        if -timeIntervalSinceNow >= Self.secondsInYear {
            return String.localizedStringWithFormat("%dy", Int(-timeIntervalSinceNow / Self.secondsInYear))
        } else if -timeIntervalSinceNow >= Self.secondsInDay {
            return String.localizedStringWithFormat("%dd", Int(-timeIntervalSinceNow / Self.secondsInDay))
        } else if -timeIntervalSinceNow >= Self.secondsInHour {
            return String.localizedStringWithFormat("%dh", Int(-timeIntervalSinceNow / Self.secondsInHour))
        } else if -timeIntervalSinceNow >= Self.secondsInMinute {
            return String.localizedStringWithFormat("%dm", Int(-timeIntervalSinceNow / Self.secondsInMinute))
        } else {
            return String.localizedStringWithFormat("%ds", Int(-timeIntervalSinceNow))
        }
    }
}
