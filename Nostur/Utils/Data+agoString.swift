//
//  Date+agoString.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/04/2023.
//

import Foundation

extension Date {

    static let dayString = String(localized: "d", comment: "short for days (ago), appended to number. Example: 2d")
    static let hourString = String(localized: "h", comment: "short for hours (ago), appended to number. Example: 7h")
    static let minuteString = String(localized: "m", comment: "short for minutes (ago), appended to number. Example: 3m")
    static let secondString = String(localized: "s", comment: "short for seconds (ago), appended to number. Example: 15s")
    
    static let secondsInMinute = 60.0
    static let secondsInHour = 3600.0
    static let secondsInDay = 86_400.0
    static let secondsInYear = 31_536_000.0
    
    var agoString: String {
        if -timeIntervalSinceNow >= Self.secondsInDay {
            return (String(Int(-timeIntervalSinceNow / Self.secondsInDay)) + Self.dayString)
        } else if -timeIntervalSinceNow >= Self.secondsInHour {
            return (String(Int(-timeIntervalSinceNow / Self.secondsInHour)) + Self.hourString)
        } else if -timeIntervalSinceNow >= Self.secondsInMinute {
            return (String(Int(-timeIntervalSinceNow / Self.secondsInMinute)) + Self.minuteString)
        } else {
            if -timeIntervalSinceNow <= 30 {
                return String(localized: "just now", comment: "Time ago (less than 30 seconds)" )
            }
            return (String(max(1,Int(-timeIntervalSinceNow / 1.0))) + Self.secondString)
        }
    }
}
