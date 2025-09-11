//
//  CloseButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/03/2025.
//

import SwiftUI

struct CloseButton: View {
    
    public let action: () -> Void
    
    var body: some View {
        // Close button
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.title2)
                .padding()
        }
    }
}

#Preview {
    ZStack {
        Color.black
        CloseButton(action: { print("Close button tapped") })
            .foregroundColor(.red)
    }
}
