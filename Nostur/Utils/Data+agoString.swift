//
//  Date+agoString.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/04/2023.
//

import Foundation

extension Date {
    static let timeUnits: [(Double, String)] = [
        (365.0 * 24.0 * 60.0 * 60.0, "%dy"),
        (24.0 * 60.0 * 60.0, "%dd"),
        (60.0 * 60.0, "%dh"),
        (60.0, "%dm"),
        (1.0, "%ds")
    ]
    
    var agoString: String {
        let interval = -timeIntervalSinceNow
        for (unitSeconds, format) in Self.timeUnits {
            if interval >= unitSeconds {
                return String.localizedStringWithFormat(format, Int(interval / unitSeconds))
            }
        }
        return "now"
    }
}
