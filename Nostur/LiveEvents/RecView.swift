//
//  RecView.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/09/2024.
//

import SwiftUI

struct RecView: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.red)
                .frame(width: 13, height: 13)

            Text("REC")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(5)
        .background(Color.black.opacity(0.5))
        .cornerRadius(8)
    }
}

#Preview {
    RecView()
}
