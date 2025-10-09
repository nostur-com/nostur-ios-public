//
//  View+wowBackground.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import SwiftUI

extension View {
    public func wowBackground() -> some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.17, green: 0.96, blue: 0.92),
                    Color(red: 0.15, green: 0.48, blue: 0.25)
                    ]),
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .ignoresSafeArea()
            
            self
                .foregroundColor(.white)
        }
    }
}
