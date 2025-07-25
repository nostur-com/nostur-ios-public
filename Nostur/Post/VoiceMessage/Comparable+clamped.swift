//
//  Comparable+clamped.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/07/2025.
//

import Foundation

// Extension to clamp values
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
