//
//  RelayConnectionStats.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/07/2024.
//

import Foundation

public class RelayConnectionStats: Identifiable {
    public let id: String // should be relay url
    
    public var errors: Int = 0
    public var messages: Int = 0
    public var connected: Int = 0
    
    public var lastErrorMessages: [String] = []
    
    init(id: String) {
        self.id = id
    }
    
    public func addErrorMessage(_ message: String) {
        lastErrorMessages = Array(([String(format: "%@: %@", Date().ISO8601Format(), message)] + lastErrorMessages).prefix(10))
    }
}
