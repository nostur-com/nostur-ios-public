//
//  View+PulseEffect.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/06/2025.
//

import SwiftUI

struct PulseEffect: ViewModifier {
    @State private var pulseIsInMaxState: Bool = true
    private let range: ClosedRange<Double>
    private let duration: TimeInterval

    init(range: ClosedRange<Double>, duration: TimeInterval) {
        self.range = range
        self.duration = duration
    }

    func body(content: Content) -> some View {
        content
            .opacity(pulseIsInMaxState ? range.upperBound : range.lowerBound)
            .onAppear { pulseIsInMaxState = false }
            .animation(.smooth(duration: duration).repeatForever(), value: pulseIsInMaxState)
    }
}

public extension View {
    func pulseEffect(range: ClosedRange<Double> = 0.7...1, duration: TimeInterval = 0.08) -> some View  {
        modifier(PulseEffect(range: range, duration: duration))
    }
}

#Preview("Pulse Effect") {
    Text("Hello, world!")
        .pulseEffect()
}
