import Foundation

extension Date {
    
    var agoString: String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(self)
        
        let secondsInMinute = 60.0
        let secondsInHour = secondsInMinute * 60.0
        let secondsInDay = secondsInHour * 24.0
        let secondsInYear = secondsInDay * 365.0
        
        if timeInterval >= secondsInYear {
            let years = Int(timeInterval / secondsInYear)
            return String(localized:"\(years)y", comment: "Shorthand for years (1y)")
        } else if timeInterval >= secondsInDay {
            let days = Int(timeInterval / secondsInDay)
            return String(localized:"\(days)d", comment: "Shorthand for days (1d)")
        } else if timeInterval >= secondsInHour {
            let hours = Int(timeInterval / secondsInHour)
            return String(localized:"\(hours)h", comment: "Shorthand for hours (1h)")
        } else if timeInterval >= secondsInMinute {
            let minutes = Int(timeInterval / secondsInMinute)
            return String(localized:"\(minutes)m", comment: "Shorthand for minutes (1m)")
        } else {
            let seconds = Int(timeInterval)
            return String(localized:"\(seconds)s", comment: "Shorthand for seconds (1s)")
        }
    }
}
