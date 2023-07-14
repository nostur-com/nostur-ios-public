//
//  Logger.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/05/2023.
//

import Foundation
import os

class L {
    static let og = Logger(subsystem: "com.nostur.Nostur", category: "Nostur")
    static let sl = Logger(subsystem: "com.nostur.Nostur", category: "SmoothList")
    static let onboarding = Logger(subsystem: "com.nostur.Nostur", category: "Onboarding")
    static let sockets = Logger(subsystem: "com.nostur.Nostur", category: "Sockets")
    static let importing = Logger(subsystem: "com.nostur.Nostur", category: "Importing")
    static let rerender = Logger(subsystem: "com.nostur.Nostur", category: "Rerendering")
    static let maintenance = Logger(subsystem: "com.nostur.Nostur", category: "Maintenance")
    static let fetching = Logger(subsystem: "com.nostur.Nostur", category: "Fetching")
    static let lvm = Logger(subsystem: "com.nostur.Nostur", category: "LVM")
}

