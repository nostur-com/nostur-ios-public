//
//  MessageBucket.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2023.
//

import Foundation
import DequeModule

class MessageBucket {
    
    private var bucket: Deque<RelayMessage> = Deque<RelayMessage>(minimumCapacity: 5000)
//    private var bucket: [RelayMessage] = []
    private var isImporting_:Bool = false
    private let serialQueue = DispatchQueue(label: "com.nostur.messageBucket.serial")
    
    var isImporting:Bool {
        get {
            return serialQueue.sync {
                return isImporting_
            }
        }
        set {
            serialQueue.sync {
                isImporting_ = newValue
            }
        }
    }
    
    func addMessage(_ message: RelayMessage) {
        serialQueue.sync { [weak self] in
            self?.bucket.prepend(message)
        }
    }
    
    func takeMessage() -> RelayMessage? {
        return serialQueue.sync { [weak self] in
            guard let self = self, !self.bucket.isEmpty else {
                return nil
            }
            return self.bucket.popLast()
        }
    }
    
    var count: Int {
        return serialQueue.sync {
            return bucket.count
        }
    }
    
    func all() -> Deque<RelayMessage> {
        return serialQueue.sync {
            return bucket
        }
    }
}
