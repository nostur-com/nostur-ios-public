//
//  Date+agoString.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/04/2023.
//

import Foundation

extension Date {
    
    static let yearString = String(localized: "y", comment: "short for year (ago), appended to number. Example: 1y")
    static let dayString = String(localized: "d", comment: "short for days (ago), appended to number. Example: 2d")
    static let hourString = String(localized: "h", comment: "short for hours (ago), appended to number. Example: 7h")
    static let minuteString = String(localized: "m", comment: "short for minutes (ago), appended to number. Example: 3m")
    static let secondString = String(localized: "s", comment: "short for seconds (ago), appended to number. Example: 15s")
    
    static let secondsInMinute = 60.0
    static let secondsInHour = secondsInMinute * 60.0
    static let secondsInDay = secondsInHour * 24.0
    static let secondsInYear = secondsInDay * 365.0
    
    var agoString: String {
        if -timeIntervalSinceNow >= Self.secondsInYear {
            return (String(Int(-timeIntervalSinceNow / Self.secondsInYear)) + Self.yearString)
        } else if -timeIntervalSinceNow >= Self.secondsInDay {
            return (String(Int(-timeIntervalSinceNow / Self.secondsInDay)) + Self.dayString)
        } else if -timeIntervalSinceNow >= Self.secondsInHour {
            return (String(Int(-timeIntervalSinceNow / Self.secondsInHour)) + Self.hourString)
        } else if -timeIntervalSinceNow >= Self.secondsInMinute {
            return (String(Int(-timeIntervalSinceNow / Self.secondsInMinute)) + Self.minuteString)
        } else {
            if -timeIntervalSinceNow <= 30 {
                return "just now"
            }
            return (String(max(1,Int(-timeIntervalSinceNow / Self.secondsInDay))) + Self.secondString)
        }
    }
}
