//
//  UnreadCountBadge.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/08/2026.
//

import SwiftUI

struct UnreadCountBadge: View {
    let count: Int
    var background: Color = .red
    var foreground: Color = .white
    
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(foreground)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, count > 9 ? 4 : 5)
                .padding(.vertical, 2)
                .background(background)
                .clipShape(Capsule())
                .allowsHitTesting(false)
        }
    }
}
