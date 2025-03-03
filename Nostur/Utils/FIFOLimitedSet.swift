//
//  LimitedFIFOQueue.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/03/2025.
//

import Foundation
import Collections

struct FIFOLimitedSet {
    private var deque: Deque<String> // Maintains FIFO order
    private var set: Set<String>     // Tracks membership
    private let maxSize: Int         // Maximum number of items
    
    init(maxSize: Int) {
        self.maxSize = maxSize
        self.deque = Deque()
        self.set = Set()
    }
    
    // Insert a string, evicting the oldest if at capacity
    mutating func insert(_ value: String) {
        // If the value is already in the set, do nothing (or update its position if desired)
        if set.contains(value) {
            return // Or move it to the end by removing and re-adding
        }
        
        // If at capacity, remove the oldest item
        if set.count >= maxSize {
            if let oldest = deque.popFirst() {
                set.remove(oldest)
            }
        }
        
        // Add the new item
        deque.append(value)
        set.insert(value)
    }
    
    // Check if a string is in the set
    func contains(_ value: String) -> Bool {
        return set.contains(value)
    }
    
    // Remove and return the oldest item (optional FIFO dequeue)
    mutating func removeFirst() -> String? {
        if let oldest = deque.popFirst() {
            set.remove(oldest)
            return oldest
        }
        return nil
    }
    
    // Current number of items
    var count: Int {
        return set.count
    }
    
    // Check if empty
    var isEmpty: Bool {
        return set.isEmpty
    }
    
    // Get all elements in FIFO order (for inspection)
    var elements: [String] {
        return Array(deque)
    }
}
