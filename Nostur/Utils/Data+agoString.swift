//
//  TimeAgo.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/04/2023.
//

import Foundation


// Yay, we don't need slow SwiftCompactor anymore

extension Date {
    
    var agoString: String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(self)
        
        let secondsInMinute = 60.0
        let secondsInHour = secondsInMinute * 60.0
        let secondsInDay = secondsInHour * 24.0
        
        if timeInterval >= secondsInDay {
            let days = Int(timeInterval / secondsInDay)
            return "\(days)d"
        } else if timeInterval >= secondsInHour {
            let hours = Int(timeInterval / secondsInHour)
            return "\(hours)h"
        } else if timeInterval >= secondsInMinute {
            let minutes = Int(timeInterval / secondsInMinute)
            return "\(minutes)m"
        } else {
            let seconds = Int(timeInterval)
            return "\(seconds)s"
        }
    }
}
