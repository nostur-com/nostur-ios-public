//
//  RecentSet.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/12/2025.
//

import Foundation

final class RecentSet<T: Hashable> {
    private var set = Set<T>()
    private var order = [T]()
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    @discardableResult
    func insert(_ element: T) -> Bool {
        // If already present, move it to the end (most recent)
        if set.contains(element) {
            order.removeAll { $0 == element }
            order.append(element)
            return false // was already in set
        }
        
        // New element
        set.insert(element)
        order.append(element)
        
        // Trim if over capacity
        if order.count > capacity {
            if let oldest = order.first {
                order.removeFirst()
                set.remove(oldest)
            }
        }
        
        return true // newly inserted
    }
    
    func contains(_ element: T) -> Bool {
        return set.contains(element)
    }
    
    var count: Int {
        return set.count
    }
    
    var elements: Set<T> {
        return set
    }
    
    // Most recent first
    var orderedElements: [T] {
        return order
    }
}
