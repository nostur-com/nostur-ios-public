//
//  AnimatedRedactedPlaceholder.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/05/2023.
//

import SwiftUI

struct ShimmeringPlaceholder: View {
    var body: some View {
        VStack {
            Text("Placeholder Text")
                .shimmer(isActive: true)
        }
    }
}

struct Shimmer: ViewModifier {
    var isActive: Bool
    @State private var opacity = 0.5

    func body(content: Content) -> some View {
        if isActive {
            content
                .redacted(reason: .placeholder).opacity(0)
                .background(Color.gray.opacity(0.3))
                .overlay(Color.gray.opacity(opacity))
                .onAppear {
                    withAnimation(.easeIn(duration: 0.4).repeatForever()) {
                        opacity = 1
                    }
                }
        }
        else {
            content
        }
    }
}

extension View {
    func shimmer(isActive: Bool) -> some View {
        modifier(Shimmer(isActive: isActive))
    }
}

struct ShimmeringPlaceholder_Previews: PreviewProvider {
    static var previews: some View {
        ShimmeringPlaceholder()
    }
}
