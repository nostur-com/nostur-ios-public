//
//  MessageBucket.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2023.
//

import Foundation

class ThreadSafeFIFOQueue<T> {
    private var queue: [T]
    private var isImporting_ = false
    private var needsImport_ = false
    private let accessQueue: DispatchQueue

    init() {
        queue = []
        accessQueue = DispatchQueue(label: "com.nostur.ThreadSafeFIFOQueue", attributes: .concurrent)
    }
    
    var needsImport:Bool {
        get {
            accessQueue.sync {
                return self.needsImport_
            }
        }
        set {
            accessQueue.async(flags: .barrier) {
                self.needsImport_ = newValue
            }
        }
    }
    
    var isImporting:Bool {
        get {
            accessQueue.sync {
                return self.isImporting_
            }
        }
        set {
            accessQueue.async(flags: .barrier) {
                self.isImporting_ = newValue
            }
        }
    }

    func addMessage(_ element: T) {
        accessQueue.async(flags: .barrier) {
            self.queue.append(element)
        }
    }

    func takeMessage() -> T? {
        var element: T?
        accessQueue.sync(flags: .barrier) {
            guard !self.queue.isEmpty else { return }
            element = self.queue.removeFirst()
        }
        return element
    }

    func isEmpty() -> Bool {
        var result = false
        accessQueue.sync {
            result = self.queue.isEmpty
        }
        return result
    }

    func all() -> [T] {
        var items: [T] = []
        accessQueue.sync {
            items = self.queue
        }
        return items
    }
    
    var count:Int {
        accessQueue.sync {
            return self.queue.count
        }
    }
}
