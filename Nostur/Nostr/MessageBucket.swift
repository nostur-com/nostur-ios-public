//
//  MessageBucket.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2023.
//

import Foundation

class MessageBucket {
    private var bucket: [RelayMessage] = []
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
        serialQueue.async { [weak self] in
            self?.bucket.append(message)
        }
    }
    
    func takeMessage() -> RelayMessage? {
        return serialQueue.sync { [weak self] in
            guard let self = self, !self.bucket.isEmpty else {
                return nil
            }
            return self.bucket.removeFirst()
        }
    }
    
    var count: Int {
        return serialQueue.sync {
            return bucket.count
        }
    }
    
    func all() -> [RelayMessage] {
        return serialQueue.sync {
            return bucket
        }
    }
}
