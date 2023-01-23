//
//  Queue.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2023.
//

import Foundation

actor Queue<T> {
    private var elements: [T] = []
    var count:Int { get { elements.count } }
    
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
