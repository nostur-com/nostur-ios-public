//
//  Logger.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/05/2023.
//

import Foundation
import os

class L {
    static let p = OSLog(subsystem: "com.nostur.Nostur", category: "Performance")
    static let og = Logger(subsystem: "com.nostur.Nostur", category: "Nostur")
    static let nests = Logger(subsystem: "com.nostur.Nostur", category: "Nests")
    static let cloud = Logger(subsystem: "com.nostur.Nostur", category: "iCloud")
    static let sl = Logger(subsystem: "com.nostur.Nostur", category: "SmoothList")
    static let onboarding = Logger(subsystem: "com.nostur.Nostur", category: "Onboarding")
    static let sockets = Logger(subsystem: "com.nostur.Nostur", category: "Sockets")
    static let importing = Logger(subsystem: "com.nostur.Nostur", category: "Importing")
    static let rerender = Logger(subsystem: "com.nostur.Nostur", category: "Rerendering")
    static let maintenance = Logger(subsystem: "com.nostur.Nostur", category: "Maintenance")
    static let fetching = Logger(subsystem: "com.nostur.Nostur", category: "Fetching")
    static let lvm = Logger(subsystem: "com.nostur.Nostur", category: "LVM")
    static let user = Logger(subsystem: "com.nostur.Nostur", category: "User Action")
    static let media = Logger(subsystem: "com.nostur.Nostur", category: "Media")
}

func logAction(_ message: String) {
    L.user.info("User: \(message)")
}



// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

#if DEBUG
let IS_SIGNPOST_LOGGING_ENABLED = true
#else
let IS_SIGNPOST_LOGGING_ENABLED = false
#endif

func signpost(_ object: AnyObject, _ name: StaticString, _ type: OSSignpostType) {
    guard IS_SIGNPOST_LOGGING_ENABLED else { return }

    let signpostId = OSSignpostID(log: L.p, object: object)
    os_signpost(type, log: L.p, name: name, signpostID: signpostId)
}

func signpost(_ object: AnyObject, _ name: StaticString, _ type: OSSignpostType, _ message: @autoclosure () -> String) {
    guard IS_SIGNPOST_LOGGING_ENABLED else { return }

    let signpostId = OSSignpostID(log: L.p, object: object)
    os_signpost(type, log: L.p, name: name, signpostID: signpostId, "%{public}s", message())
}

func signpost<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
    try signpost(name, "", work)
}

func signpost<T>(_ name: StaticString, _ message: @autoclosure () -> String, _ work: () throws -> T) rethrows -> T {
    guard IS_SIGNPOST_LOGGING_ENABLED else { return try work() }

    let signpostId = OSSignpostID(log: L.p)
    let message = message()
    if !message.isEmpty {
        os_signpost(.begin, log: L.p, name: name, signpostID: signpostId, "%{public}s", message)
    } else {
        os_signpost(.begin, log: L.p, name: name, signpostID: signpostId)
    }
    let result = try work()
    os_signpost(.end, log: L.p, name: name, signpostID: signpostId)
    return result
}
