//
//  MessageBucket.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2023.
//

import Foundation
//import DequeModule

//import Collections
//import Dispatch


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


//class ThreadSafeDeque<Element> {
//    private var isImporting_ = false
//    private var deque = Deque<Element>()
//    private let queue = DispatchQueue(label: "nostur.com.ThreadSafeDeque", attributes: .concurrent)
//
////    func append(_ element: Element) {
////        queue.async(flags: .barrier) {
////            self.deque.append(element)
////        }
////    }
//
//    func addMessage(_ element: Element) {
//        queue.async(flags: .barrier) {
//            self.deque.prepend(element)
//        }
//    }
//
////    func popFirst() -> Element? {
////        return queue.sync {
////            return self.deque.popFirst()
////        }
////    }
//
//    func takeMessage() -> Element? {
//        return queue.sync(flags: .barrier) {
//            return self.deque.popLast()
//        }
//    }
//
//    var count: Int {
//        return queue.sync {
//            return self.deque.count
//        }
//    }
//    
//    func all() -> Deque<Element> {
//        return queue.sync {
//            return Deque(self.deque)
//        }
//    }
//    
//    var isImporting:Bool {
//        get {
//            return queue.sync {
//                return self.isImporting_
//            }
//        }
//        set {
//            queue.async(flags: .barrier) {
//                self.isImporting_ = newValue
//            }
//        }
//    }
//}




//class MessageBucket {
//    
//    private var bucket: Deque<RelayMessage> = Deque<RelayMessage>(minimumCapacity: 5000)
////    private var bucket: [RelayMessage] = []
//    private var isImporting_:Bool = false
//    private let serialQueue = DispatchQueue(label: "com.nostur.messageBucket.serial")
//    
//
//    var isImporting:Bool {
//        get { isImporting_ }
////        get {
////            return serialQueue.sync {
////                return isImporting_
////            }
////        }
//        set {
//            serialQueue.sync {
//                isImporting_ = newValue
//            }
//        }
//    }
//    
////    func addMessage(_ message: RelayMessage) {
//////        serialQueue.sync { [weak self] in
////            self.bucket.prepend(message)
//////        }
////    }
////
////    func takeMessage() -> RelayMessage? {
//////        return serialQueue.sync { [weak self] in
////            guard self.bucket.isEmpty else {
////                return nil
////            }
////            return self.bucket.popLast()
//////        }
////    }
//    
//    var count: Int {
////        return serialQueue.sync {
//            return bucket.count
////        }
//    }
//    
//    func all() -> Deque<RelayMessage> {
////        return serialQueue.sync {
//            return bucket
////        }
//    }
//    
//    
//    func addMessage(_ message: RelayMessage) {
//        serialQueue.async {
//            // Make a copy of the deque if it is not uniquely referenced
//            if !bucket.isKnownUniquelyReferenced {
//                bucket = bucket.mutatingCopy()
//            }
//            // Add the message to the deque
//            bucket.append(message)
//        }
//    }
//
//    func takeMessage() -> RelayMessage? {
//        var message: RelayMessage?
//        serialQueue.sync {
//            // Get the first message from the deque
//            message = bucket.first
//            // Remove the message from the deque
//            if message != nil {
//                if !bucket.isKnownUniquelyReferenced {
//                    bucket = bucket.mutatingCopy()
//                }
//                _ = bucket.removeFirst()
//            }
//        }
//        return message
//    }
//}
