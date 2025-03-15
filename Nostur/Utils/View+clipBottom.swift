//
//  View+clipBottom.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2025.
//

import SwiftUI

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
