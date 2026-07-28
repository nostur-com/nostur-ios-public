//
//  View+clipBottom.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2025.
//

import SwiftUI

/// When a nested post expands, ancestors can lift their bottom clip without setting their own showMore.
struct NestedContentExpandedPreferenceKey: PreferenceKey {
    static let defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func clipBottom(height: CGFloat) -> some View {
        self.mask(
            VStack {
                Rectangle()
                    .padding(.horizontal, -10)
                    .frame(height: height)
                // Full view rectangle
                Spacer() // Clip height, adjust as needed
            }
        )
    }
}
