//
//  Deduplicator.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/10/2024.
//

import Foundation

class Deduplicator {
    public var onScreenSeen: Set<String> = []
    static let shared = Deduplicator()
    private init() { }
}
