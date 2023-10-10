//
//  ThreadWarning.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/06/2023.
//

import Foundation
import SwiftUI

struct ThreadWarning {
    static func which(_ description:String? = "") {
        if (Thread.isMainThread) {
            print ("🟢🟢🟢🟢🟢 MAIN 🟢🟢🟢🟢🟢 \(description!) 💖💖💖")
        }
        else {
            print ("🟡🟡🟡🟡 NOT MAIN: \(Thread.current.description) 🟡🟡🟡🟡 \(description!) 💖💖💖")
        }
    }
    
    static func shouldBeMain(_ description:String? = "") {
        if (Thread.isMainThread) {
            return
        }
        print("🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡 \(Thread.current.description)")
        print("🟡🟡🟡 Main thread expected, but was not in main!  🟡🟡🟡 \(description!)")
        print("🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡🟡")
    }
    static func shouldNotBeMain(_ description:String? = "") {
        if (!Thread.isMainThread) {
            return
        }
        print("🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴")
        print("🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴")
        print("🔴🔴🔴 Should not be in main, but was main!  🔴🔴🔴")
        print("🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴 \(description!)")
        print("🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴")
    }
}


func shouldBeBg() {
#if DEBUG
    if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
        fatalError("Should only be called from bg()")
    }
#endif
}

func shouldBeMain() {
    #if DEBUG
    if !Thread.isMainThread {
        fatalError("Should be bg")
    }
    #endif
}

