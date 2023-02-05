//
//  Queue.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2023.
//

import Foundation
import SwiftUI

extension String: Error {}

actor ActorQueue<T> {
    private var elements: [T] = []
    
    init(_ t:[T]? = nil) {
        if (t != nil) {
            self.elements = t!
        }
    }
        
    func count() -> Int {
        return elements.count
    }
    
    func all() -> [T] {
        return elements
    }
    
    func enqueue(_ value: T) {
        elements.append(value)
    }
    
    func dequeue() -> T? {
        guard !elements.isEmpty else {
            return nil
        }
        return elements.removeFirst()
    }
    
    var head: T? {
        return elements.first
    }
    
    var tail: T? {
        return elements.last
    }
}

class Queue<T> {
    private var elements: [T] = []
    var count:Int { get { elements.count } }
    
    var backgroundTaskCounter:UInt = 0
    
    func incrementCounter() {
        backgroundTaskCounter = backgroundTaskCounter + 1
    }
    
    func all() -> [T] {
        return elements
    }
    
    func enqueue(_ value: T) {
        elements.append(value)
    }
    
    func dequeue() -> T? {
        guard !elements.isEmpty else {
            return nil
        }
        return elements.removeFirst()
    }
    
    var head: T? {
        return elements.first
    }
    
    var tail: T? {
        return elements.last
    }
}


struct ThreadWarning {
    
    
    // Do something on main
    // viewContaxt.perform
    
    // Do something in background
    // container.performBackgroundTrask
    
    // Do something in background in serial?
    // container.newBackgroundContext
    
    static func which(_ description:String? = "") {
        if (Thread.isMainThread) {
            print ("🟢🟢🟢🟢🟢 MAIN 🟢🟢🟢🟢🟢 \(description!)")
        }
        else {
            print ("🟡🟡🟡🟡 NOT MAIN: \(Thread.current.description) 🟡🟡🟡🟡 \(description!)")
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
    
//    private func debug(file: String = #file, line: Int = #line, function: String = #function) -> String {
//        return "\(file):\(line) : \(function)"
//    }
}


struct d {
    var t:Int64?
    
    init(_ t:Int64? = nil) {
        self.t = t
    }
    
    init(_ t:NTimestamp? = nil) {
        if (t != nil) {
            self.t = Int64(t!.timestamp)
        }
    }
    
    init(_ t:Int) {
        self.t = Int64(t)
    }
    
    init(_ t:Int? = nil) {
        if (t != nil) {
            self.t = Int64(t!)
        }
    }
    
    var description:String {
        get {
            if (t == nil) { return "?" }
            return Date(timeIntervalSince1970: TimeInterval(t!)).formatted(.dateTime.hour().minute().second())
        }
    }
}


extension Color {
    /// Return a random color
    static var random: Color {
        return Color(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1)
        )
    }
}
