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


